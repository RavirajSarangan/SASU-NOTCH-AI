import Foundation
import NovaKit
import Observation

/// Owns the integration providers, refreshes them, and reports health changes.
@Observable
@MainActor
final class IntegrationManager {
    private(set) var snapshots: [IntegrationKind: ServiceSnapshot] = [:]
    private(set) var errors: [IntegrationKind: String] = [:]
    private(set) var refreshing: Set<IntegrationKind> = []
    private(set) var version = 0

    var config: IntegrationConfig {
        didSet {
            guard config != oldValue, let data = try? JSONEncoder().encode(config) else { return }
            UserDefaults.standard.set(data, forKey: Self.configKey)
        }
    }

    @ObservationIgnored let providers: [IntegrationKind: any IntegrationProvider]
    /// Fired when a connected service gets worse (e.g. a deploy fails).
    @ObservationIgnored var onHealthWorsened: ((ServiceSnapshot) -> Void)?
    /// Refresh only while this returns true (e.g. Nova is visible).
    @ObservationIgnored var shouldAutoRefresh: () -> Bool = { true }
    @ObservationIgnored private var loop: Task<Void, Never>?

    private static let configKey = "integrations.config"
    static let interval: Duration = .seconds(60)

    init(google: GoogleAuth) {
        config = UserDefaults.standard.data(forKey: Self.configKey)
            .flatMap { try? JSONDecoder().decode(IntegrationConfig.self, from: $0) } ?? IntegrationConfig()
        let vercel = VercelIntegration(), n8n = N8nIntegration(), supabase = SupabaseIntegration()
        let firebase = FirebaseIntegration(google: google)
        providers = [.github: GitHubIntegration(), .vercel: vercel, .n8n: n8n, .supabase: supabase,
                     .stripe: StripeIntegration(), .firebase: firebase]
        vercel.config = { [unowned self] in config }
        n8n.config = { [unowned self] in config }
        supabase.config = { [unowned self] in config }
        firebase.config = { [unowned self] in config }
        firebase.setEnabled = { [unowned self] in config.firebaseEnabled = $0 }
    }

    func start() {
        loop = Task { [weak self] in
            while !Task.isCancelled {
                if let self, self.shouldAutoRefresh() { await self.refreshAll() }
                try? await Task.sleep(for: Self.interval)
            }
        }
    }

    func isConnected(_ kind: IntegrationKind) -> Bool {
        _ = version
        return providers[kind]?.isConnected ?? false
    }

    var connectedKinds: [IntegrationKind] { IntegrationKind.allCases.filter(isConnected) }

    func refreshAll() async {
        // Each refresh awaits the network, so these interleave on the main actor.
        let tasks = connectedKinds.map { kind in Task { await self.refresh(kind) } }
        for task in tasks { await task.value }
    }

    func refresh(_ kind: IntegrationKind) async {
        guard let provider = providers[kind], provider.isConnected, !refreshing.contains(kind) else { return }
        refreshing.insert(kind)
        defer { refreshing.remove(kind) }
        do {
            let snapshot = try await provider.refresh()
            let previous = snapshots[kind]
            snapshots[kind] = snapshot
            errors[kind] = nil
            if let previous, snapshot.health == .failing, previous.health < .failing {
                onHealthWorsened?(snapshot)
            }
        } catch {
            errors[kind] = error.localizedDescription
            Log.integrations.error("\(kind.rawValue, privacy: .public) refresh failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Saves the token and verifies it with a refresh. Rolls back on failure.
    func connect(_ kind: IntegrationKind, token: String) async throws {
        guard let provider = providers[kind] else { return }
        try provider.connect(token: token)
        version += 1
        await refresh(kind)
        if let error = errors[kind] {
            provider.disconnect()
            version += 1
            throw IntegrationError.missingConfig(error)
        }
    }

    func disconnect(_ kind: IntegrationKind) {
        providers[kind]?.disconnect()
        snapshots[kind] = nil
        errors[kind] = nil
        version += 1
    }

    var supabaseProjects: [SupabaseDecoder.Project] { (providers[.supabase] as? SupabaseIntegration)?.projects ?? [] }
    var firebaseProjects: [FirebaseDecoder.Project] { (providers[.firebase] as? FirebaseIntegration)?.projects ?? [] }

    #if DEBUG
    func loadPreview() {
        snapshots = [
            .github: GitHubDecoder.snapshot(
                notifications: (1...3).map { ServiceItem(id: "\($0)", title: "Notification \($0)", subtitle: "me/nova") },
                reviews: (2, [ServiceItem(id: "r1", title: "Add retry with backoff", subtitle: "me/nova #7", health: .attention),
                              ServiceItem(id: "r2", title: "Docs: setup guide", subtitle: "me/web #9", health: .attention)]),
                assigned: (0, []),
                runs: [GitHubDecoder.WorkflowRun(repo: "me/web", name: "CI", status: "completed", conclusion: "failure", url: nil, updated: Date())]),
            .vercel: VercelDecoder.snapshot([VercelDecoder.Deployment(id: "d", project: "portfolio", state: "READY", target: "production", url: nil, created: Date().addingTimeInterval(-120))]),
            .n8n: N8nDecoder.snapshot(workflows: (1...12).map { N8nDecoder.Workflow(id: "\($0)", name: "Flow \($0)", active: true) },
                                      executions: (1...49).map { N8nDecoder.Execution(id: "\($0)", workflowId: "1", status: "success", startedAt: nil) }
                                        + [N8nDecoder.Execution(id: "50", workflowId: "2", status: "error", startedAt: Date.distantPast)],
                                      baseURL: "https://n8n.example.com"),
            .supabase: SupabaseDecoder.snapshot(project: SupabaseDecoder.Project(ref: "abcd", name: "nova-db", region: "eu-west-2", status: "ACTIVE_HEALTHY"),
                                                services: ["db", "auth", "storage", "rest"].map { SupabaseDecoder.ServiceStatus(name: $0, healthy: true, status: "ACTIVE_HEALTHY") }),
            .stripe: StripeDecoder.snapshot(revenue: ["gbp": 125_542], payments: [StripeDecoder.Payment(id: "ch_1", amount: 4900, currency: "gbp", status: "succeeded", created: Date(), refunded: false)]),
        ]
    }
    #endif
}
