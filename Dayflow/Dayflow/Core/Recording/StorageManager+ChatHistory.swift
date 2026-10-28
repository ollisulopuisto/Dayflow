import Foundation
import GRDB

/// Summary row for the chat history panel.
struct ChatConversationRecord: Identifiable, Sendable, Equatable {
  let id: UUID
  var title: String
  var provider: String
  var cliSessionId: String?
  let createdAt: Date
  var updatedAt: Date
}

extension StorageManager {
  // MARK: - Chat History Methods

  /// Upsert a conversation and replace its messages in one transaction.
  /// Conversations are small, so replace-all keeps persistence idempotent
  /// without any dirty-tracking in ChatService.
  func saveChatConversation(_ record: ChatConversationRecord, messages: [ChatMessage]) {
    try? timedWrite("saveChatConversation") { db in
      try db.execute(
        sql: """
              INSERT INTO chat_conversations (id, title, provider, cli_session_id, created_at, updated_at)
              VALUES (?, ?, ?, ?, ?, ?)
              ON CONFLICT(id) DO UPDATE SET
                  title = excluded.title,
                  provider = excluded.provider,
                  cli_session_id = excluded.cli_session_id,
                  updated_at = excluded.updated_at
          """,
        arguments: [
          record.id.uuidString,
          record.title,
          record.provider,
          record.cliSessionId,
          Int(record.createdAt.timeIntervalSince1970),
          Int(record.updatedAt.timeIntervalSince1970),
        ])

      try db.execute(
        sql: "DELETE FROM chat_messages WHERE conversation_id = ?",
        arguments: [record.id.uuidString])

      if !messages.isEmpty {
        let chunkSize = 100
        let enumeratedMessages = Array(messages.enumerated())
        for chunkStart in stride(from: 0, to: enumeratedMessages.count, by: chunkSize) {
          let chunk = enumeratedMessages[chunkStart..<min(chunkStart + chunkSize, enumeratedMessages.count)]
          let valuePlaceholders = Array(repeating: "(?, ?, ?, ?, ?, ?)", count: chunk.count).joined(separator: ", ")
          let sql = """
                INSERT INTO chat_messages (id, conversation_id, role, content, created_at, sort_order)
                VALUES \(valuePlaceholders)
            """
          var arguments: [DatabaseValueConvertible?] = []
          arguments.reserveCapacity(chunk.count * 6)
          for (index, message) in chunk {
            arguments.append(message.id.uuidString)
            arguments.append(record.id.uuidString)
            arguments.append(message.role.rawValue)
            arguments.append(message.content)
            arguments.append(Int(message.timestamp.timeIntervalSince1970))
            arguments.append(index)
          }
          try db.execute(sql: sql, arguments: StatementArguments(arguments))
        }
      }
    }
  }

  func fetchChatConversations() -> [ChatConversationRecord] {
    return
      (try? timedRead("fetchChatConversations") { db in
        let rows = try Row.fetchAll(
          db,
          sql: """
                SELECT id, title, provider, cli_session_id, created_at, updated_at
                FROM chat_conversations
                ORDER BY updated_at DESC
            """)

        return rows.compactMap { row -> ChatConversationRecord? in
          guard let id = UUID(uuidString: row["id"]) else { return nil }
          return ChatConversationRecord(
            id: id,
            title: row["title"],
            provider: row["provider"],
            cliSessionId: row["cli_session_id"],
            createdAt: Date(timeIntervalSince1970: TimeInterval(row["created_at"] as Int64)),
            updatedAt: Date(timeIntervalSince1970: TimeInterval(row["updated_at"] as Int64))
          )
        }
      }) ?? []
  }

  func fetchChatMessages(conversationId: UUID) -> [ChatMessage] {
    return
      (try? timedRead("fetchChatMessages") { db in
        let rows = try Row.fetchAll(
          db,
          sql: """
                SELECT id, role, content, created_at
                FROM chat_messages
                WHERE conversation_id = ?
                ORDER BY sort_order ASC
            """, arguments: [conversationId.uuidString])

        return rows.compactMap { row -> ChatMessage? in
          guard let id = UUID(uuidString: row["id"]),
            let role = ChatMessage.Role(rawValue: row["role"])
          else { return nil }
          return ChatMessage(
            id: id,
            role: role,
            content: row["content"],
            timestamp: Date(timeIntervalSince1970: TimeInterval(row["created_at"] as Int64))
          )
        }
      }) ?? []
  }

  func deleteChatConversation(id: UUID) {
    try? timedWrite("deleteChatConversation") { db in
      // Delete messages explicitly in case foreign keys are disabled.
      try db.execute(
        sql: "DELETE FROM chat_messages WHERE conversation_id = ?",
        arguments: [id.uuidString])
      try db.execute(
        sql: "DELETE FROM chat_conversations WHERE id = ?",
        arguments: [id.uuidString])
    }
  }
}
