import AppKit
import NovaKit
import Observation
import SwiftUI

enum ScreenChoice: String, CaseIterable, Identifiable, Codable {
    case automatic, builtIn, main

    var id: String { rawValue }
    var label: String {
        switch self {
        case .automatic: "Automatic (the notched screen)"
        case .builtIn: "Built-in display"
        case .main: "Screen with the menu bar"
        }
    }
}

enum PanelSize: String, CaseIterable, Identifiable, Codable {
    case regular, large

    var id: String { rawValue }
    var scale: CGFloat { self == .large ? 1.12 : 1 }
    var label: String { self == .large ? "Large" : "Regular" }
}

/// Non-secret app preferences, persisted in UserDefaults (prefix "pref.").
@Observable
@MainActor
final class NovaPreferences {
    private let defaults: UserDefaults

    // General
    var startHidden: Bool { didSet { save("startHidden", startHidden) } }
    var screen: ScreenChoice { didSet { save("screen", screen.rawValue) } }
    var onboardingDone: Bool { didSet { save("onboardingDone", onboardingDone) } }

    // Appearance
    var panelSize: PanelSize { didSet { save("panelSize", panelSize.rawValue) } }
    var animations: Bool { didSet { save("animations", animations) } }
    var reduceMotion: Bool { didSet { save("reduceMotion", reduceMotion) } }
    var glow: Double { didSet { save("glow", glow) } }

    // Nova
    var characterScale: Double { didSet { save("characterScale", characterScale) } }
    var eyeTracking: Bool { didSet { save("eyeTracking", eyeTracking) } }
    /// Full-body pose art per emotion (vs. the single hero art).
    var characterPoses: Bool { didSet { save("characterPoses", characterPoses) } }
    /// Hearts, Zs, sparkles, confetti… around Nova.
    var characterEffects: Bool { didSet { save("characterEffects", characterEffects) } }
    /// One-shot body reactions (hop, shake, pop) when the mood changes.
    var characterReactions: Bool { didSet { save("characterReactions", characterReactions) } }
    var motionIntensity: Double { didSet { save("motionIntensity", motionIntensity) } }
    /// "classic" (painted art) or "nova2" (code-drawn, rigged).
    var characterStyle: String { didSet { save("characterStyle", characterStyle) } }
    /// Nova 2 skin id (see `RigSkin`).
    var characterSkin: String { didSet { save("characterSkin", characterSkin) } }
    /// Animated scene backgrounds behind Nova 2.
    var sceneBackgrounds: Bool { didSet { save("sceneBackgrounds", sceneBackgrounds) } }
    /// Nova 2 dances on the beat while Spotify or Music plays.
    var danceToMusic: Bool { didSet { save("danceToMusic", danceToMusic) } }

    // Voice ("Hey Nova")
    var voiceEnabled: Bool { didSet { save("voiceEnabled", voiceEnabled) } }
    /// Always listen for "Hey Nova" (on-device; paused while locked).
    var voiceWakeWord: Bool { didSet { save("voiceWakeWord", voiceWakeWord) } }
    /// "auto", "en-US", "en-IN" or "ta-IN".
    var voiceLanguage: String { didSet { save("voiceLanguage", voiceLanguage) } }
    var voiceSpeakReplies: Bool { didSet { save("voiceSpeakReplies", voiceSpeakReplies) } }
    var voiceRate: Double { didSet { save("voiceRate", voiceRate) } }
    /// Keep listening for a few seconds after a reply, so you can ask a follow-up.
    var voiceFollowUps: Bool { didSet { save("voiceFollowUps", voiceFollowUps) } }
    /// A banner 5 minutes before each meeting (with its join link).
    var meetingNudges: Bool { didSet { save("meetingNudges", meetingNudges) } }

    // Agents
    var disabledAgents: Set<AgentKind> { didSet { save("disabledAgents", disabledAgents.map(\.rawValue)) } }

    // Security (Nova Guard)
    var securityEnabled: Bool { didSet { save("securityEnabled", securityEnabled) } }
    var securityPosture: Bool { didSet { save("securityPosture", securityPosture) } }
    var securityIntrusion: Bool { didSet { save("securityIntrusion", securityIntrusion) } }
    var securityPersistence: Bool { didSet { save("securityPersistence", securityPersistence) } }
    var securityCameraMic: Bool { didSet { save("securityCameraMic", securityCameraMic) } }
    /// Fix safe things automatically (quarantine risky startup items, stop reverse shells).
    var securityAutoFix: Bool { didSet { save("securityAutoFix", securityAutoFix) } }
    /// Deny high-risk agent commands while the Mac is locked or you're away.
    var securityAwayGuard: Bool { didSet { save("securityAwayGuard", securityAwayGuard) } }
    /// Always deny agent commands like reverse shells or curl|sh.
    var securityAgentDenyList: Bool { didSet { save("securityAgentDenyList", securityAgentDenyList) } }
    var securitySudoAlerts: Bool { didSet { save("securitySudoAlerts", securitySudoAlerts) } }
    var securityPortAlerts: Bool { didSet { save("securityPortAlerts", securityPortAlerts) } }
    var failedLoginThreshold: Int { didSet { save("failedLoginThreshold", failedLoginThreshold) } }

