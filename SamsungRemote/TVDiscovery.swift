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

    /// Common home-router ranges, used if the phone's own address can't be read.
    /// (Bell Home Hub uses 192.168.2.x; Rogers/most others use 192.168.0.x or 1.x; some use 10.0.0.x.)
    private static let fallbackPrefixes = ["192.168.2", "192.168.0", "192.168.1", "10.0.0"]

    func scan(knownIP: String? = nil) async {
        guard !isScanning else { return }

        var prefixes = Self.localSubnetPrefixes()
        if let knownIP, let prefix = Self.prefix(of: knownIP), !prefixes.contains(prefix) {
            prefixes.append(prefix)
        }
        if prefixes.isEmpty { prefixes = Self.fallbackPrefixes }

        isScanning = true
        message = nil

        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 2
        config.timeoutIntervalForResource = 3
        config.httpMaximumConnectionsPerHost = 1
        let session = URLSession(configuration: config)

        let results: [DiscoveredTV] = await withTaskGroup(of: DiscoveredTV?.self) { group in
            for prefix in prefixes {
                for host in 1...254 {
                    let ip = "\(prefix).\(host)"
                    group.addTask { await TVDiscovery.probe(ip: ip, session: session) }
                }
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

    nonisolated static func prefix(of ip: String) -> String? {
        let octets = ip.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: ".")
        guard octets.count == 4, octets.allSatisfy({ UInt8($0) != nil }) else { return nil }
        return octets[0..<3].joined(separator: ".")
    }

    /// The first three parts of every private (home-network) IPv4 address the phone has,
    /// e.g. ["192.168.2"]. Skips cellular (pdp_ip), VPN (utun/ipsec) and loopback interfaces.
    nonisolated static func localSubnetPrefixes() -> [String] {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return [] }
        defer { freeifaddrs(ifaddr) }

        var prefixes: [String] = []
        for pointer in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let interface = pointer.pointee
            let name = String(cString: interface.ifa_name)
            let flags = Int32(interface.ifa_flags)
            guard let address = interface.ifa_addr,
                  address.pointee.sa_family == UInt8(AF_INET),
                  flags & IFF_UP != 0, flags & IFF_LOOPBACK == 0,
                  !name.hasPrefix("pdp_ip"), !name.hasPrefix("utun"), !name.hasPrefix("ipsec") else { continue }

            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            guard getnameinfo(address, socklen_t(address.pointee.sa_len),
                              &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 else { continue }

            let ip = String(cString: host)
            guard isPrivate(ip), let subnet = Self.prefix(of: ip), !prefixes.contains(subnet) else { continue }
            prefixes.append(subnet)
        }
        return prefixes
    }

    nonisolated private static func isPrivate(_ ip: String) -> Bool {
        let o = ip.split(separator: ".").compactMap { Int($0) }
        guard o.count == 4 else { return false }
        return o[0] == 10 || (o[0] == 192 && o[1] == 168) || (o[0] == 172 && (16...31).contains(o[1]))
    }
}
