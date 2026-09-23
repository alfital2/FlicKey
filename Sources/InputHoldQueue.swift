// Preserves physical event order while a text replacement owns the caret.
// Newly arriving input stays queued until the previously replayed batch has
// returned through the event tap, so it cannot overtake an older key.
struct InputHoldQueue<Event> {
    private(set) var isHolding = false
    private(set) var replaying = 0
    private var pending: [Event] = []

    mutating func begin() -> Bool {
        guard !isHolding else { return false }
        isHolding = true
        return true
    }

    mutating func capture(_ event: Event) -> Bool {
        guard isHolding else { return false }
        pending.append(event)
        return true
    }

    mutating func drain() -> [Event] {
        precondition(replaying == 0)
        let batch = pending
        pending.removeAll(keepingCapacity: true)
        replaying = batch.count
        if batch.isEmpty { isHolding = false }
        return batch
    }

    mutating func didReplay() -> [Event] {
        guard replaying > 0 else { return [] }
        replaying -= 1
        return replaying == 0 ? drain() : []
    }

    mutating func stop() -> [Event] {
        let remainder = pending
        self = InputHoldQueue()
        return remainder
    }
}
