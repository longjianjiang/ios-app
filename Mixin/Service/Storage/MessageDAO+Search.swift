import Foundation
import GRDB
import MixinServices

extension MessageDAO {
    
    func getMessages(conversationId: String, contentLike keyword: String, belowMessageId location: String?, limit: Int?) -> [MessageSearchResult] {
        let isFTSInitialized = AppGroupUserDefaults.Database.isFTSInitialized
        var results = [MessageSearchResult]()
        
        var sql = """
        SELECT m.id, m.category, m.content, m.created_at, u.user_id, u.full_name, u.avatar_url, u.is_verified, u.app_id
        FROM messages m LEFT JOIN users u ON m.user_id = u.user_id
        """
        let arguments: [String: String]
        
        if isFTSInitialized {
            sql += "\nWHERE m.id in (SELECT id FROM fts.\(Message.ftsTableName) WHERE \(Message.ftsTableName) MATCH :keyword) AND m.conversation_id = :conv_id"
            arguments = ["conv_id": conversationId, "keyword": keyword]
        } else {
            sql += """
                WHERE conversation_id = :conv_id
                    AND m.category in ('SIGNAL_TEXT','SIGNAL_DATA','SIGNAL_POST','PLAIN_TEXT','PLAIN_DATA','PLAIN_POST')
                    AND m.status != 'FAILED'
                    AND (m.content LIKE :keyword ESCAPE '/' OR m.name LIKE :keyword ESCAPE '/')
            """
            arguments = ["conv_id": conversationId, "keyword": "%\(keyword.sqlEscaped)%"]
        }
        if let location = location, let rowId: Int = UserDatabase.current.select(column: .rowID, from: Message.self, where: Message.column(of: .messageId) == location) {
            sql += "\nAND m.ROWID < \(rowId)"
        }
        if let limit = limit {
            sql += "\nORDER BY m.created_at DESC LIMIT \(limit)"
        } else {
            sql += "\nORDER BY m.created_at DESC"
        }
        
        try? UserDatabase.current.pool.write { (db) -> Void in
            do {
                if isFTSInitialized {
                    try db.execute(sql: "ATTACH DATABASE '\(AppGroupContainer.ftsDatabaseUrl.path)' AS fts")
                }
                let rows = try Row.fetchCursor(db, sql: sql, arguments: StatementArguments(arguments), adapter: nil)
                while let row = try rows.next() {
                    let counter = Counter(value: -1)
                    let result = MessageSearchResult(conversationId: conversationId,
                                                     messageId: row[counter.advancedValue] ?? "",
                                                     category: row[counter.advancedValue] ?? "",
                                                     content: row[counter.advancedValue] ?? "",
                                                     createdAt: row[counter.advancedValue] ?? "",
                                                     userId: row[counter.advancedValue] ?? "",
                                                     fullname: row[counter.advancedValue] ?? "",
                                                     avatarUrl: row[counter.advancedValue] ?? "",
                                                     isVerified: row[counter.advancedValue] ?? false,
                                                     appId: row[counter.advancedValue] ?? "",
                                                     keyword: keyword)
                    results.append(result)
                }
            } catch {
                Logger.writeDatabase(error: error)
                reporter.report(error: error)
            }
        }
        
        if isFTSInitialized {
            try? UserDatabase.current.pool.write({ (db) -> Void in
                try db.execute(sql: "DETACH DATABASE 'fts'")
            })
        }
        
        return results
    }
    
}
