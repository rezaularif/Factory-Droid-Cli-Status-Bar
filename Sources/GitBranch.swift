import Foundation

/// Resolve branch from `.git/HEAD` without spawning `git`.
enum GitBranch {
    /// cwd → resolved HEAD path; `""` means confirmed non-git.
    private static var headCache: [String: String] = [:]

    static func invalidateNonGit(_ cwd: String) {
        if headCache[cwd] == "" { headCache[cwd] = nil }
    }

    static func branch(for cwd: String) -> String {
        guard !cwd.isEmpty, let headPath = headPath(for: cwd) else { return "" }
        guard let d = FileManager.default.contents(atPath: headPath), d.count <= 1024,
              let s = String(data: d, encoding: .utf8) else {
            headCache[cwd] = nil
            return ""
        }
        let head = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if head.hasPrefix("ref: refs/heads/") { return String(head.dropFirst(16)) }
        if head.hasPrefix("ref: ") { return (head as NSString).lastPathComponent }
        if (40...64).contains(head.count), head.allSatisfy({ $0.isHexDigit && !$0.isUppercase }) {
            return String(head.prefix(7))
        }
        return ""
    }

    private static func headPath(for cwd: String) -> String? {
        if let hit = headCache[cwd] { return hit.isEmpty ? nil : hit }
        let fm = FileManager.default
        var dir = cwd
        var isDir: ObjCBool = false
        for _ in 0..<40 {
            let g = (dir as NSString).appendingPathComponent(".git")
            if fm.fileExists(atPath: g, isDirectory: &isDir) {
                var head: String?
                if isDir.boolValue {
                    head = (g as NSString).appendingPathComponent("HEAD")
                } else if let d = fm.contents(atPath: g), d.count <= 4096,
                          let s = String(data: d, encoding: .utf8),
                          let line = s.split(separator: "\n").first, line.hasPrefix("gitdir: ") {
                    var gd = String(line.dropFirst(8)).trimmingCharacters(in: .whitespaces)
                    if !gd.hasPrefix("/") {
                        gd = ((dir as NSString).appendingPathComponent(gd) as NSString).standardizingPath
                    }
                    head = (gd as NSString).appendingPathComponent("HEAD")
                }
                headCache[cwd] = head ?? ""
                return head
            }
            let parent = (dir as NSString).deletingLastPathComponent
            if parent == dir || parent.isEmpty { break }
            dir = parent
        }
        headCache[cwd] = ""
        return nil
    }
}
