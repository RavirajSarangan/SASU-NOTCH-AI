import Foundation
import NovaKit
import Observation

/// Your routines, in Application Support/Nova/routines.json. The built-in
/// ones start switched off.
@Observable
@MainActor
final class RoutineStore {
    var routines: [Routine] {
        didSet { if routines != oldValue { save() } }
    }

    private static var url: URL { NovaPathsApp.support.appendingPathComponent("routines.json") }

    init() {
        if let data = try? Data(contentsOf: Self.url), let saved = try? JSONDecoder().decode([Routine].self, from: data) {
            routines = saved
        } else {
            routines = Routine.templates
        }
    }

    func add(_ routine: Routine) {
        routines.removeAll { $0.name.caseInsensitiveCompare(routine.name) == .orderedSame }
        routines.append(routine)
    }

    private func save() {
        try? FileManager.default.createDirectory(at: NovaPathsApp.support, withIntermediateDirectories: true)
        try? JSONEncoder().encode(routines).write(to: Self.url, options: .atomic)
    }
}

/// Your Apple Shortcuts, run with the `shortcuts` command (off the main thread).
@MainActor
final class ShortcutsService {
    private var cache: [String] = []
    private var cachedAt = Date.distantPast
    private static let approvedKey = "voice.approvedShortcuts"

    func names() async -> [String] {
        if Date().timeIntervalSince(cachedAt) < 600, !cache.isEmpty { return cache }
        let output = await CommandRunner.run("/usr/bin/shortcuts", ["list"], timeout: 15)
        cache = output.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        cachedAt = Date()
        return cache
    }

    /// Shortcuts you already allowed Nova to run.
    func isApproved(_ name: String) -> Bool {
        (UserDefaults.standard.stringArray(forKey: Self.approvedKey) ?? []).contains(name)
    }

    func approve(_ name: String) {
        var list = UserDefaults.standard.stringArray(forKey: Self.approvedKey) ?? []
        if !list.contains(name) { list.append(name) }
        UserDefaults.standard.set(list, forKey: Self.approvedKey)
    }

    func run(_ name: String) async -> Bool {
        await CommandRunner.runWithStatus("/usr/bin/shortcuts", ["run", name], timeout: 60).status == 0
    }
}
