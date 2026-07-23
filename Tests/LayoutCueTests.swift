import XCTest

// Unit tests for LayoutCueCore — the pure decision behind the layout-switch
// cue. The cue keys off the active input SOURCE ID (so it generalizes to any
// number of layouts, not just English/Hebrew). Change notifications are
// recorded with noteChange(); after a quiet gap settle() announces the FINAL
// layout's configured tap count (1–3), or stays silent (Off, unchanged,
// unsupported, or conversion-suppressed).
final class LayoutCueCoreTests: XCTestCase {

    // A stand-in taps table for tests: sourceID → tap count (nil = Off/no cue).
    private let taps: (String) -> Int? = { id in
        ["en": 1, "he": 2, "ar": 3][id]   // "ru" and unknowns → nil (Off)
    }

    // MARK: - Per-layout tap counts

    func testChangeToOneTapLayoutCuesOnce() {
        var core = LayoutCueCore(initialSourceID: "he")
        core.noteChange(to: "en")
        XCTAssertEqual(core.settle(tapCount: taps, now: 10.25), 1)
    }

    func testChangeToTwoTapLayoutCuesTwice() {
        var core = LayoutCueCore(initialSourceID: "en")
        core.noteChange(to: "he")
        XCTAssertEqual(core.settle(tapCount: taps, now: 10.25), 2)
    }

    func testThirdLayoutCuesThreeTaps() {
        var core = LayoutCueCore(initialSourceID: "en")
        core.noteChange(to: "ar")
        XCTAssertEqual(core.settle(tapCount: taps, now: 10.25), 3)
    }

    func testLayoutSetToOffIsSilent() {
        var core = LayoutCueCore(initialSourceID: "en")
        core.noteChange(to: "ru")   // ru → nil (Off)
        XCTAssertNil(core.settle(tapCount: taps, now: 10.25))
    }

    // MARK: - Coalescing rapid flip-flops

    func testFlipFlopBackToStartIsSilent() {
        var core = LayoutCueCore(initialSourceID: "he")
        core.noteChange(to: "en")
        core.noteChange(to: "he")
        XCTAssertNil(core.settle(tapCount: taps, now: 10.35))
    }

    func testRapidBurstCuesOnlyTheFinalLayout() {
        var core = LayoutCueCore(initialSourceID: "he")
        core.noteChange(to: "en")
        core.noteChange(to: "he")
        core.noteChange(to: "en")
        XCTAssertEqual(core.settle(tapCount: taps, now: 10.35), 1)
        XCTAssertNil(core.settle(tapCount: taps, now: 10.4))
    }

    func testEchoOfAnnouncedLayoutIsSilent() {
        var core = LayoutCueCore(initialSourceID: "he")
        core.noteChange(to: "en")
        XCTAssertEqual(core.settle(tapCount: taps, now: 10.25), 1)
        core.noteChange(to: "en")
        XCTAssertNil(core.settle(tapCount: taps, now: 10.58))
    }

    func testSettleWithoutChangeIsSilent() {
        var core = LayoutCueCore(initialSourceID: "he")
        XCTAssertNil(core.settle(tapCount: taps, now: 10))
    }

    // MARK: - Unknown / no source

    func testNilSourceIsSilent() {
        var core = LayoutCueCore(initialSourceID: "he")
        core.noteChange(to: nil)
        XCTAssertNil(core.settle(tapCount: taps, now: 10.25))
    }

    func testReturningFromOffLayoutCuesAgain() {
        // he → ru(Off) → he must cue: the user really left and re-entered he.
        var core = LayoutCueCore(initialSourceID: "he")
        core.noteChange(to: "ru")
        XCTAssertNil(core.settle(tapCount: taps, now: 10.25))
        core.noteChange(to: "he")
        XCTAssertEqual(core.settle(tapCount: taps, now: 11.25), 2)
    }

    // MARK: - Suppression (conversion path)

    func testSuppressedChangeIsSilent() {
        var core = LayoutCueCore(initialSourceID: "he")
        core.suppress(for: 1.0, now: 10)
        core.noteChange(to: "en")
        XCTAssertNil(core.settle(tapCount: taps, now: 10.3))
    }

    func testSuppressedChangeIsStillAdopted() {
        var core = LayoutCueCore(initialSourceID: "he")
        core.suppress(for: 1.0, now: 10)
        core.noteChange(to: "en")
        XCTAssertNil(core.settle(tapCount: taps, now: 10.3))
        core.noteChange(to: "en")
        XCTAssertNil(core.settle(tapCount: taps, now: 12.25))
    }

    func testChangeAfterSuppressionWindowCues() {
        var core = LayoutCueCore(initialSourceID: "he")
        core.suppress(for: 1.0, now: 10)
        core.noteChange(to: "en")
        XCTAssertEqual(core.settle(tapCount: taps, now: 11.75), 1)
    }
}

final class LayoutCueSettingsTests: XCTestCase {

    private let keys = ["layoutCue.haptic.enabled",
                        "layoutCue.sound.enabled",
                        "layoutCue.tapsBySource"]

