import SwiftUI

struct ContentView: View {
    @EnvironmentObject var tv: TVController
    @EnvironmentObject var discovery: TVDiscovery
    @Environment(\.scenePhase) private var scenePhase
    @State private var triedRediscovery = false

    @State private var showSettings = false
    @State private var showNumbers = false
    @State private var showKeyboard = false

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(white: 0.11), Color(white: 0.03)],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()

            VStack(spacing: 18) {
                header

                HStack {
                    RemoteButton(action: { tv.power() }) {
                        RoundIcon(symbol: "power", tint: .white, fill: Color(red: 0.75, green: 0.12, blue: 0.12))
                    }
                    Spacer()
                    key("rectangle.on.rectangle", "KEY_SOURCE")
                    Spacer()
                    key("gearshape.fill", "KEY_MENU")
                }

                DPad()

                HStack {
                    key("arrow.uturn.backward", "KEY_RETURN")
                    Spacer()
                    key("house.fill", "KEY_HOME")
                    Spacer()
                    key("playpause.fill", "KEY_PLAY")
                }

                HStack(alignment: .center) {
                    Rocker(title: "VOL", upKey: "KEY_VOLUP", downKey: "KEY_VOLDOWN")
                    Spacer()
                    VStack(spacing: 12) {
                        key("speaker.slash.fill", "KEY_MUTE", size: 50)
                        RemoteButton(action: { showNumbers = true }) {
                            RoundIcon(symbol: "circle.grid.3x3.fill", size: 50)
                        }
                    }
                    Spacer()
                    Rocker(title: "CH", upKey: "KEY_CHUP", downKey: "KEY_CHDOWN",
                           upSymbol: "chevron.up", downSymbol: "chevron.down")
                }

                HStack(spacing: 10) {
                    ForEach(StreamingApp.all) { app in
                        RemoteButton(action: { tv.launchApp(app.id) }) {
                            Text(app.name)
                                .font(.footnote.weight(.bold))
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                                .frame(maxWidth: .infinity)
                                .frame(height: 40)
                                .background(Capsule().fill(app.color))
                        }
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 26)
            .padding(.top, 6)
        }
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showSettings) { SettingsView() }
        .sheet(isPresented: $showNumbers) { NumberPadView() }
        .sheet(isPresented: $showKeyboard) { KeyboardView() }
        .onAppear {
            if tv.isConfigured { tv.connect() } else { showSettings = true }
        }
        .onChange(of: tv.status) { status in
            switch status {
            case .connected:
                triedRediscovery = false
            case .failed:
                guard !triedRediscovery, tv.isConfigured else { return }
                triedRediscovery = true
                Task { await followTVToNewAddress() }
            default:
                break
            }
        }
        .onChange(of: scenePhase) { phase in
            switch phase {
            case .active: if tv.isConfigured { tv.connect() }
            case .background: tv.disconnect()
            default: break
            }
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(statusColor)
                .frame(width: 10, height: 10)
            VStack(alignment: .leading, spacing: 1) {
                Text(tv.tvName ?? "Samsung TV")
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Text(tv.statusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            .onTapGesture { if tv.status != .connected { tv.reconnect() } }
            Spacer()
            Button { showKeyboard = true } label: {
                Image(systemName: "keyboard").font(.title3)
            }
            .padding(.trailing, 6)
            Button { showSettings = true } label: {
                Image(systemName: "slider.horizontal.3").font(.title3)
            }
        }
        .foregroundStyle(.white)
    }

    /// If the router gave the TV a new IP, find it again and reconnect.
    private func followTVToNewAddress() async {
        await discovery.scan(knownIP: tv.ipAddress)
        let candidates = discovery.found.filter { $0.ip != tv.ipAddress }
        let match = candidates.first { $0.name == tv.tvName } ?? (discovery.found.count == 1 ? candidates.first : nil)
        if let match {
            tv.ipAddress = match.ip
            tv.reconnect()
        }
    }

    private var statusColor: Color {
        switch tv.status {
        case .connected: return .green
        case .connecting, .awaitingApproval: return .yellow
        case .failed: return .red
        case .disconnected, .notConfigured: return .gray
        }
    }

    private func key(_ symbol: String, _ code: String, size: CGFloat = 58) -> some View {
        RemoteButton(action: { tv.press(code) }) {
            RoundIcon(symbol: symbol, size: size)
        }
    }
}
