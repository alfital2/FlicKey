import Carbon

// Tiny helper for the day-of-work driver: read or set the current keyboard layout.
//   day-of-work-helper current      → prints the current input-source ID
//   day-of-work-helper set <id>     → selects that input source
func sources() -> [TISInputSource] {
    (TISCreateInputSourceList(nil, false)?.takeRetainedValue() as? [TISInputSource]) ?? []
}
func id(_ s: TISInputSource) -> String? {
    TISGetInputSourceProperty(s, kTISPropertyInputSourceID).map {
        Unmanaged<CFString>.fromOpaque($0).takeUnretainedValue() as String
    }
}

let args = CommandLine.arguments
if args.count >= 2, args[1] == "current" {
    if let cur = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue(), let i = id(cur) {
        print(i)
    }
} else if args.count >= 3, args[1] == "set" {
    if let s = sources().first(where: { id($0) == args[2] }) { TISSelectInputSource(s) }
}
