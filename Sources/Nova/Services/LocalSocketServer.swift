import Darwin
import Foundation
import NovaKit

/// One accepted client. Thread-safety: every mutable property is only touched
/// on the server's serial `queue`, which is why this is `@unchecked Sendable`.
final class SocketConnection: @unchecked Sendable {
    let id = UUID()
    fileprivate let fd: Int32
    private let queue: DispatchQueue
    fileprivate var buffer = Data()
    fileprivate var source: DispatchSourceRead?
    fileprivate var isClosed = false
    /// Set once a full line arrives; idle connections are dropped.
    fileprivate var receivedLine = false
    fileprivate var onClose: (@Sendable (SocketConnection) -> Void)?

    fileprivate init(fd: Int32, queue: DispatchQueue) {
        self.fd = fd
        self.queue = queue
    }

    /// Sends one newline-terminated line, then optionally closes.
    func send(_ line: Data, thenClose: Bool = true) {
        queue.async {
            guard !self.isClosed else { return }
            _ = UnixSocket.writeAll(self.fd, line)
            if thenClose { self.closeOnQueue() }
        }
    }

    func close() {
        queue.async { self.closeOnQueue() }
    }

    fileprivate func closeOnQueue() {
        guard !isClosed else { return }
        isClosed = true
        source?.cancel()  // cancel handler closes the fd
        source = nil
        onClose?(self)
        onClose = nil
    }
}

/// Newline-delimited JSON server on a Unix-domain socket. Only accepts peers
/// running as the current user.
final class LocalSocketServer: @unchecked Sendable {
    typealias MessageHandler = @Sendable (Data, SocketConnection) -> Void
    typealias CloseHandler = @Sendable (SocketConnection) -> Void

    let path: String
    private let queue = DispatchQueue(label: "app.nova.socket")
    // Mutable state below is confined to `queue`.
    /// Hooks open one short connection per event; this caps a flood.
    static let maxConnections = 64
    static let firstLineTimeout: TimeInterval = 10
    private var listenFD: Int32 = -1
    private var acceptSource: DispatchSourceRead?
    private var connections: [UUID: SocketConnection] = [:]
    private let onMessage: MessageHandler
    private let onClose: CloseHandler

    init(path: String, onMessage: @escaping MessageHandler, onClose: @escaping CloseHandler) {
        self.path = path
        self.onMessage = onMessage
        self.onClose = onClose
    }

    func start() throws {
        try queue.sync { try startOnQueue() }
    }

    func stop() {
        queue.sync {
            connections.values.forEach { $0.closeOnQueue() }
            connections.removeAll()
            acceptSource?.cancel()
            acceptSource = nil
            unlink(path)
        }
    }

    private func startOnQueue() throws {
        let directory = (path as NSString).deletingLastPathComponent
        try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        unlink(path)  // stale socket from a previous run

        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw UnixSocket.SocketError.system("socket", errno) }
        let bound = try UnixSocket.withAddress(path) { bind(fd, $0, $1) == 0 }
        guard bound, listen(fd, 16) == 0 else {
            let err = errno
            Darwin.close(fd)
            throw UnixSocket.SocketError.system("bind/listen", err)
        }
        chmod(path, 0o600)
        _ = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK)
        listenFD = fd

        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        source.setEventHandler { [weak self] in self?.acceptPending() }
        source.setCancelHandler { Darwin.close(fd) }
        source.resume()
        acceptSource = source
    }

    private func acceptPending() {
        while true {
            let client = accept(listenFD, nil, nil)
            guard client >= 0 else { return }

            var uid: uid_t = 0, gid: gid_t = 0
            guard getpeereid(client, &uid, &gid) == 0, uid == getuid(), connections.count < Self.maxConnections else {
                Darwin.close(client)
                continue
            }
            var noSigPipe: Int32 = 1
            setsockopt(client, SOL_SOCKET, SO_NOSIGPIPE, &noSigPipe, socklen_t(MemoryLayout<Int32>.size))
            _ = fcntl(client, F_SETFL, fcntl(client, F_GETFL) | O_NONBLOCK)

            let connection = SocketConnection(fd: client, queue: queue)
            connection.onClose = { [weak self] conn in
                self?.connections[conn.id] = nil
                self?.onClose(conn)
            }
            let source = DispatchSource.makeReadSource(fileDescriptor: client, queue: queue)
            source.setEventHandler { [weak self, weak connection] in
                guard let self, let connection else { return }
                self.read(from: connection)
            }
            source.setCancelHandler { Darwin.close(client) }
            connection.source = source
            connections[connection.id] = connection
            source.resume()
            // A client that connects but never sends a full line is dropped.
            queue.asyncAfter(deadline: .now() + Self.firstLineTimeout) { [weak connection] in
                guard let connection, !connection.receivedLine else { return }
                connection.closeOnQueue()
            }
        }
    }

    private func read(from connection: SocketConnection) {
        var chunk = [UInt8](repeating: 0, count: 4096)
        let n = Darwin.read(connection.fd, &chunk, chunk.count)
        if n <= 0 {
            if n < 0, errno == EAGAIN { return }
            connection.closeOnQueue()  // peer hung up
            return
        }
        connection.buffer.append(contentsOf: chunk[0..<n])
        if connection.buffer.count > AgentEventDecoder.maxMessageSize {
            connection.closeOnQueue()
            return
        }
        while let newline = connection.buffer.firstIndex(of: 0x0A) {
            let line = connection.buffer.prefix(upTo: newline)
            connection.buffer.removeSubrange(...newline)
            connection.receivedLine = true
            if !line.isEmpty { onMessage(Data(line), connection) }
        }
    }
}
