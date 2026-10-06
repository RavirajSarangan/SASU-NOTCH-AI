// nova-hook: run by coding-agent hooks (Claude Code, Codex, Cursor, Gemini
// CLI / Antigravity). Reads the hook JSON from stdin and forwards it to Nova
// over its local socket.
//
//   nova-hook                    Claude Code
//   nova-hook --agent codex|cursor|gemini
//
// Safety contract:
// - If Nova isn't running, or anything fails, print nothing and exit 0, so
//   the tool behaves exactly as if the hook weren't installed.
// - Claude Code's PermissionRequest waits for the user's decision in Nova.
//   For Codex, Cursor and Gemini, only high-risk commands wait, and Nova
//   can only *deny* them; allowing defers to the tool's own approvals.
// - Timeouts and "ask" print nothing. This hook never approves on its own.

import Darwin
import Foundation
import NovaKit

func argument(_ name: String) -> String? {
    let args = CommandLine.arguments
    guard let i = args.firstIndex(of: name), args.indices.contains(i + 1) else { return nil }
    return args[i + 1]
}

/// This process's ancestors (parent first): used to tell Antigravity apart
/// from Gemini CLI (they share ~/.gemini/settings.json) and to find the app
/// the agent runs in (Terminal, iTerm, VS Code…) for "jump to terminal".
func ancestors(limit: Int = 12) -> [(pid: pid_t, path: String)] {
    var result: [(pid: pid_t, path: String)] = []
    var pid = getppid()
    for _ in 0..<limit where pid > 1 {
        var buffer = [UInt8](repeating: 0, count: Int(MAXPATHLEN) * 4)
        let length = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        if length > 0 { result.append((pid, String(decoding: buffer.prefix(Int(length)), as: UTF8.self))) }
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        guard sysctl(&mib, 4, &info, &size, nil, 0) == 0 else { break }
        pid = info.kp_eproc.e_ppid
    }
    return result
}

/// The outermost .app bundle among the ancestors, e.g.
/// "/Applications/iTerm.app" (also for helpers nested inside an app).
func hostApp(_ chain: [(pid: pid_t, path: String)]) -> (path: String, pid: pid_t)? {
    for item in chain {
        if let bundle = HostApp.outermostBundle(path: item.path) { return (bundle, item.pid) }
    }
    return nil
}

let ancestorChain = ancestors()
let host = hostApp(ancestorChain)

let source = HookSource(rawValue: argument("--agent") ?? "claude") ?? .claude
var agent: AgentKind?
if source == .gemini {
    let launchedByAntigravity = ProcessInfo.processInfo.environment.keys.contains { $0.uppercased().contains("ANTIGRAVITY") }
        || ancestorChain.contains { $0.path.lowercased().contains("antigravity") }
    agent = launchedByAntigravity ? .antigravity : .gemini
}

let input = FileHandle.standardInput.readDataToEndOfFile()
// `--ask`: installed only for AskUserQuestion; waits for answers from the notch.
let askMode = CommandLine.arguments.contains("--ask")
guard var plan = AgentHookRouter.plan(source: source, hookJSON: input, agent: agent, askMode: askMode) else { exit(0) }
if let host {
    for i in plan.events.indices {
        plan.events[i].terminalApp = host.path
        plan.events[i].terminalPid = host.pid
    }
    plan.request?.terminalApp = host.path
    plan.request?.terminalPid = host.pid
}

// Activity: one connection per event.
for event in plan.events {
    guard let line = try? AgentEventDecoder.encodeLine(event) else { continue }
    _ = UnixSocket.request(path: NovaPaths.socketPath, line: line, awaitReply: false, timeout: 1)
}

// Decision: wait for the user.
if let request = plan.request, let line = try? AgentEventDecoder.encodeLine(request) {
    let timeout: TimeInterval = request.questions != nil ? 305 : plan.canApprove ? 125 : AgentHookRouter.guardTimeout
    if let reply = UnixSocket.request(path: NovaPaths.socketPath, line: line, awaitReply: true, timeout: timeout),
       let decision = try? JSONDecoder().decode(PermissionReply.self, from: reply),
       decision.requestId == request.requestId,
       let output = AgentHookRouter.output(source: source, hookEvent: plan.hookEvent, reply: decision, hookJSON: input) {
        FileHandle.standardOutput.write(output)
    }
}
exit(0)
