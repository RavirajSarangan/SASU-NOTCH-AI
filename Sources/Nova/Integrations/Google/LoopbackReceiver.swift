import Foundation
import Network

/// One-shot HTTP listener on 127.0.0.1 for the OAuth redirect.
/// Thread-safety: state is only touched on `queue` (hence @unchecked Sendable).
final class LoopbackReceiver: @unchecked Sendable {
    private let queue = DispatchQueue(label: "app.nova.oauth-loopback")
    private var listener: NWListener?
    private var continuation: CheckedContinuation<[String: String], Error>?
    private var readyContinuation: CheckedContinuation<UInt16, Error>?

    /// Starts listening on a random port and returns it.
    func start() async throws -> UInt16 {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        let listener = try NWListener(using: parameters)
        self.listener = listener
        return try await withCheckedThrowingContinuation { (ready: CheckedContinuation<UInt16, Error>) in
            readyContinuation = ready
            listener.stateUpdateHandler = { [weak self] state in
                guard let self, let ready = self.readyContinuation else { return }
                switch state {
                case .ready:
                    self.readyContinuation = nil
                    ready.resume(returning: self.listener?.port?.rawValue ?? 0)
                case .failed(let error):
                    self.readyContinuation = nil
                    ready.resume(throwing: error)
                default: break
                }
            }
            listener.newConnectionHandler = { [weak self] connection in self?.handle(connection) }
            listener.start(queue: queue)
        }
    }

    /// Waits for the browser redirect and returns its query parameters.
    func waitForCallback(timeout: Duration = .seconds(300)) async throws -> [String: String] {
        let timeoutTask = Task { [weak self] in
            try? await Task.sleep(for: timeout)
            self?.finish(.failure(URLError(.timedOut)))
        }
        defer { timeoutTask.cancel() }
        return try await withCheckedThrowingContinuation { continuation in
            queue.async { self.continuation = continuation }
        }
    }

    func stop() {
        queue.async {
            self.listener?.cancel()
            self.listener = nil
        }
    }

    private func handle(_ connection: NWConnection) {
        connection.start(queue: queue)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16_384) { [weak self] data, _, _, _ in
            guard let self, let data, let request = String(data: data, encoding: .utf8),
                  let line = request.split(separator: "\r\n").first else { connection.cancel(); return }
            // "GET /?code=...&state=... HTTP/1.1"
            let parts = line.split(separator: " ")
            let target = parts.count > 1 ? String(parts[1]) : "/"
            let items = URLComponents(string: "http://localhost\(target)")?.queryItems ?? []
            let params = Dictionary(items.map { ($0.name, $0.value ?? "") }, uniquingKeysWith: { a, _ in a })
            guard params["code"] != nil || params["error"] != nil else {
                connection.send(content: Self.response("Not found"), completion: .contentProcessed { _ in connection.cancel() })
                return
            }
            let ok = params["error"] == nil
            let page = ok ? "Nova is connected to Google. You can close this tab." : "Sign-in was cancelled. You can close this tab."
            connection.send(content: Self.response(page), completion: .contentProcessed { _ in connection.cancel() })
            self.finish(.success(params))
        }
    }

    private func finish(_ result: Result<[String: String], Error>) {
        queue.async {
            guard let continuation = self.continuation else { return }
            self.continuation = nil
            continuation.resume(with: result)
            self.listener?.cancel()
            self.listener = nil
        }
    }

    private static func response(_ message: String) -> Data {
        let body = """
        <!doctype html><meta charset="utf-8"><title>Nova</title>
        <body style="font-family:-apple-system;background:#0A0B10;color:#F5F7FF;display:grid;place-items:center;height:100vh;margin:0">
        <p style="font-size:18px">\(message)</p></body>
        """
        let head = "HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: \(body.utf8.count)\r\nConnection: close\r\n\r\n"
        return Data((head + body).utf8)
    }
}
