import AppKit
import Foundation
import NovaKit
import Observation

/// Something Nova Guard did on its own (or at the user's click), with undo.
struct GuardAction: Codable, Identifiable, Equatable {
    enum Undo: Codable, Equatable {
        /// Move `quarantined` back to `original` and load it again.
        case restoreLaunchAgent(original: String, quarantined: String)
        case none
    }

    var id = UUID()
    var date = Date()
    var title: String
    var detail: String
    var undo: Undo = .none
    var undone = false
}

/// Nova Guard's hands: safe, reversible fixes without admin rights, and
/// admin fixes that run only after the user clicks (macOS asks for the
/// password). Every action is logged and, where possible, undoable.
@Observable
@MainActor
final class GuardActions {
    private(set) var log: [GuardAction] = []
    private(set) var runningFix: AdminFix?

    private static var logURL: URL { NovaPathsApp.support.appendingPathComponent("guard-actions.json") }
    static var quarantineDirectory: URL { NovaPathsApp.support.appendingPathComponent("Quarantine", isDirectory: true) }

    init() {
        log = (try? Data(contentsOf: Self.logURL)).flatMap { try? JSONDecoder().decode([GuardAction].self, from: $0) } ?? []
    }

    // MARK: Startup items

    /// Unloads a user LaunchAgent and moves its plist to Nova's quarantine
    /// folder. Only for ~/Library/LaunchAgents (no admin needed).
    @discardableResult
    func quarantineLaunchAgent(at path: String, reason: String) async -> GuardAction? {
        let userAgents = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/LaunchAgents").path
        guard path.hasPrefix(userAgents + "/"), FileManager.default.fileExists(atPath: path) else { return nil }
        let domain = "gui/\(getuid())"
        _ = await CommandRunner.run("/bin/launchctl", ["bootout", domain, path], timeout: 10)
        do {
            try FileManager.default.createDirectory(at: Self.quarantineDirectory, withIntermediateDirectories: true,
                                                    attributes: [.posixPermissions: 0o700])
            let destination = QuarantinePath.destination(for: path, in: Self.quarantineDirectory.path, date: Date())
            try FileManager.default.moveItem(atPath: path, toPath: destination)
            let name = (path as NSString).lastPathComponent
            return record(GuardAction(title: "Blocked startup item \(name)", detail: reason,
                                      undo: .restoreLaunchAgent(original: path, quarantined: destination)))
        } catch {
            Log.app.error("Couldn't quarantine a startup item: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    // MARK: Processes

    func terminate(pid: Int32, command: String) -> GuardAction? {
        guard pid > 1, pid != getpid(), kill(pid, SIGTERM) == 0 else { return nil }
        return record(GuardAction(title: "Stopped a reverse shell (pid \(pid))", detail: String(command.prefix(160))))
    }

    // MARK: Admin fixes (user click + macOS password prompt)

    /// Returns true if the fix ran. The user can cancel the password prompt.
    func runAdminFix(_ fix: AdminFix) async -> Bool {
        guard runningFix == nil else { return false }
        runningFix = fix
        defer { runningFix = nil }
        let result = await CommandRunner.runWithStatus("/usr/bin/osascript", ["-e", fix.appleScript], timeout: 120)
        guard result.status == 0 else { return false }
        record(GuardAction(title: fix.title, detail: "Ran: \(fix.command)"))
        return true
    }

    // MARK: Undo

    func undo(_ action: GuardAction) async {
        guard let i = log.firstIndex(where: { $0.id == action.id }), !log[i].undone else { return }
        switch action.undo {
        case .restoreLaunchAgent(let original, let quarantined):
            do {
                try FileManager.default.moveItem(atPath: quarantined, toPath: original)
                _ = await CommandRunner.run("/bin/launchctl", ["bootstrap", "gui/\(getuid())", original], timeout: 10)
            } catch {
                Log.app.error("Couldn't restore a startup item: \(error.localizedDescription, privacy: .public)")
                return
            }
        case .none:
            return
        }
        log[i].undone = true
        save()
    }

    @discardableResult
    private func record(_ action: GuardAction) -> GuardAction {
        log.insert(action, at: 0)
        log = Array(log.prefix(100))
        save()
        Log.app.notice("Guard action: \(action.title, privacy: .public)")
        return action
    }

    private func save() {
        try? FileManager.default.createDirectory(at: NovaPathsApp.support, withIntermediateDirectories: true)
        try? JSONEncoder().encode(log).write(to: Self.logURL, options: .atomic)
    }
}
