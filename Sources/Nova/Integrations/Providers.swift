import Foundation
import NovaKit

@MainActor
final class GitHubIntegration: TokenIntegration, IntegrationProvider {
    init() { super.init(kind: .github, secret: .githubToken) }

    func refresh() async throws -> ServiceSnapshot {
        let headers = ["Authorization": "Bearer \(try await token())", "Accept": "application/vnd.github+json",
                       "X-GitHub-Api-Version": "2022-11-28"]
        let api = "https://api.github.com"
        func get(_ path: String, _ query: [(String, String)] = []) async throws -> Data {
            guard let url = ServiceHTTP.url(api, path, query) else { throw IntegrationError.missingConfig("URL") }
            return try await ServiceHTTP.get(url, headers: headers)
        }
        async let notifications = get("/notifications", [("per_page", "50")])
        async let reviews = get("/search/issues", [("q", "is:open is:pr review-requested:@me archived:false"), ("per_page", "10")])
        async let assigned = get("/search/issues", [("q", "is:open assignee:@me archived:false"), ("per_page", "10")])
        async let repos = get("/user/repos", [("sort", "pushed"), ("per_page", "5")])

        var runs: [GitHubDecoder.WorkflowRun] = []
        for repo in try GitHubDecoder.repoNames(try await repos) {
            if let data = try? await get("/repos/\(repo)/actions/runs", [("per_page", "1")]),
               let run = try? GitHubDecoder.latestRun(data, repo: repo) {
                runs.append(run)
            }
        }
        let snapshot = GitHubDecoder.snapshot(notifications: try GitHubDecoder.notifications(try await notifications),
                                              reviews: try GitHubDecoder.search(try await reviews),
                                              assigned: try GitHubDecoder.search(try await assigned), runs: runs)
        last = snapshot
        return snapshot
    }
}

@MainActor
final class VercelIntegration: TokenIntegration, IntegrationProvider {
    var config: () -> IntegrationConfig = { IntegrationConfig() }

    init() { super.init(kind: .vercel, secret: .vercelToken) }

    func refresh() async throws -> ServiceSnapshot {
        var query = [("limit", "20")]
        if let team = config().vercelTeamID, !team.isEmpty { query.append(("teamId", team)) }
        guard let url = ServiceHTTP.url("https://api.vercel.com", "/v6/deployments", query) else { throw IntegrationError.missingConfig("URL") }
        let data = try await ServiceHTTP.get(url, headers: ["Authorization": "Bearer \(try await token())"])
        let snapshot = VercelDecoder.snapshot(try VercelDecoder.deployments(data))
        last = snapshot
        return snapshot
    }
}

@MainActor
final class N8nIntegration: TokenIntegration, IntegrationProvider {
    var config: () -> IntegrationConfig = { IntegrationConfig() }

    init() { super.init(kind: .n8n, secret: .n8nKey) }

    override var isConnected: Bool { super.isConnected && !(config().n8nBaseURL ?? "").isEmpty }

    func refresh() async throws -> ServiceSnapshot {
        guard var base = config().n8nBaseURL?.trimmingCharacters(in: .whitespaces), !base.isEmpty else {
            throw IntegrationError.missingConfig("n8n URL")
        }
        while base.hasSuffix("/") { base.removeLast() }
        if !base.hasPrefix("http") { base = "https://" + base }
        let headers = ["X-N8N-API-KEY": try await token(), "Accept": "application/json"]
        guard let workflowsURL = ServiceHTTP.url(base, "/api/v1/workflows", [("limit", "100")]),
              let executionsURL = ServiceHTTP.url(base, "/api/v1/executions", [("limit", "100")]) else {
            throw IntegrationError.missingConfig("valid n8n URL")
        }
        async let workflows = ServiceHTTP.get(workflowsURL, headers: headers)
        async let executions = ServiceHTTP.get(executionsURL, headers: headers)
        let snapshot = N8nDecoder.snapshot(workflows: try N8nDecoder.workflows(try await workflows),
                                           executions: try N8nDecoder.executions(try await executions), baseURL: base)
        last = snapshot
        return snapshot
    }
}

@MainActor
final class SupabaseIntegration: TokenIntegration, IntegrationProvider {
    var config: () -> IntegrationConfig = { IntegrationConfig() }
    private(set) var projects: [SupabaseDecoder.Project] = []

    init() { super.init(kind: .supabase, secret: .supabaseKey) }

