import Darwin
import Foundation

/// Minimal blocking Unix-domain socket helpers shared by the app and the hook.
public enum UnixSocket {
    public enum SocketError: Error, Equatable {
        case pathTooLong
        case system(String, Int32)
    }

    /// Builds a `sockaddr_un` for `path` and passes it to `body`.
    public static func withAddress<T>(_ path: String, _ body: (UnsafePointer<sockaddr>, socklen_t) throws -> T) throws -> T {
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(path.utf8)
        let capacity = MemoryLayout.size(ofValue: addr.sun_path)
        guard bytes.count < capacity else { throw SocketError.pathTooLong }
        withUnsafeMutableBytes(of: &addr.sun_path) { raw in
            raw.copyBytes(from: bytes)
            raw[bytes.count] = 0
        }
        return try withUnsafePointer(to: &addr) { ptr in
            try ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                try body($0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
    }

    /// Writes all of `data`, retrying on partial writes.
    public static func writeAll(_ fd: Int32, _ data: Data) -> Bool {
        data.withUnsafeBytes { raw -> Bool in
            guard var base = raw.baseAddress else { return true }
            var remaining = raw.count
            while remaining > 0 {
                let n = Darwin.write(fd, base, remaining)
                if n < 0 {
                    if errno == EINTR { continue }
                    return false
                }
                remaining -= n
                base = base.advanced(by: n)
            }
            return true
        }
    }

    /// Client side: connects, sends one line, and optionally waits for a
    /// one-line reply. Returns nil if Nova isn't listening.
    public static func request(path: String, line: Data, awaitReply: Bool, timeout: TimeInterval) -> Data? {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return nil }
        defer { close(fd) }

        var noSigPipe: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &noSigPipe, socklen_t(MemoryLayout<Int32>.size))

        let connected = (try? withAddress(path) { connect(fd, $0, $1) == 0 }) ?? false
        guard connected, writeAll(fd, line) else { return nil }
        guard awaitReply else { return Data() }

        var tv = timeval(tv_sec: Int(timeout), tv_usec: Int32((timeout - floor(timeout)) * 1_000_000))
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))

        var reply = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while reply.count < AgentEventDecoder.maxMessageSize {
            let n = read(fd, &buffer, buffer.count)
            if n <= 0 { break }  // EOF, timeout or error
            reply.append(contentsOf: buffer[0..<n])
            if let newline = reply.firstIndex(of: 0x0A) { return reply.prefix(upTo: newline) }
        }
        return reply.isEmpty ? nil : reply
    }
}
