import XCTest
@testable import NirvanaWheel

final class ConfigTests: XCTestCase {
    func testDefaultRoundTrips() throws {
        let data = try JSONEncoder().encode(RingConfig.default)
        XCTAssertEqual(try JSONDecoder().decode(RingConfig.self, from: data).items.map(\.title),
                       RingConfig.default.items.map(\.title))
    }

    func testSubMenuDecodes() throws {
        let json = """
        {"hotkey":{"key":"space","modifiers":["option"]},
         "items":[{"title":"Tools","symbol":"wrench","items":[
            {"title":"Safari","action":{"type":"app","value":"/Applications/Safari.app"}}]}]}
        """
        let cfg = try JSONDecoder().decode(RingConfig.self, from: Data(json.utf8))
        XCTAssertTrue(cfg.items[0].isMenu)
        XCTAssertNil(cfg.items[0].action)
        XCTAssertEqual(cfg.items[0].items?.first?.symbol, "circle") // default icon
    }

    func testItemWithoutActionOrItemsIsRejected() {
        let json = """
        {"hotkey":{"key":"space","modifiers":[]},"items":[{"title":"Nothing"}]}
        """
        XCTAssertThrowsError(try JSONDecoder().decode(RingConfig.self, from: Data(json.utf8)))
    }

    func testDefaultHasSystemSubMenu() {
        XCTAssertTrue(RingConfig.default.items.contains { $0.title == "System" && $0.isMenu })
    }
}
