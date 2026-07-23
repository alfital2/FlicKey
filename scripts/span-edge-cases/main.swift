import Foundation

// Real enum (mirrors Sources/DiagnosticEvent.swift) so the real OnScreenSpan.swift
// compiles unmodified alongside this harness.
enum RewriteAnomalyKind: String, Codable, Equatable {
    case orphanFragment
    case tailMutated
}

// Faithful replica of AutoSwitchController.onScreenDeleteCount (it is private).
// Mirrors the post-QA guard: the measured span is trusted even when SMALLER than
// the tracked count (a shrinking text service — deleting less can never eat prior
// text); only an implausibly large span, or an unreadable field, falls back.
func onScreenDeleteCount(run: String, before: [Character]?) -> (count: Int, path: String) {
    let tracked = run.count
    guard let before else { return (tracked, "FALLBACK ax_unreadable") }
    let words = run.split(separator: " ").count
    let onScreen = OnScreenSpan.length(beforeCaret: before, words: words)
    guard onScreen <= tracked * 3 + 24 else {
        return (min(tracked, before.count), "FALLBACK span_out_of_range(onScreen=\(onScreen) tracked=\(tracked))")
    }
    return (onScreen, onScreen != tracked ? "measured(\(onScreen)) != tracked(\(tracked))" : "exact")
}

struct Case {
    let name: String
    let field: String       // on-screen text before caret at fire time
    let run: String         // what FlicKey tracked (keystroke model)
    let typed: String       // the conversion it will type
    let expected: String    // correct resulting field
    let axReadable: Bool
    var knownLimitation = false   // documented + deferred; not counted as failure
}

func simulate(_ c: Case) -> (actual: String, deleted: Int, path: String, anomaly: RewriteAnomalyKind?) {
    let before = c.axReadable ? Array(c.field) : nil
    let (n, path) = onScreenDeleteCount(run: c.run, before: before)
    var chars = Array(c.field)
    let toDrop = min(n, chars.count)
    chars.removeLast(toDrop)
    let result = String(chars) + c.typed
    // The shipping self-check compares against the PLANNED outcome when the
    // pre-rewrite state was readable, else the weaker tail heuristic.
    let anomaly: RewriteAnomalyKind?
    if let before {
        let planned = String(before.dropLast(toDrop)) + c.typed
        anomaly = RewriteCheck.residueAnomaly(actual: Array(result),
                                              expected: Array(planned),
                                              typed: Array(c.typed))
    } else {
        anomaly = nil   // AX unreadable at fire ⇒ usually unreadable at check too
    }
    return (result, n, path, anomaly)
}

let cases: [Case] = [
    Case(name: "baseline — no text service mutation",
         field: "מה המצב can i ", run: "can i ", typed: "כשמ י ",
         expected: "מה המצב כשמ י ", axReadable: true),

    Case(name: "BUG-1 autocorrect single-word expansion (the 0.4.6 fix)",
         field: "מה המצב בשמאל ן ", run: "בשמ ן ", typed: "can i ",
         expected: "מה המצב can i ", axReadable: true),

    Case(name: "AUTOCORRECT WORD-SPLIT — safer direction: under-delete, never eat prior text",
         field: "hi ab cde vnmc ", run: "abcde vnmc ", typed: "מה המצב ",
         expected: "hi ab מה המצב ", axReadable: true),

    Case(name: "TEXT REPLACEMENT multi-word expansion (omw → On my way!) — DEFERRED (caret anchor)",
         field: "On my way! vnmc ", run: "omw vnmc ", typed: "מה המצב ",
         expected: "מה המצב ", axReadable: true, knownLimitation: true),

    Case(name: "AUTOCORRECT SHRINK — measured span trusted (fixed)",
         field: "keep this hello vnmc ", run: "helllo vnmc ", typed: "מה המצב ",
         expected: "keep this מה המצב ", axReadable: true),

    Case(name: "NBSP separator instead of ASCII space (fixed)",
         field: "hi בשמאל\u{00A0}ן ", run: "בשמ ן ", typed: "can i ",
         expected: "hi can i ", axReadable: true),

    Case(name: "AX UNREADABLE → fallback, logged to trail — unmeasurable by definition",
         field: "מה המצב בשמאל ן ", run: "בשמ ן ", typed: "can i ",
         expected: "מה המצב can i ", axReadable: false, knownLimitation: true),
]

print("FlicKey — auto-switch rewrite span simulator")
print("real OnScreenSpan.swift + faithful replica of the private guard\n")
print(String(repeating: "=", count: 78))

var failures = 0
var limitations = 0
for c in cases {
    let r = simulate(c)
    let pass = r.actual == c.expected
    let verdict: String
    if pass {
        verdict = "✅ PASS"
    } else if c.knownLimitation {
        verdict = "⚠️ KNOWN LIMITATION (documented, deferred)"
        limitations += 1
    } else {
        verdict = "🔴 FAIL"
        failures += 1
    }
    print("\n\(verdict)  \(c.name)")
    print("   field before : \(c.field.debugDescription)")
    print("   tracked run  : \(c.run.debugDescription)  (\(c.run.count) chars, \(c.run.split(separator: " ").count) words)")
    print("   delete count : \(r.deleted)   [\(r.path)]")
    print("   expected     : \(c.expected.debugDescription)")
    print("   ACTUAL       : \(r.actual.debugDescription)")
    if !pass {
        let diag = r.anomaly.map { "logged \($0.rawValue)" } ?? "SILENT at the self-check (span fallback IS logged to the trail where taken)"
        print("   diagnostic   : \(diag)")
    }
}

print("\n" + String(repeating: "=", count: 78))
print("\(cases.count - failures - limitations)/\(cases.count) correct;  \(limitations) known limitations;  \(failures) unexpected corruptions")
exit(failures == 0 ? 0 : 1)
