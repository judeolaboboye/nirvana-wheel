import XCTest
@testable import NirvanaWheel

final class ProfilesAndWindowsTests: XCTestCase {
    func testOldSingleRingFileStillLoads() throws {
        let json = """
        {"hotkey":{"key":"space","modifiers":["control","option"]},
         "items":[{"title":"Safari","symbol":"safari","action":{"type":"app","value":"/Applications/Safari.app"}}]}
        """
        let cfg = try JSONDecoder().decode(RingConfig.self, from: Data(json.utf8))
        XCTAssertEqual(cfg.profiles.count, 1)
        XCTAssertEqual(cfg.profiles[0].name, "Main")
        XCTAssertEqual(cfg.items.first?.title, "Safari")
        XCTAssertFalse(cfg.trackpadGesture)
        XCTAssertNil(cfg.mouseButton)
    }

    func testProfilesRoundTrip() throws {
        var cfg = RingConfig.default
        cfg.profiles.append(RingProfile(name: "Work", hotkey: HotkeyConfig(key: "w", modifiers: ["control"]), items: []))
        cfg.mouseButton = 3
        cfg.trackpadGesture = true
        let back = try JSONDecoder().decode(RingConfig.self, from: JSONEncoder().encode(cfg))
        XCTAssertEqual(back.profiles.map(\.name), ["Main", "Work"])
        XCTAssertEqual(back.mouseButton, 3)
        XCTAssertTrue(back.trackpadGesture)
    }

    func testWindowTargets() {
        let vf = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let w = CGRect(x: 100, y: 100, width: 400, height: 300)
        XCTAssertEqual(WindowAction.leftHalf.target(window: w, in: vf, next: nil), CGRect(x: 0, y: 0, width: 500, height: 800))
        XCTAssertEqual(WindowAction.rightHalf.target(window: w, in: vf, next: nil), CGRect(x: 500, y: 0, width: 500, height: 800))
        XCTAssertEqual(WindowAction.topHalf.target(window: w, in: vf, next: nil), CGRect(x: 0, y: 400, width: 1000, height: 400))
        XCTAssertEqual(WindowAction.maximize.target(window: w, in: vf, next: nil), vf)
        XCTAssertEqual(WindowAction.center.target(window: w, in: vf, next: nil), CGRect(x: 300, y: 250, width: 400, height: 300))
        XCTAssertEqual(WindowAction.nextScreen.target(window: w, in: vf, next: nil), w) // one display: stays put
        let other = CGRect(x: 1000, y: 0, width: 2000, height: 1600)
        XCTAssertEqual(WindowAction.nextScreen.target(window: w, in: vf, next: other), CGRect(x: 1200, y: 200, width: 800, height: 600))
    }

    func testNestedItemEditing() {
        let root = [RingItem(title: "A", symbol: "a", items: [
            RingItem(title: "B", symbol: "b", items: [RingConfig.item("C", "c", .url, "x")]),
        ])]
        XCTAssertEqual(SettingsView.items(in: root, at: [0, 0]).map(\.title), ["C"])
        let changed = SettingsView.setting([RingConfig.item("D", "d", .url, "y")], in: root, at: [0, 0])
        XCTAssertEqual(SettingsView.items(in: changed, at: [0, 0]).map(\.title), ["D"])
        XCTAssertEqual(changed[0].title, "A")
        XCTAssertEqual(SettingsView.items(in: root, at: [5]), []) // bad path is safe
    }
}
