import Foundation

// A matching app bundle found on disk.
struct AppMatch {
    let name: String
    let url: URL
    let location: String? // containing folder, set only to disambiguate same-named apps
}

// Locates app bundles by name in the usual install locations.
enum AppFinder {
    private static let searchDirs = [
        "/Applications",
        "/Applications/Utilities",
        "/System/Applications",
        "/System/Applications/Utilities",
        NSHomeDirectory() + "/Applications",
    ]

    // All apps whose name contains the query, prefix-matches first then
    // alphabetical. Same-named apps get a `location` to tell them apart.
    static func search(_ query: String, limit: Int = 8) -> [AppMatch] {
        let q = query.lowercased().trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return [] }

        let fm = FileManager.default
        let urls = searchDirs.flatMap { dir -> [URL] in
            (try? fm.contentsOfDirectory(at: URL(fileURLWithPath: dir),
                                         includingPropertiesForKeys: nil)) ?? []
        }.filter { $0.pathExtension == "app" }

        let matched = urls.filter { displayName(of: $0).lowercased().contains(q) }
        let sorted = matched.sorted { a, b in
            let na = displayName(of: a).lowercased(), nb = displayName(of: b).lowercased()
            let pa = na.hasPrefix(q), pb = nb.hasPrefix(q)
            if pa != pb { return pa }
            if na != nb { return na < nb }
            return a.path < b.path
        }

        var nameCounts: [String: Int] = [:]
        for u in sorted { nameCounts[displayName(of: u).lowercased(), default: 0] += 1 }

        return sorted.prefix(limit).map { url in
            let name = displayName(of: url)
            let dup = (nameCounts[name.lowercased()] ?? 0) > 1
            return AppMatch(name: name, url: url,
                            location: dup ? url.deletingLastPathComponent().lastPathComponent : nil)
        }
    }

    static func find(named query: String) -> URL? {
        search(query, limit: 1).first?.url
    }

    static func info(at url: URL) -> CustomApp {
        CustomApp(name: displayName(of: url), bundleID: Bundle(url: url)?.bundleIdentifier ?? "")
    }

    private static func displayName(of url: URL) -> String {
        let display = FileManager.default.displayName(atPath: url.path)
        return display.hasSuffix(".app") ? String(display.dropLast(4)) : display
    }
}
