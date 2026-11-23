import AppKit
import SwiftUI

struct ClipEntry: Codable, Identifiable, Equatable {
    var id = UUID()
    var text: String
    var date: Date
    var pinned = false
}

/// Watches the clipboard while the app runs and keeps the last 200 text copies (pinned ones stay).
final class ClipboardStore: ObservableObject {
    static let shared = ClipboardStore()
    @Published private(set) var entries: [ClipEntry] = []
    private var lastChange = NSPasteboard.general.changeCount
    private var timer: Timer?
    private let file = appDataURL("clipboard.json")
    private let limit = 200

    func start() {
        guard timer == nil else { return }
        if let data = try? Data(contentsOf: file), let saved = try? JSONDecoder().decode([ClipEntry].self, from: data) {
            entries = saved
        }
        let t = Timer(timeInterval: 0.6, repeats: true) { [weak self] _ in self?.poll() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func poll() {
        let pb = NSPasteboard.general
        guard pb.changeCount != lastChange else { return }
        lastChange = pb.changeCount
        // Skip what password managers mark as secret.
        let secret = NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")
        if pb.types?.contains(secret) == true { return }
        guard let s = pb.string(forType: .string), !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        add(s)
    }

    func add(_ s: String) {
        if let i = entries.firstIndex(where: { $0.text == s }) {
            var e = entries.remove(at: i); e.date = Date(); entries.insert(e, at: 0)
        } else {
            entries.insert(ClipEntry(text: s, date: Date()), at: 0)
        }
        trim(); save()
    }

    func use(_ e: ClipEntry) {
        copyToClipboard(e.text)
        lastChange = NSPasteboard.general.changeCount
        add(e.text)
    }

    func togglePin(_ e: ClipEntry) {
        guard let i = entries.firstIndex(of: e) else { return }
        entries[i].pinned.toggle(); save()
    }

    func remove(_ e: ClipEntry) { entries.removeAll { $0.id == e.id }; save() }
    func clearUnpinned() { entries.removeAll { !$0.pinned }; save() }

    private func trim() {
        var unpinned = 0
        entries = entries.filter { e in
            if e.pinned { return true }
            unpinned += 1
            return unpinned <= limit
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(entries) { try? data.write(to: file, options: .atomic) }
    }
}

struct ClipboardView: View {
    @ObservedObject private var store = ClipboardStore.shared
    @State private var query = ""
    @FocusState private var focused: Bool

    private var shown: [ClipEntry] {
        let list = query.isEmpty ? store.entries : store.entries.filter { $0.text.localizedCaseInsensitiveContains(query) }
        return list.filter(\.pinned) + list.filter { !$0.pinned }
    }

    var body: some View {
        MiniCard {
            TextField("Search clipboard", text: $query)
                .textFieldStyle(.roundedBorder)
                .focused($focused)
                .onSubmit { if let first = shown.first { pick(first) } }
            if shown.isEmpty {
                Text(store.entries.isEmpty ? "Copy some text and it shows up here." : "Nothing matches.")
                    .foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(shown) { e in
                    HStack(alignment: .top) {
                        if e.pinned { Image(systemName: "pin.fill").foregroundStyle(ringAccent).font(.caption) }
                        Text(e.text.trimmingCharacters(in: .whitespacesAndNewlines))
                            .lineLimit(3).font(.system(size: 12))
                        Spacer()
                        Text(e.date, style: .relative).font(.caption2).foregroundStyle(.tertiary)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { pick(e) }
                    .contextMenu {
                        Button(e.pinned ? "Unpin" : "Pin") { store.togglePin(e) }
                        Button("Delete") { store.remove(e) }
                    }
                }
                .listStyle(.plain)
            }
            HStack {
                Text("Click to copy · right-click to pin").font(.caption).foregroundStyle(.tertiary)
                Spacer()
                Button("Clear") { store.clearUnpinned() }.controlSize(.small)
            }
        }
        .onAppear { focused = true }
    }

    private func pick(_ e: ClipEntry) {
        store.use(e)
        NSApp.keyWindow?.close()
    }
}