    func refresh() async throws -> ServiceSnapshot {
        let headers = ["Authorization": "Bearer \(try await token())"]
        guard let projectsURL = URL(string: "https://api.supabase.com/v1/projects") else { throw IntegrationError.missingConfig("URL") }
        projects = try SupabaseDecoder.projects(try await ServiceHTTP.get(projectsURL, headers: headers))
        let wanted = config().supabaseProjectRef
        guard let project = projects.first(where: { $0.ref == wanted }) ?? projects.first else {
            let snapshot = ServiceSnapshot(kind: .supabase, headline: "No projects", detail: "", health: .unknown)
            last = snapshot
            return snapshot
        }
        let query = ["db", "auth", "storage", "rest"].map { ("services", $0) }
        guard let healthURL = ServiceHTTP.url("https://api.supabase.com", "/v1/projects/\(project.ref)/health", query) else {
            throw IntegrationError.missingConfig("URL")
        }
        let services = try SupabaseDecoder.health(try await ServiceHTTP.get(healthURL, headers: headers))
        let snapshot = SupabaseDecoder.snapshot(project: project, services: services)
        last = snapshot
        return snapshot
    }
}

@MainActor
final class StripeIntegration: TokenIntegration, IntegrationProvider {
    init() { super.init(kind: .stripe, secret: .stripeKey) }

    func refresh() async throws -> ServiceSnapshot {
        let headers = ["Authorization": "Bearer \(try await token())"]
        let startOfDay = Int(Calendar.current.startOfDay(for: Date()).timeIntervalSince1970)
        guard let balanceURL = ServiceHTTP.url("https://api.stripe.com", "/v1/balance_transactions",
                                               [("created[gte]", String(startOfDay)), ("limit", "100")]),
              let chargesURL = ServiceHTTP.url("https://api.stripe.com", "/v1/charges", [("limit", "5")]) else {
            throw IntegrationError.missingConfig("URL")
        }
        async let balance = ServiceHTTP.get(balanceURL, headers: headers)
        async let charges = ServiceHTTP.get(chargesURL, headers: headers)
        let snapshot = StripeDecoder.snapshot(revenue: try StripeDecoder.revenueByCurrency(try await balance),
                                              payments: try StripeDecoder.payments(try await charges))
        last = snapshot
        return snapshot
    }
}

/// Firebase uses the Google sign-in (read-only Firebase + Cloud scopes).
@MainActor
final class FirebaseIntegration: IntegrationProvider {
    let kind = IntegrationKind.firebase
    private let google: GoogleAuth
    var config: () -> IntegrationConfig = { IntegrationConfig() }
    var setEnabled: (Bool) -> Void = { _ in }
    private var last: ServiceSnapshot?
    private(set) var projects: [FirebaseDecoder.Project] = []

    init(google: GoogleAuth) { self.google = google }

    var isConnected: Bool { google.isSignedIn && config().firebaseEnabled }

    func connect(token: String) throws { setEnabled(true) }
    func disconnect() { setEnabled(false); last = nil }
    func fetchSummary() -> ServiceSnapshot? { last }

    func refresh() async throws -> ServiceSnapshot {
        guard google.isSignedIn else { throw IntegrationError.notConnected(.firebase) }
        let projectsData: Data
        do {
            projectsData = try await google.get(URL(string: "https://firebase.googleapis.com/v1beta1/projects?pageSize=50")!)
        } catch AIError.http(403, _) {
            throw IntegrationError.missingConfig("Firebase access: reconnect Google in Settings → Automations")
        }
        projects = try FirebaseDecoder.projects(projectsData)
        let wanted = config().firebaseProjectID
        guard let project = projects.first(where: { $0.projectId == wanted }) ?? projects.first else {
            let snapshot = ServiceSnapshot(kind: .firebase, headline: "No projects", detail: "", health: .unknown)
            last = snapshot
            return snapshot
        }
        let p = project.projectId
        let databases = (try? FirebaseDecoder.databases(try await google.get(URL(string: "https://firestore.googleapis.com/v1/projects/\(p)/databases")!))) ?? []
        let functions = (try? FirebaseDecoder.functions(try await google.get(URL(string: "https://cloudfunctions.googleapis.com/v2/projects/\(p)/locations/-/functions")!))) ?? []
        var hosting: [(site: String, date: Date?, status: String)] = []
        let sites = (try? FirebaseDecoder.sites(try await google.get(URL(string: "https://firebasehosting.googleapis.com/v1beta1/projects/\(p)/sites")!))) ?? []
        for site in sites.prefix(3) {
            if let release = try? FirebaseDecoder.latestRelease(try await google.get(URL(string: "https://firebasehosting.googleapis.com/v1beta1/sites/\(site)/releases?pageSize=1")!)) {
                hosting.append((site, release.date, release.status))
            }
        }
        let snapshot = FirebaseDecoder.snapshot(project: project, databases: databases, functions: functions, hosting: hosting)
        last = snapshot
        return snapshot
    }
}
