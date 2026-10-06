import Foundation

/// A saved list of steps you start with one sentence ("start my work day").
/// Steps are stored in the same JSON shape the AI uses for plans, so the same
/// checks apply (`VoiceAIAction.intent`, `VoiceSafety.allowedInPlan`).
public struct Routine: Codable, Identifiable, Equatable, Sendable {
    public var id = UUID()
    public var name: String
    /// What you say to start it (the name always works too).
    public var phrases: [String]
    public var steps: [RoutineStep]
    public var enabled: Bool

    public init(name: String, phrases: [String] = [], steps: [RoutineStep], enabled: Bool = true) {
        self.name = name; self.phrases = phrases; self.steps = steps; self.enabled = enabled
    }

    /// The steps Nova will actually run (invalid or forbidden ones dropped).
    public var intents: [VoiceIntent] { steps.compactMap(\.intent).filter(VoiceSafety.allowedInPlan) }

    public static let templates: [Routine] = [
        Routine(name: "Start my work day", phrases: ["start my work day", "start work", "work mode", "office mode", "vela start pannu"],
                steps: [.init(["action": "agenda", "day": "today"]), .init(["action": "openApp", "name": "Visual Studio Code"]),
                        .init(["action": "openApp", "name": "Slack"]), .init(["action": "status"]),
                        .init(["action": "music", "command": "play"])], enabled: false),
        Routine(name: "Wrap up", phrases: ["wrap up", "end my day", "finish work", "good night nova"],
                steps: [.init(["action": "status"]), .init(["action": "agenda", "day": "tomorrow"]),
                        .init(["action": "systemCheck"]), .init(["action": "music", "command": "pause"])], enabled: false),
    ]
}

/// One step: a JSON object like {"action":"openApp","name":"Slack"}.
public struct RoutineStep: Codable, Equatable, Sendable {
    public var json: String

    public init(json: String) { self.json = json }

    public init(_ object: [String: Any]) {
        let data = (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])) ?? Data("{}".utf8)
        json = String(decoding: data, as: UTF8.self)
    }

    public init?(_ intent: VoiceIntent) {
        guard let object = VoiceAIAction.json(for: intent) else { return nil }
        self.init(object)
    }

    public var intent: VoiceIntent? {
        guard let data = json.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let action = object["action"] as? String else { return nil }
        return VoiceAIAction.intent(action, object)
    }
}

public enum RoutineMatcher {
    /// The enabled routine you asked for: "start my work day", "run wrap up",
    /// "start the gym routine".
    public static func match(_ transcript: String, in routines: [Routine]) -> Routine? {
        let text = VoiceIntentRouter.normalize(VoiceIntentRouter.stripWakeWord(transcript))
        guard !text.isEmpty else { return nil }
        let stripped = text.replacingOccurrences(of: #"^(run|start|do|begin|play)\s+(the\s+|my\s+)?"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\s+routine$"#, with: "", options: .regularExpression)
        for routine in routines where routine.enabled {
            let names = ([routine.name] + routine.phrases).map(VoiceIntentRouter.normalize).filter { !$0.isEmpty }
            if names.contains(text) || names.contains(stripped) { return routine }
        }
        return nil
    }
}

extension VoiceAIAction {
    /// The JSON for a step (the reverse of `intent(_:_:)`). Nil for things a
    /// routine can't contain.
    public static func json(for intent: VoiceIntent) -> [String: Any]? {
        switch intent {
        case .openApp(let name): ["action": "openApp", "name": name]
        case .quitApp(let name): ["action": "quitApp", "name": name]
        case .switchTo(let name): ["action": "switchTo", "name": name]
        case .openWebsite(let url): ["action": "openWebsite", "url": url]
        case .webSearch(let engine, let query): ["action": "webSearch", "engine": engine.rawValue, "query": query]
        case .playSong(let query): ["action": "playSong", "query": query]
        case .browser(let command): ["action": "browser", "command": command.rawValue]
        case .typeText(let text): ["action": "typeText", "text": text]
        case .click(let label): ["action": "click", "label": label]
        case .mute(let on): ["action": "mute", "on": on]
        case .volume(let up): ["action": "volume", "up": up]
        case .timer(let seconds): ["action": "timer", "seconds": seconds]
        case .screenshot: ["action": "screenshot"]
        case .lockScreen: ["action": "lockScreen"]
        case .music(let command): ["action": "music", "command": command.rawValue]
        case .systemCheck: ["action": "systemCheck"]
        case .status: ["action": "status"]
        case .agenda(let day): ["action": "agenda", "day": day.rawValue]
        case .runShortcut(let name): ["action": "runShortcut", "name": name]
        case .sendMessage(let contact, let text): ["action": "sendWhatsApp", "contact": contact, "text": text]
        default: nil
        }
    }
}
