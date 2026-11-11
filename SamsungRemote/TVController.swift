import Foundation
import Network

/// Talks to a 2016+ Samsung Tizen TV (e.g. QN85BA) over its local remote-control API.
///
/// Protocol summary:
///  - Secure WebSocket: wss://<tv-ip>:8002/api/v2/channels/samsung.remote.control?name=<base64>&token=<token>
///  - First connection shows an "Allow" prompt on the TV; the TV then returns a token we save,
///    so later connections are silent.
///  - Device info (name, MAC for Wake-on-LAN): http://<tv-ip>:8001/api/v2/
@MainActor
final class TVController: NSObject, ObservableObject {

    enum Status: Equatable {
        case notConfigured
        case disconnected
        case connecting
        case awaitingApproval
        case connected
        case failed(String)
    }

    @Published private(set) var status: Status = .disconnected
    @Published private(set) var tvName: String?
    @Published var ipAddress: String {
        didSet { defaults.set(ipAddress, forKey: Keys.ip) }
    }

    private enum Keys {
        static let ip = "tvIP"
        static let token = "tvToken"
        static let mac = "tvMAC"
        static let name = "tvName"
    }

    private let defaults = UserDefaults.standard
    private let clientName = "iPhone Remote"
    private var session: URLSession!
    private var socket: URLSessionWebSocketTask?
    private var pending: [[String: Any]] = []

    private var token: String? {
        get { defaults.string(forKey: Keys.token) }
        set { defaults.set(newValue, forKey: Keys.token) }
    }

    private var macAddress: String? {
        get { defaults.string(forKey: Keys.mac) }
        set { defaults.set(newValue, forKey: Keys.mac) }
    }

