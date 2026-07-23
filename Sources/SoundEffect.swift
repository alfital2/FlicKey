import AVFoundation

// A selectable click sound played when a conversion lands. One preloaded player
// per variant (cached), re-triggered by resetting currentTime for low latency.
struct ClickSound: Equatable {
    let id: String      // stable key persisted in defaults
    let name: String    // shown in the picker
    let file: String    // resource basename (.wav)
}

enum SoundEffect {
    static let options: [ClickSound] = [
        ClickSound(id: "wood",   name: "Wood",   file: "click-wood"),
        ClickSound(id: "tic",    name: "Tic",    file: "click-tic"),
        ClickSound(id: "block",  name: "Block",  file: "click-block"),
        ClickSound(id: "knock",  name: "Knock",  file: "click-knock"),
        ClickSound(id: "double", name: "Double", file: "click-double"),
        ClickSound(id: "majistic", name: "Majistic", file: "click-majistic"),
        ClickSound(id: "pop",    name: "Pop",    file: "click-pop"),
        ClickSound(id: "pluck",  name: "Pluck",  file: "click-pluck"),
        ClickSound(id: "ping",   name: "Ping",   file: "click-ping"),
        ClickSound(id: "bubble", name: "Bubble", file: "click-bubble"),
        ClickSound(id: "keyboard", name: "Keyboard", file: "click-keyboard"),
    ]

    private static let enabledKey = "clickSound.enabled"
    private static let variantKey = "clickSound.variant"
    private static let volumeKey = "clickSound.volumeLevel"
    private static let defaultID = "knock"

    // Four discrete volume steps (0…3). Governs every FlicKey click — the
    // conversion click and the layout-switch cue alike.
    static let volumeLevels = 4

    static var isEnabled: Bool {
        get { AppDefaults.store.object(forKey: enabledKey) as? Bool ?? true }
        set { AppDefaults.store.set(newValue, forKey: enabledKey) }
    }

    static var volumeLevel: Int {
        get {
            guard AppDefaults.store.object(forKey: volumeKey) != nil else { return volumeLevels - 1 }
            return max(0, min(volumeLevels - 1, AppDefaults.store.integer(forKey: volumeKey)))
        }
        set {
            let clamped = max(0, min(volumeLevels - 1, newValue))
            AppDefaults.store.set(clamped, forKey: volumeKey)
            let v = volume(forLevel: clamped)
            players.values.forEach { $0.volume = v }   // apply live to cached players
        }
    }

    // Level → linear gain. Level 3 = full; lower levels quieter but audible.
    static func volume(forLevel level: Int) -> Float {
        let clamped = max(0, min(volumeLevels - 1, level))
        return Float(clamped + 1) / Float(volumeLevels)   // 0.25, 0.5, 0.75, 1.0
    }

    static var selected: ClickSound {
        let id = AppDefaults.store.string(forKey: variantKey) ?? defaultID
        return options.first { $0.id == id }
            ?? options.first { $0.id == defaultID }
            ?? options[0]
    }

    static func select(_ sound: ClickSound) {
        AppDefaults.store.set(sound.id, forKey: variantKey)
        warm()
    }

    // Pre-acquire the audio hardware so the NEXT click plays instantly. The first
    // play after idle otherwise pays for lazy player creation plus CoreAudio
    // spinning the output back up (easily 100-300ms — "the first click is slow,
    // the rest are fast"). Called at launch, on selection change, and from the
    // moments a click is imminent (first Shift/Option tap, auto-fix arming).
    // Cheap when already warm: a dictionary hit and a no-op prepare.
    static func warm() {
        player(for: selected)?.prepareToPlay()
    }

    private static var players: [String: AVAudioPlayer] = [:]

    private static func player(for sound: ClickSound) -> AVAudioPlayer? {
        if let cached = players[sound.id] { return cached }
        guard let url = Bundle.main.url(forResource: sound.file, withExtension: "wav"),
              let player = try? AVAudioPlayer(contentsOf: url) else { return nil }
        player.volume = volume(forLevel: volumeLevel)
        player.prepareToPlay()
        players[sound.id] = player
        return player
    }

    // Played on a real conversion (respects the on/off setting).
    static func playClick() {
        guard isEnabled else { return }
        play(selected)
    }

    // Played by the settings picker to audition a variant (ignores on/off).
    static func preview(_ sound: ClickSound) { play(sound) }

    // Played by the layout-switch cue, which has its own enable flag
    // (LayoutCueSettings.soundEnabled) — so this ignores `isEnabled`.
    static func playCueClick() { play(selected) }

    private static func play(_ sound: ClickSound) {
        guard let player = player(for: sound) else { return }
        player.currentTime = 0
        player.play()
    }
}
