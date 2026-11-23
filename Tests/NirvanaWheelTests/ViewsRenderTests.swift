import AppKit
import SwiftUI
import XCTest
@testable import NirvanaWheel

/// Builds each window's view off-screen and lays it out, to catch crashes before they reach the menu bar.
/// Camera, microphone and screen tools are skipped: they ask for permissions when shown.
final class ViewsRenderTests: XCTestCase {
    @MainActor private func render<V: View>(_ v: V, _ size: CGSize = CGSize(width: 760, height: 520)) {
        let host = NSHostingView(rootView: v.frame(width: size.width, height: size.height))
        host.frame = CGRect(origin: .zero, size: size)
        host.layoutSubtreeIfNeeded()
        let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds)!
        host.cacheDisplay(in: host.bounds, to: rep)
        XCTAssertGreaterThan(rep.pixelsWide, 0)
        if let dir = ProcessInfo.processInfo.environment["NR_SNAPSHOT_DIR"] {
            let name = String(describing: V.self).prefix(40).filter { $0.isLetter }
            try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name).png"))
        }
    }

    @MainActor func testSettingsWindowRenders() {
        render(SettingsView(initial: .default) { _ in })
    }

    @MainActor func testRingRenders() {
        let m = RingModel()
        m.items = RingConfig.default.items
        m.visible = true
        m.selected = 2
        render(RingView(model: m), CGSize(width: RingView.size, height: RingView.size))
    }

    @MainActor func testQuietMiniAppsRender() {
        let quiet: [MiniAppID] = [.clipboard, .shelf, .timer, .calculator, .colorPicker, .scratchpad,
                                  .qrMaker, .qrScanner, .audio, .caffeine, .focus, .systemGlance]
        for id in quiet { render(id.makeView(), id.size) }
    }

    func testQRRoundTrip() throws {
        let img = try XCTUnwrap(QR.image(for: "https://example.com/nirvana"))
        let cg = try XCTUnwrap(img.cgImage(forProposedRect: nil, context: nil, hints: nil))
        XCTAssertEqual(QR.decode(cg), ["https://example.com/nirvana"])
    }
}
