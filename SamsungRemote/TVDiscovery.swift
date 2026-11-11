import Foundation
import Darwin

struct DiscoveredTV: Identifiable, Hashable {
    let ip: String
    let name: String
    var id: String { ip }
}

/// Finds Samsung TVs on the local Wi‑Fi by asking every address on the phone's
/// subnet (x.x.x.1 – x.x.x.254) for the TV info page at http://<ip>:8001/api/v2/.
/// Uses plain unicast requests, so it works without Apple's special multicast entitlement.
@MainActor
final class TVDiscovery: ObservableObject {
    @Published private(set) var found: [DiscoveredTV] = []
    @Published private(set) var isScanning = false
    @Published private(set) var message: String?

    func scan() async {
        guard !isScanning else { return }
        guard let prefix = Self.localSubnetPrefix() else {
            message = "Connect your iPhone to Wi‑Fi first."
            return
        }

        isScanning = true
        message = nil

        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 2
        config.timeoutIntervalForResource = 3
        config.httpMaximumConnectionsPerHost = 1
        let session = URLSession(configuration: config)

        let results: [DiscoveredTV] = await withTaskGroup(of: DiscoveredTV?.self) { group in
            for host in 1...254 {
                let ip = "\(prefix).\(host)"
                group.addTask { await TVDiscovery.probe(ip: ip, session: session) }
            }
            var tvs: [DiscoveredTV] = []
            for await tv in group {
                if let tv { tvs.append(tv) }
            }
            return tvs
        }

        session.invalidateAndCancel()
        found = results.sorted { $0.ip.localizedStandardCompare($1.ip) == .orderedAscending }
        isScanning = false
        if found.isEmpty {
            message = "No TV found. Make sure the TV is on and on the same Wi‑Fi, and that Local Network access is allowed for this app (iPhone Settings → TV Remote)."
        }
    }

    nonisolated static func probe(ip: String, session: URLSession) async -> DiscoveredTV? {
        guard let url = URL(string: "http://\(ip):8001/api/v2/"),
              let result = try? await session.data(from: url),
              let json = (try? JSONSerialization.jsonObject(with: result.0)) as? [String: Any],
              let device = json["device"] as? [String: Any] else { return nil }

        let type = (device["type"] as? String) ?? (json["type"] as? String) ?? ""
        let rawName = (device["name"] as? String) ?? (json["name"] as? String) ?? "Samsung TV"
        guard type.localizedCaseInsensitiveContains("samsung") || rawName.contains("[TV]") else { return nil }

        let name = rawName.replacingOccurrences(of: "[TV] ", with: "")
        return DiscoveredTV(ip: ip, name: name)
    }

    /// Returns the first three parts of the phone's Wi‑Fi IP, e.g. "192.168.1".
    nonisolated static func localSubnetPrefix() -> String? {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return nil }
        defer { freeifaddrs(ifaddr) }

        for pointer in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let interface = pointer.pointee
            guard let address = interface.ifa_addr,
                  address.pointee.sa_family == UInt8(AF_INET),
                  String(cString: interface.ifa_name) == "en0" else { continue }

            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            guard getnameinfo(address, socklen_t(address.pointee.sa_len),
                              &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 else { continue }

            let octets = String(cString: host).split(separator: ".")
            if octets.count == 4 { return octets[0..<3].joined(separator: ".") }
        }
        return nil
    }
}