    override func setUp() { keys.forEach { UserDefaults.standard.removeObject(forKey: $0) } }
    override func tearDown() { keys.forEach { UserDefaults.standard.removeObject(forKey: $0) } }

    func testToggleDefaults() {
        XCTAssertTrue(LayoutCueSettings.hapticEnabled)     // haptic on by default
        XCTAssertFalse(LayoutCueSettings.soundEnabled)     // sound opt-in
    }

    func testTogglePersistence() {
        LayoutCueSettings.hapticEnabled = false
        LayoutCueSettings.soundEnabled = true
        XCTAssertFalse(LayoutCueSettings.hapticEnabled)
        XCTAssertTrue(LayoutCueSettings.soundEnabled)
    }

    // With nothing stored, English defaults to 1 tap, Hebrew to 2, others Off.
    func testTapCountDefaultsByLanguage() {
        XCTAssertEqual(LayoutCueSettings.tapCount(forSourceID: "com.apple.keylayout.ABC",
                                                  defaultLanguageCode: "en"), 1)
        XCTAssertEqual(LayoutCueSettings.tapCount(forSourceID: "com.apple.keylayout.Hebrew-PC",
                                                  defaultLanguageCode: "he"), 2)
        XCTAssertEqual(LayoutCueSettings.tapCount(forSourceID: "com.apple.keylayout.Arabic",
                                                  defaultLanguageCode: "ar"), 0)
    }

    func testTapCountRoundTripAndCap() {
        LayoutCueSettings.setTapCount(3, forSourceID: "com.apple.keylayout.Arabic")
        XCTAssertEqual(LayoutCueSettings.tapCount(forSourceID: "com.apple.keylayout.Arabic",
                                                  defaultLanguageCode: "ar"), 3)
        // Stored value overrides the language default.
        LayoutCueSettings.setTapCount(0, forSourceID: "com.apple.keylayout.ABC")
        XCTAssertEqual(LayoutCueSettings.tapCount(forSourceID: "com.apple.keylayout.ABC",
                                                  defaultLanguageCode: "en"), 0)
        // Out-of-range clamps to 0...3.
        LayoutCueSettings.setTapCount(9, forSourceID: "com.apple.keylayout.ABC")
        XCTAssertEqual(LayoutCueSettings.tapCount(forSourceID: "com.apple.keylayout.ABC",
                                                  defaultLanguageCode: "en"), 3)
    }
}

final class HapticIntensityTests: XCTestCase {

    private let key = "layoutCue.haptic.level"
    override func setUp() { UserDefaults.standard.removeObject(forKey: key) }
    override func tearDown() { UserDefaults.standard.removeObject(forKey: key) }

    func testDefaultIsStrongest() {
        // Default preserves today's feel (the strongest tap).
        XCTAssertEqual(LayoutCueSettings.hapticIntensityLevel, LayoutCueSettings.hapticLevels - 1)
    }

    func testLevelPersistsAndClamps() {
        LayoutCueSettings.hapticIntensityLevel = 0
        XCTAssertEqual(LayoutCueSettings.hapticIntensityLevel, 0)
        LayoutCueSettings.hapticIntensityLevel = 99
        XCTAssertEqual(LayoutCueSettings.hapticIntensityLevel, LayoutCueSettings.hapticLevels - 1)
        LayoutCueSettings.hapticIntensityLevel = -3
        XCTAssertEqual(LayoutCueSettings.hapticIntensityLevel, 0)
    }

    func testActuationIDsAreDistinctAndStrongestIsSix() {
        let ids = (0..<LayoutCueSettings.hapticLevels).map { LayoutCueSettings.actuationID(forLevel: $0) }
        XCTAssertEqual(Set(ids).count, ids.count, "each level maps to a distinct actuation ID")
        XCTAssertEqual(ids.last, 6, "the strongest level is the ID FlicKey has always used")
    }
}

final class SoundEffectVolumeTests: XCTestCase {

    private let key = "clickSound.volumeLevel"
    override func setUp() { UserDefaults.standard.removeObject(forKey: key) }
    override func tearDown() { UserDefaults.standard.removeObject(forKey: key) }

    func testDefaultVolumeLevel() {
        XCTAssertEqual(SoundEffect.volumeLevel, 3)   // 4 levels (0...3); loud by default
    }

    func testVolumeLevelPersistsAndClamps() {
        SoundEffect.volumeLevel = 1
        XCTAssertEqual(SoundEffect.volumeLevel, 1)
        SoundEffect.volumeLevel = 99
        XCTAssertEqual(SoundEffect.volumeLevel, 3)   // clamps to max
        SoundEffect.volumeLevel = -5
        XCTAssertEqual(SoundEffect.volumeLevel, 0)   // clamps to min
    }

    func testVolumeForLevelIsMonotonic() {
        XCTAssertLessThan(SoundEffect.volume(forLevel: 0), SoundEffect.volume(forLevel: 3))
        XCTAssertEqual(SoundEffect.volume(forLevel: 3), 1.0, accuracy: 0.001)
    }
}