    // Notifications
    var notifications: Set<NovaNotificationKind> { didSet { save("notifications", notifications.map(\.rawValue)) } }
    var notifyOnlyWhenAway: Bool { didSet { save("notifyOnlyWhenAway", notifyOnlyWhenAway) } }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        func value<T>(_ key: String, _ fallback: T) -> T { defaults.object(forKey: "pref." + key) as? T ?? fallback }
        startHidden = value("startHidden", false)
        screen = ScreenChoice(rawValue: value("screen", "")) ?? .automatic
        onboardingDone = value("onboardingDone", false)
        panelSize = PanelSize(rawValue: value("panelSize", "")) ?? .regular
        animations = value("animations", true)
        reduceMotion = value("reduceMotion", false)
        glow = value("glow", 1.0)
        characterScale = value("characterScale", 1.0)
        eyeTracking = value("eyeTracking", true)
        characterPoses = value("characterPoses", true)
        characterEffects = value("characterEffects", true)
        characterReactions = value("characterReactions", true)
        motionIntensity = value("motionIntensity", 1.0)
        characterStyle = value("characterStyle", "nova2")
        characterSkin = value("characterSkin", "aurora")
        sceneBackgrounds = value("sceneBackgrounds", true)
        danceToMusic = value("danceToMusic", false)
        voiceEnabled = value("voiceEnabled", true)
        voiceWakeWord = value("voiceWakeWord", false)
        voiceLanguage = value("voiceLanguage", "auto")
        voiceSpeakReplies = value("voiceSpeakReplies", true)
        voiceRate = value("voiceRate", 0.5)
        voiceFollowUps = value("voiceFollowUps", true)
        meetingNudges = value("meetingNudges", true)
        disabledAgents = Set((value("disabledAgents", [String]()) as [String]).compactMap(AgentKind.init(rawValue:)))
        securityEnabled = value("securityEnabled", true)
        securityPosture = value("securityPosture", true)
        securityIntrusion = value("securityIntrusion", true)
        securityPersistence = value("securityPersistence", true)
        securityCameraMic = value("securityCameraMic", true)
        securityAutoFix = value("securityAutoFix", true)
        securityAwayGuard = value("securityAwayGuard", true)
        securityAgentDenyList = value("securityAgentDenyList", true)
        securitySudoAlerts = value("securitySudoAlerts", false)
        securityPortAlerts = value("securityPortAlerts", true)
        failedLoginThreshold = value("failedLoginThreshold", 3)
        let saved = defaults.object(forKey: "pref.notifications") as? [String]
        notifications = saved.map { Set($0.compactMap(NovaNotificationKind.init(rawValue:))) } ?? NotificationPolicy.defaults
        notifyOnlyWhenAway = value("notifyOnlyWhenAway", true)
    }

    private func save(_ key: String, _ value: Any) {
        defaults.set(value, forKey: "pref." + key)
    }

    /// True when motion should be minimal (user setting or system setting).
    var effectiveReduceMotion: Bool {
        reduceMotion || NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    var style: NovaStyle {
        NovaStyle(eyeTracking: eyeTracking,
                  motion: animations && !effectiveReduceMotion ? motionIntensity : 0,
                  animations: animations && !effectiveReduceMotion, glow: glow, characterScale: characterScale,
                  poses: characterPoses, effects: characterEffects && animations && !effectiveReduceMotion,
                  reactions: characterReactions && animations && !effectiveReduceMotion,
                  nova2: characterStyle == "nova2", skin: characterSkin,
                  scenes: sceneBackgrounds && animations && !effectiveReduceMotion)
    }

    /// Clears every preference (used by "Reset app data").
    func resetAll() {
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix("pref.") { defaults.removeObject(forKey: key) }
    }
}

/// Visual preferences read by views through the environment.
struct NovaStyle: Equatable {
    var eyeTracking = true
    /// 0 = still, 1 = normal, up to 1.5 = lively.
    var motion = 1.0
    var animations = true
    var glow = 1.0
    var characterScale = 1.0
    var poses = true
    var effects = true
    var reactions = true
    /// Draw Nova 2 (code-drawn, rigged) instead of the classic art.
    var nova2 = false
    var skin = "aurora"
    /// Animated scene backgrounds behind Nova 2.
    var scenes = true
    /// Stop all animation (Nova hidden, display asleep or screen locked).
    var paused = false
}

private struct NovaStyleKey: EnvironmentKey {
    static let defaultValue = NovaStyle()
}

extension EnvironmentValues {
    var novaStyle: NovaStyle {
        get { self[NovaStyleKey.self] }
        set { self[NovaStyleKey.self] = newValue }
    }
}
