import XCTest
@testable import NirvanaWheel

final class CalcTests: XCTestCase {
    func ev(_ s: String) throws -> Double { try Calc.evaluate(s) }

    func testBasics() throws {
        XCTAssertEqual(try ev("2+3*4"), 14)
        XCTAssertEqual(try ev("(2+3)*4"), 20)
        XCTAssertEqual(try ev("10/4"), 2.5)
        XCTAssertEqual(try ev("-3 + 5"), 2)
        XCTAssertEqual(try ev("2^3^2"), 512) // right-associative
        XCTAssertEqual(try ev("10 % 3"), 1)
        XCTAssertEqual(try ev("1,000 × 2"), 2000)
        XCTAssertEqual(try ev("9 ÷ 3"), 3)
    }

    func testBadInputNeverCrashes() {
        for s in ["", "2+", "(1", "1)", "abc", "..", "1/0", "5 % 0", "2**3"] {
            XCTAssertThrowsError(try ev(s), s)
        }
    }

    func testFormat() {
        XCTAssertEqual(Calc.format(14), "14")
        XCTAssertEqual(Calc.format(2.5), "2.5")
        XCTAssertEqual(Calc.format(1.0 / 3.0), "0.3333333333")
    }

    func testEveryMiniAppIsInTheDefaultRing() {
        let tools = RingConfig.default.items.first { $0.title == "Tools" }?.items ?? []
        XCTAssertEqual(tools.count, MiniAppID.allCases.count)
    }
}
