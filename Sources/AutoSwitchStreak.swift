// Pure streak state machine for auto-switch. The streak is ARMED (returns true)
// once at least `threshold` CONFIDENT wrong-layout matches have completed in a row,
// all agreeing on the same target layout, and at least one of them is a multi-letter
// word. It stays armed as further words arrive, so a continuously typed wrong phrase
// converts as a whole once typing pauses, not just its first pair. The count resets
// only when the streak breaks (an ordinary word, a run break, or the fire itself via
// breakRun()).
//
// Single letters may open or extend a streak but never arm one by themselves:
// dictionaries can't vouch for lone letters, and several languages (Russian
// especially) have many valid one-letter words, so an all-singles streak could
// rewrite intentional text. One confident multi-letter word is required.
//
// An `ambiguousLayout` word is valid AS TYPED (the classifier judged it notSlip)
// yet ALSO reads as a real word once converted toward the target — the many
// high-frequency function words that transliterate to a short valid English token
// (Hebrew את→"t,", כן→"fi"; Arabic في→"td"; Russian же→";t"). Such a word belongs to
// the wrong-layout passage, so it rides along in the run (converting with it) and can
// keep a live streak going — but it supplies NO confidence: it never counts toward
// the arm threshold and never provides the multi-letter evidence. Only `threshold`
// genuine CONFIDENT matches can arm a fire. This is deliberate: because a short word
// that is valid in both scripts is common, letting ambiguous words push a streak to
// the threshold would let a single English typo beside one ordinary word convert real
// English into gibberish. Requiring two confident matches keeps that from happening
// while still dragging the passage's function words along once a real slip run exists.
struct AutoSwitchStreak {

    enum Word: Equatable {
        case wrongLayout(targetSourceID: String?, isSingleLetter: Bool)
        case ambiguousLayout(targetSourceID: String?)
        case ordinary
    }

    let threshold: Int
    // Total members of the current run (confident + ambiguous); used to tell whether a
    // streak is live and, on a target-disagreement restart, to trim the reconstructed run.
    private(set) var count = 0
    // Only CONFIDENT wrong-layout matches — these alone can arm a fire.
    private var confidentCount = 0
    // The layout the current streak's words agree on; valid while count > 0.
    private(set) var targetSourceID: String?
    private var hasMultiLetterWord = false

    init(threshold: Int = 2) { self.threshold = threshold }

    // Returns whether the streak is armed after this word.
    mutating func word(_ kind: Word) -> Bool {
        switch kind {
        case let .wrongLayout(target, isSingleLetter):
            restartIfTargetDiffers(target)
            if count == 0 { targetSourceID = target }
            count += 1
            confidentCount += 1
            if !isSingleLetter { hasMultiLetterWord = true }
            return armed
        case let .ambiguousLayout(target):
            // Rides in the run and agrees on target, but supplies no confidence: it
            // touches neither confidentCount nor hasMultiLetterWord, so it can neither
            // arm a streak nor push one to the arm threshold.
            restartIfTargetDiffers(target)
            if count == 0 { targetSourceID = target }
            count += 1
            return armed
        case .ordinary:
            breakRun()
            return false
        }
    }

    // Armed only on enough CONFIDENT matches, at least one of them multi-letter.
    var isArmed: Bool { confidentCount >= threshold && hasMultiLetterWord }
    private var armed: Bool { isArmed }

    private mutating func restartIfTargetDiffers(_ target: String?) {
        if count > 0 && target != targetSourceID {
            count = 0                          // disagreeing target: restart at this word
            confidentCount = 0
            hasMultiLetterWord = false
        }
    }

    mutating func breakRun() {
        count = 0
        confidentCount = 0
        hasMultiLetterWord = false
    }
}
