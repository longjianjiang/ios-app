import Foundation

internal class MessageFTSDAO {
    
    static let shared = MessageFTSDAO()
    
    private var db: Database {
        FTSDatabase.current
    }
    
    func insert(id: String, conversationId: String, content: String?, name: String?) {
        try db.write { (db) in
            try db.execute(sql: "INSERT INTO \(Message.ftsTableName) VALUES (?, ?, ?, ?)",
                           arguments: [id, conversationId, content, name])
        }
    }
    
    func deleteAllMessages(with conversationId: String) throws {
        try db.write { (db) in
            let sql = "DELETE FROM \(Message.ftsTableName) WHERE conversation_id = ?"
            try db.execute(sql: sql, arguments: [conversationId])
        }
    }
    
    func deleteMessage(with messageId: String) throws {
        try db.write { (db) in
            try db.execute(sql: "DELETE FROM \(Message.ftsTableName) WHERE id=?",
                           arguments: [messageId])
        }
    }
    
}
