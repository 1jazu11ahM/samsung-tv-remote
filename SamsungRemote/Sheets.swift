import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var tv: TVController
    @Environment(\.dismiss) private var dismiss
    @State private var ipDraft = ""

    var body: some View {
        NavigationView {
            Form {
                Section {
                    TextField("e.g. 192.168.1.50", text: $ipDraft)
                        .keyboardType(.numbersAndPunctuation)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button("Connect") {
                        tv.ipAddress = ipDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                        tv.reconnect()
                    }
                    .disabled(ipDraft.trimmingCharacters(in: .whitespaces).isEmpty)
                    HStack {
                        Text("Status")
                        Spacer()
                        Text(tv.statusText)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.trailing)
                    }
                } header: {
                    Text("TV IP address")
                } footer: {
                    Text("On the TV: Settings → General → Network → Network Status → IP Settings. The first time you connect, the TV asks to allow “iPhone Remote” — choose Allow.")
                }

                Section {
                    Text("To turn the TV on from your phone, enable Settings → General → Network → Expert Settings → Power On with Mobile on the TV. Connect once while the TV is on so the app can learn its address.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("Power on")
                }

                Section {
                    Button("Forget this TV", role: .destructive) { tv.forgetTV() }
                }
            }
            .navigationTitle("TV Setup")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .onAppear { ipDraft = tv.ipAddress }
        .onChange(of: tv.status) { status in
            if status == .connected {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { dismiss() }
            }
        }
    }
}

struct NumberPadView: View {
    @EnvironmentObject var tv: TVController
    @Environment(\.dismiss) private var dismiss

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 18), count: 3)

    var body: some View {
        VStack(spacing: 18) {
            Capsule().fill(Color.secondary.opacity(0.4)).frame(width: 40, height: 5).padding(.top, 10)
            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(1...9, id: \.self) { digit($0) }
                textKey("PRE", code: "KEY_PRECH")
                digit(0)
                textKey("GUIDE", code: "KEY_GUIDE")
            }
            .padding(.horizontal, 36)
            Spacer()
        }
        .preferredColorScheme(.dark)
        .presentationDetents([.medium])
    }

    private func digit(_ n: Int) -> some View {
        textKey("\(n)", code: "KEY_\(n)", font: .title2.weight(.semibold))
    }

    private func textKey(_ label: String, code: String, font: Font = .footnote.weight(.bold)) -> some View {
        RemoteButton(action: { tv.press(code) }) {
            Text(label)
                .font(font)
                .frame(width: 70, height: 70)
                .background(Circle().fill(RemoteStyle.surface))
        }
    }
}

struct KeyboardView: View {
    @EnvironmentObject var tv: TVController
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        NavigationView {
            Form {
                Section {
                    TextField("Type here", text: $text)
                        .focused($focused)
                        .submitLabel(.send)
                        .onSubmit(send)
                    Button("Send to TV", action: send)
                        .disabled(text.isEmpty)
                } footer: {
                    Text("Open a search or text box on the TV first (for example in YouTube or Netflix), then send your text.")
                }
            }
            .navigationTitle("Keyboard")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
        .onAppear { focused = true }
    }

    private func send() {
        guard !text.isEmpty else { return }
        tv.sendText(text)
        text = ""
    }
}
