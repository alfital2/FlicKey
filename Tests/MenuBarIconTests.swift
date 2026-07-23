import XCTest

final class MenuBarIconTests: XCTestCase {

    func testHueIsDeterministic() {
        let a = MenuBarIcon.hue(forSourceID: "com.apple.keylayout.ABC")
        let b = MenuBarIcon.hue(forSourceID: "com.apple.keylayout.ABC")
        XCTAssertEqual(a, b, "same layout must always map to the same color")
    }

    func testDistinctLayoutsGetDistinctHues() {
        let ids = ["com.apple.keylayout.ABC", "com.apple.keylayout.Hebrew-PC",
                   "com.apple.keylayout.Russian", "com.apple.keylayout.Greek",
                   "com.apple.keylayout.Arabic"]
        let hues = Set(ids.map { MenuBarIcon.hue(forSourceID: $0) })
        XCTAssertEqual(hues.count, ids.count, "the common layouts should each get a unique hue")
    }

    func testHueInRange() {
        for id in ["x", "com.apple.keylayout.ABC", "🙂", ""] {
            let h = MenuBarIcon.hue(forSourceID: id)
            XCTAssert(h >= 0 && h < 360, "hue \(h) out of range for \(id)")
        }
    }
}
