import SwiftUI
import UIKit

/// A button that reacts on touch-down (like a real remote) and, optionally,
/// repeats while held — used for volume, channel and the arrow keys.
struct RemoteButton<Label: View>: View {
    var repeats: Bool = false
    let action: () -> Void
    @ViewBuilder let label: () -> Label

    @State private var isPressed = false
    @State private var repeatTask: Task<Void, Never>?

    init(repeats: Bool = false, action: @escaping () -> Void, @ViewBuilder label: @escaping () -> Label) {
        self.repeats = repeats
        self.action = action
        self.label = label
    }

    var body: some View {
        label()
            .contentShape(Rectangle())
            .scaleEffect(isPressed ? 0.92 : 1)
            .opacity(isPressed ? 0.65 : 1)
            .animation(.easeOut(duration: 0.08), value: isPressed)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        guard !isPressed else { return }
                        isPressed = true
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        action()
                        if repeats { startRepeating() }
                    }
                    .onEnded { _ in
                        isPressed = false
                        repeatTask?.cancel()
                        repeatTask = nil
                    }
            )
    }

    private func startRepeating() {
        repeatTask?.cancel()
        repeatTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 450_000_000)
            while !Task.isCancelled {
                action()
                try? await Task.sleep(nanoseconds: 130_000_000)
            }
        }
    }
}

enum RemoteStyle {
    static let surface = Color(white: 0.17)
    static let raised = Color(white: 0.25)
}

struct RoundIcon: View {
    let symbol: String
    var size: CGFloat = 58
    var tint: Color = .white
    var fill: Color = RemoteStyle.surface

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.36, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: size, height: size)
            .background(Circle().fill(fill))
    }
}

struct DPad: View {
    @EnvironmentObject var tv: TVController

    var body: some View {
        ZStack {
            Circle()
                .fill(RemoteStyle.surface)
                .overlay(Circle().stroke(Color.white.opacity(0.06), lineWidth: 1))

            VStack {
                arrow("chevron.up", key: "KEY_UP")
                Spacer()
                arrow("chevron.down", key: "KEY_DOWN")
            }
            .padding(.vertical, 6)

            HStack {
                arrow("chevron.left", key: "KEY_LEFT")
                Spacer()
                arrow("chevron.right", key: "KEY_RIGHT")
            }
            .padding(.horizontal, 6)

            RemoteButton(action: { tv.press("KEY_ENTER") }) {
                Circle()
                    .fill(RemoteStyle.raised)
                    .frame(width: 84, height: 84)
                    .overlay(Text("OK").font(.headline))
            }
        }
        .frame(width: 216, height: 216)
    }

    private func arrow(_ symbol: String, key: String) -> some View {
        RemoteButton(repeats: true, action: { tv.press(key) }) {
            Image(systemName: symbol)
                .font(.system(size: 22, weight: .semibold))
                .frame(width: 62, height: 62)
        }
    }
}

/// Vertical +/– pill for volume or channel.
struct Rocker: View {
    @EnvironmentObject var tv: TVController
    let title: String
    let upKey: String
    let downKey: String
    var upSymbol = "plus"
    var downSymbol = "minus"

    var body: some View {
        VStack(spacing: 0) {
            RemoteButton(repeats: true, action: { tv.press(upKey) }) {
                Image(systemName: upSymbol)
                    .font(.system(size: 20, weight: .semibold))
                    .frame(width: 64, height: 50)
            }
            Text(title)
                .font(.caption2.weight(.bold))
                .foregroundStyle(.secondary)
            RemoteButton(repeats: true, action: { tv.press(downKey) }) {
                Image(systemName: downSymbol)
                    .font(.system(size: 20, weight: .semibold))
                    .frame(width: 64, height: 50)
            }
        }
        .padding(.vertical, 4)
        .background(Capsule().fill(RemoteStyle.surface))
    }
}

struct StreamingApp: Identifiable {
    let id: String   // Samsung Tizen app ID
    let name: String
    let color: Color

    static let all: [StreamingApp] = [
        StreamingApp(id: "3201907018807", name: "Netflix", color: Color(red: 0.75, green: 0.04, blue: 0.07)),
        StreamingApp(id: "111299001912", name: "YouTube", color: Color(red: 0.55, green: 0.08, blue: 0.08)),
        StreamingApp(id: "3201910019365", name: "Prime", color: Color(red: 0.0, green: 0.45, blue: 0.65)),
        StreamingApp(id: "3201901017640", name: "Disney+", color: Color(red: 0.08, green: 0.2, blue: 0.5)),
    ]
}
