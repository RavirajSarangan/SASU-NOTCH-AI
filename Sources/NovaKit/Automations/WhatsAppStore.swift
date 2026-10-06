import Foundation
import SQLite3

public struct WAChat: Identifiable, Sendable, Equatable, Codable {
    public let id: Int64
    public var jid: String
    public var name: String
    public var lastMessageDate: Date?
    /// International number as digits ("447700900123"), when WhatsApp knows it.
    /// Chats keyed by a privacy LID only have one if the contact is saved.
    public var phone: String?

    public init(id: Int64, jid: String, name: String, lastMessageDate: Date?, phone: String? = nil) {
        self.id = id
        self.jid = jid
        self.name = name
        self.lastMessageDate = lastMessageDate
        self.phone = phone ?? Self.digits(ofPhoneJID: jid)
    }

    /// "447700900123@s.whatsapp.net" → "447700900123"
    public static func digits(ofPhoneJID jid: String?) -> String? {
        guard let jid, jid.hasSuffix("@s.whatsapp.net") else { return nil }
        let digits = jid.prefix { $0 != "@" }
        return !digits.isEmpty && digits.allSatisfy(\.isNumber) && digits != "0" ? String(digits) : nil
    }
}

public struct WAMessage: Identifiable, Sendable, Equatable {
    public let id: Int64
    public var chatId: Int64
    public var isFromMe: Bool
    public var text: String
    public var date: Date

    public init(id: Int64, chatId: Int64, isFromMe: Bool, text: String, date: Date) {
        self.id = id
        self.chatId = chatId
        self.isFromMe = isFromMe
        self.text = text
        self.date = date
    }
}

/// Read-only access to WhatsApp for Mac's local database
/// (~/Library/Group Containers/group.net.whatsapp.WhatsApp.shared/ChatStorage.sqlite).
/// The schema is undocumented, so it's validated up front and every query
/// fails soft. Nova never writes to this database.
public final class WhatsAppStore {
    public enum StoreError: Error, Equatable {
        case cannotOpen(String)
        case schemaChanged(String)
    }

    public static var containerPath: String {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Group Containers/group.net.whatsapp.WhatsApp.shared").path
    }

    public static var defaultPath: String { containerPath + "/ChatStorage.sqlite" }

    /// WhatsApp's address book, which maps privacy LIDs to phone numbers.
    public static var defaultContactsPath: String { containerPath + "/ContactsV2.sqlite" }

    static let requiredColumns: [String: [String]] = [
        "ZWACHATSESSION": ["Z_PK", "ZCONTACTJID", "ZPARTNERNAME", "ZLASTMESSAGEDATE", "ZSESSIONTYPE"],
        "ZWAMESSAGE": ["Z_PK", "ZCHATSESSION", "ZISFROMME", "ZTEXT", "ZMESSAGEDATE"],
    ]

    private var db: OpaquePointer?
    private let contactsPath: String?
    private var hasHiddenColumn = false

    public init(path: String = WhatsAppStore.defaultPath, contactsPath: String? = WhatsAppStore.defaultContactsPath) throws {
        self.contactsPath = contactsPath
        guard sqlite3_open_v2(path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            let message = db.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown error"
            sqlite3_close(db)
            db = nil
            throw StoreError.cannotOpen(message)
        }
        sqlite3_busy_timeout(db, 2000)
        try validateSchema()
    }

    deinit { sqlite3_close(db) }

    private func validateSchema() throws {
        for (table, columns) in Self.requiredColumns {
            let present = Set(try rows("SELECT name FROM pragma_table_info('\(table)')") { Self.text($0, 0) ?? "" })
            if present.isEmpty { throw StoreError.schemaChanged("missing table \(table)") }
            if table == "ZWACHATSESSION" { hasHiddenColumn = present.contains("ZHIDDEN") }
            for column in columns where !present.contains(column) {
                throw StoreError.schemaChanged("missing \(table).\(column)")
            }
        }
    }

    /// One-to-one chats, most recent first. Newer WhatsApp versions key these
    /// by a privacy LID ("…@lid"); older ones by phone ("…@s.whatsapp.net").
    public func chats(limit: Int = 400) throws -> [WAChat] {
        let phones = lidPhoneMap()
        return try rows("""
            SELECT Z_PK, ZCONTACTJID, ZPARTNERNAME, ZLASTMESSAGEDATE FROM ZWACHATSESSION
            WHERE ZSESSIONTYPE = 0
              AND (ZCONTACTJID LIKE '%@lid' OR ZCONTACTJID LIKE '%@s.whatsapp.net')
              AND ZCONTACTJID != '0@s.whatsapp.net'
              \(hasHiddenColumn ? "AND IFNULL(ZHIDDEN, 0) = 0" : "")
            ORDER BY ZLASTMESSAGEDATE DESC LIMIT ?
            """, bind: [.int(Int64(limit))]) { row in
            let jid = Self.text(row, 1) ?? ""
            return WAChat(id: sqlite3_column_int64(row, 0), jid: jid, name: Self.text(row, 2) ?? "",
                          lastMessageDate: Self.date(row, 3), phone: phones[jid])
        }
    }

