import SwiftUI

/// Shown on first launch and whenever the app is opened again (from Applications, Spotlight or Launchpad),
/// because the app otherwise only lives in the menu bar and is easy to miss.
struct WelcomeView: View {
    var openSettings: () -> Void
    var showWheel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 56, height: 56)
                VStack(alignment: .leading) {
                    Text("Nirvana Wheel is on").font(.title2.bold())
                    Text("You can close this window: the wheel keeps working. Open the app again (Dock or Spotlight) to come back here.")
                        .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }

            Button { showWheel() } label: {
                Label("Open the Wheel", systemImage: "circle.circle.fill")
                    .font(.title3.bold()).frame(maxWidth: .infinity).padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent).tint(ringAccent).foregroundStyle(.black)
            Text("Opens it with a click: move to an item and click it. Click the middle or press Esc to close.")
                .font(.caption).foregroundStyle(.secondary)

            GroupBox {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Press and **hold** Control ⌃ + Option ⌥ + Space together.", systemImage: "1.circle.fill")
                    Label("Keep holding. The wheel appears where your pointer is.", systemImage: "2.circle.fill")
                    Label("Move the pointer towards an item; it turns yellow.", systemImage: "3.circle.fill")
                    Label("**Let go** of the keys to run it. Let go in the middle to cancel.", systemImage: "4.circle.fill")
                    Label("Items with a small arrow open more: keep moving outwards past them.", systemImage: "arrow.up.right.circle.fill")
                }
                .padding(6)
            } label: { Text("The fast way: the key (from any app)").font(.headline) }

            GroupBox {
                VStack(alignment: .leading, spacing: 6) {
                    tool(.mirror, "Your camera as a mirror: check your hair or framing before a call or recording.")
                    tool(.micCheck, "Shows how loud your microphone is, to check it before recording.")
                    tool(.magnifier, "A zoom lens that follows your pointer, for small details on screen.")
                    Text("macOS asks for permission the first time you open these three.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .padding(6)
            } label: { Text("Try a tool (all 15 are under Tools on the wheel)").font(.headline) }

            HStack {
                Button("Settings…") { openSettings() }
                Spacer()
                Button("Done") { NSApp.keyWindow?.close() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 580)
    }

    private func tool(_ id: MiniAppID, _ text: String) -> some View {
        HStack(alignment: .top) {
            Button { MiniAppHost.shared.open(id) } label: {
                Label(id.title, systemImage: id.symbol).frame(width: 120, alignment: .leading)
            }
            Text(text).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }
}