    var isConfigured: Bool {
        !ipAddress.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var statusText: String {
        switch status {
        case .notConfigured: return "Set up your TV"
        case .disconnected: return "Not connected"
        case .connecting: return "Connecting…"
        case .awaitingApproval: return "Choose “Allow” on your TV"
        case .connected: return "Connected"
        case .failed(let message): return message
        }
    }

    override init() {
        ipAddress = UserDefaults.standard.string(forKey: Keys.ip) ?? ""
        tvName = UserDefaults.standard.string(forKey: Keys.name)
        super.init()
        session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
        if !isConfigured { status = .notConfigured }
    }

    // MARK: - Connection

    func connect() {
        let ip = ipAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !ip.isEmpty else { status = .notConfigured; return }
        if socket != nil, status == .connected || status == .connecting || status == .awaitingApproval { return }

        closeSocket()

        var components = URLComponents()
        components.scheme = "wss"
        components.host = ip
        components.port = 8002
        components.path = "/api/v2/channels/samsung.remote.control"
        var query = [URLQueryItem(name: "name", value: Data(clientName.utf8).base64EncodedString())]
        if let token { query.append(URLQueryItem(name: "token", value: token)) }
        components.queryItems = query

        guard let url = components.url else {
            status = .failed("That IP address doesn't look right.")
            return
        }

        let task = session.webSocketTask(with: url)
        socket = task
        status = token == nil ? .awaitingApproval : .connecting
        task.resume()
        listen(on: task)

        Task { await fetchDeviceInfo(ip: ip) }
    }

    func reconnect() {
        closeSocket()
        status = .disconnected
        connect()
    }

    func disconnect() {
        closeSocket()
        pending.removeAll()
        status = isConfigured ? .disconnected : .notConfigured
    }

    /// Clears the saved pairing so the TV asks for permission again.
    func forgetTV() {
        closeSocket()
        pending.removeAll()
        token = nil
        macAddress = nil
        tvName = nil
        defaults.removeObject(forKey: Keys.name)
        status = isConfigured ? .disconnected : .notConfigured
    }

    private func closeSocket() {
        socket?.cancel(with: .goingAway, reason: nil)
        socket = nil
    }

    private func listen(on task: URLSessionWebSocketTask) {
        task.receive { [weak self] result in
            Task { @MainActor [weak self] in
                guard let self, self.socket === task else { return }
                switch result {
                case .success(let message):
                    switch message {
                    case .string(let text): self.handle(text)
                    case .data(let data): self.handle(String(decoding: data, as: UTF8.self))
                    @unknown default: break
                    }
                    self.listen(on: task)
                case .failure(let error):
                    self.socket = nil
                    self.pending.removeAll()
                    self.status = .failed(Self.describe(error))
                }
            }
        }
    }

    private func handle(_ text: String) {
        guard let data = text.data(using: .utf8),
              let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let event = json["event"] as? String else { return }

        switch event {
        case "ms.channel.connect":
            if let info = json["data"] as? [String: Any], let newToken = info["token"] {
                token = "\(newToken)"
            }
            status = .connected
            flushPending()
        case "ms.channel.unauthorized":
            token = nil
            closeSocket()
            status = .failed("The TV denied access. Tap Connect, then choose Allow on the TV.")
        case "ms.channel.timeOut":
            closeSocket()
            status = .failed("No answer to the TV's prompt. Tap Connect and try again.")
        default:
            break
        }
    }

    private static func describe(_ error: Error) -> String {
        let code = (error as NSError).code
        switch code {
        case NSURLErrorTimedOut, NSURLErrorCannotConnectToHost, NSURLErrorNetworkConnectionLost,
             NSURLErrorNotConnectedToInternet, NSURLErrorCannotFindHost:
            return "Can't reach the TV. Check it's on and on the same Wi‑Fi."
        default:
            return "Disconnected (\(error.localizedDescription))"
        }
    }

    // MARK: - Commands

    /// Sends a remote key, e.g. "KEY_VOLUP". Reconnects automatically if the link dropped.
    func press(_ key: String) {
        enqueue([
            "method": "ms.remote.control",
            "params": [
                "Cmd": "Click",
                "DataOfCmd": key,
                "Option": "false",
                "TypeOfRemote": "SendRemoteKey"
            ]
        ])
    }

    func launchApp(_ appID: String) {
        enqueue([
            "method": "ms.channel.emit",
            "params": [
                "event": "ed.apps.launch",
                "to": "host",
                "data": ["appId": appID, "action_type": "DEEP_LINK"]
            ]
        ])
    }

    /// Types text into an on-screen keyboard that's open on the TV (e.g. a YouTube search box).
    func sendText(_ text: String) {
        enqueue([
            "method": "ms.remote.control",
            "params": [
                "Cmd": Data(text.utf8).base64EncodedString(),
                "DataOfCmd": "base64",
                "TypeOfRemote": "SendInputString"
            ]
        ])
        enqueue([
            "method": "ms.remote.control",
            "params": ["TypeOfRemote": "SendInputEnd"]
        ])
    }

    /// Turns the TV off when connected; when it's off, sends Wake-on-LAN and reconnects.
    func power() {
        if status == .connected, socket != nil {
            press("KEY_POWER")
            return
        }
        wake()
        connect()
        Task { @MainActor in
            for delay in [4, 8] {
                try? await Task.sleep(nanoseconds: UInt64(delay) * 1_000_000_000)
                if self.status == .connected { return }
                self.reconnect()
            }
        }
    }

    private func enqueue(_ payload: [String: Any]) {
        if status == .connected, let socket {
            send(payload, on: socket)
        } else {
            pending.append(payload)
            if pending.count > 5 { pending.removeFirst() }
            connect()
        }
    }

    private func flushPending() {
        guard let socket else { return }
        let items = pending
        pending.removeAll()
        items.forEach { send($0, on: socket) }
    }

    private func send(_ payload: [String: Any], on socket: URLSessionWebSocketTask) {
        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let text = String(data: data, encoding: .utf8) else { return }
        socket.send(.string(text)) { [weak self] error in
            guard error != nil else { return }
            Task { @MainActor [weak self] in
                guard let self, self.socket === socket else { return }
                // The TV closed an idle connection: reconnect and resend this command once.
                self.socket = nil
                self.status = .disconnected
                self.pending.append(payload)
                self.connect()
            }
        }
    }

    // MARK: - Device info & Wake-on-LAN

    private func fetchDeviceInfo(ip: String) async {
        guard let url = URL(string: "http://\(ip):8001/api/v2/") else { return }
        var request = URLRequest(url: url)
        request.timeoutInterval = 4
        guard let result = try? await URLSession.shared.data(for: request),
              let json = (try? JSONSerialization.jsonObject(with: result.0)) as? [String: Any],
              let device = json["device"] as? [String: Any] else { return }

        if var name = device["name"] as? String {
            name = name.replacingOccurrences(of: "[TV] ", with: "")
            tvName = name
            defaults.set(name, forKey: Keys.name)
        }
        if let mac = device["wifiMac"] as? String, !mac.isEmpty {
            macAddress = mac
        }
    }

    private func wake() {
        guard let mac = macAddress, let packet = Self.magicPacket(for: mac) else { return }
        let ip = ipAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        var targets = [ip]
        var octets = ip.split(separator: ".")
        if octets.count == 4 {
            octets[3] = "255"
            targets.append(octets.joined(separator: "."))
        }
        for target in targets {
            let connection = NWConnection(host: NWEndpoint.Host(target), port: 9, using: .udp)
            connection.start(queue: .global(qos: .userInitiated))
            connection.send(content: packet, completion: .contentProcessed { _ in connection.cancel() })
        }
    }

    private static func magicPacket(for mac: String) -> Data? {
        let bytes = mac
            .split(whereSeparator: { $0 == ":" || $0 == "-" })
            .compactMap { UInt8($0, radix: 16) }
        guard bytes.count == 6 else { return nil }
        var packet = Data(repeating: 0xFF, count: 6)
        for _ in 0..<16 { packet.append(contentsOf: bytes) }
        return packet
    }
}

// MARK: - TLS

extension TVController: URLSessionDelegate {
    /// The TV uses a self-signed certificate on port 8002, so trust it for this local connection.
    nonisolated func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
           let trust = challenge.protectionSpace.serverTrust {
            completionHandler(.useCredential, URLCredential(trust: trust))
        } else {
            completionHandler(.performDefaultHandling, nil)
        }
    }
}