    /// LID → phone digits from WhatsApp's address book. Empty if it can't be read.
    func lidPhoneMap() -> [String: String] {
        guard let contactsPath, FileManager.default.fileExists(atPath: contactsPath) else { return [:] }
        var contacts: OpaquePointer?
        defer { sqlite3_close(contacts) }
        guard sqlite3_open_v2(contactsPath, &contacts, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else { return [:] }
        var statement: OpaquePointer?
        let sql = "SELECT ZLID, ZWHATSAPPID FROM ZWAADDRESSBOOKCONTACT WHERE ZLID IS NOT NULL AND ZWHATSAPPID IS NOT NULL"
        guard sqlite3_prepare_v2(contacts, sql, -1, &statement, nil) == SQLITE_OK, let statement else { return [:] }
        defer { sqlite3_finalize(statement) }
        var map: [String: String] = [:]
        while sqlite3_step(statement) == SQLITE_ROW {
            if let lid = Self.text(statement, 0), let phone = WAChat.digits(ofPhoneJID: Self.text(statement, 1)) {
                map[lid] = phone
            }
        }
        return map
    }

    /// Latest text messages in a chat, oldest first.
    public func messages(chatId: Int64, limit: Int = 30) throws -> [WAMessage] {
        try rows("""
            SELECT Z_PK, ZCHATSESSION, ZISFROMME, ZTEXT, ZMESSAGEDATE FROM ZWAMESSAGE
            WHERE ZCHATSESSION = ? AND ZTEXT IS NOT NULL AND ZTEXT != ''
            ORDER BY ZMESSAGEDATE DESC LIMIT ?
            """, bind: [.int(chatId), .int(Int64(limit))], map: Self.message).reversed()
    }

    /// Incoming text messages newer than `rowId`, for the given chats.
    public func incoming(after rowId: Int64, chatIds: [Int64]) throws -> [WAMessage] {
        guard !chatIds.isEmpty else { return [] }
        let placeholders = Array(repeating: "?", count: chatIds.count).joined(separator: ",")
        return try rows("""
            SELECT Z_PK, ZCHATSESSION, ZISFROMME, ZTEXT, ZMESSAGEDATE FROM ZWAMESSAGE
            WHERE Z_PK > ? AND ZISFROMME = 0 AND ZTEXT IS NOT NULL AND ZTEXT != '' AND ZCHATSESSION IN (\(placeholders))
            ORDER BY Z_PK ASC
            """, bind: [.int(rowId)] + chatIds.map { .int($0) }, map: Self.message)
    }

    public func maxMessageId() throws -> Int64 {
        try rows("SELECT IFNULL(MAX(Z_PK), 0) FROM ZWAMESSAGE") { sqlite3_column_int64($0, 0) }.first ?? 0
    }

    /// True if a message with this text was sent by me in the chat after `date`
    /// (used to confirm a send actually went through).
    public func hasOutgoing(chatId: Int64, text: String, after date: Date) throws -> Bool {
        try rows("""
            SELECT COUNT(*) FROM ZWAMESSAGE WHERE ZCHATSESSION = ? AND ZISFROMME = 1 AND ZTEXT = ? AND ZMESSAGEDATE >= ?
            """, bind: [.int(chatId), .text(text), .double(date.timeIntervalSinceReferenceDate - 5)]) {
            sqlite3_column_int64($0, 0)
        }.first ?? 0 > 0
    }

    // MARK: - SQLite helpers

    enum Binding { case int(Int64), double(Double), text(String) }

    private func rows<T>(_ sql: String, bind: [Binding] = [], map: (OpaquePointer) throws -> T) throws -> [T] {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw StoreError.schemaChanged(db.map { String(cString: sqlite3_errmsg($0)) } ?? "prepare failed")
        }
        defer { sqlite3_finalize(statement) }
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        for (i, value) in bind.enumerated() {
            let index = Int32(i + 1)
            switch value {
            case .int(let v): sqlite3_bind_int64(statement, index, v)
            case .double(let v): sqlite3_bind_double(statement, index, v)
            case .text(let v): sqlite3_bind_text(statement, index, v, -1, transient)
            }
        }
        var result: [T] = []
        while true {
            let step = sqlite3_step(statement)
            if step == SQLITE_ROW { result.append(try map(statement)) } else if step == SQLITE_DONE { break } else {
                throw StoreError.schemaChanged(String(cString: sqlite3_errmsg(db)))
            }
        }
        return result
    }

    private static func text(_ row: OpaquePointer, _ column: Int32) -> String? {
        sqlite3_column_text(row, column).map { String(cString: $0) }
    }

    /// Core Data stores dates as seconds since 2001-01-01.
    private static func date(_ row: OpaquePointer, _ column: Int32) -> Date? {
        sqlite3_column_type(row, column) == SQLITE_NULL ? nil : Date(timeIntervalSinceReferenceDate: sqlite3_column_double(row, column))
    }

    private static func message(_ row: OpaquePointer) -> WAMessage {
        WAMessage(id: sqlite3_column_int64(row, 0), chatId: sqlite3_column_int64(row, 1),
                  isFromMe: sqlite3_column_int(row, 2) != 0, text: text(row, 3) ?? "",
                  date: date(row, 4) ?? .distantPast)
    }
}
