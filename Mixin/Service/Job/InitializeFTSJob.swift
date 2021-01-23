import Foundation
import MixinServices

class InitializeFTSJob: BaseJob {
    
    enum Error: Swift.Error {
        case mismatchedFTSTable
    }
    
    private static let insertionLimit: Int = 1000
    
    private let insertionSQL = """
        INSERT INTO \(Message.ftsTableName)
        SELECT id, conversation_id, content, name
        FROM user.\(Message.databaseTableName)
        WHERE category in \(MessageCategory.ftsAvailableCategorySequence) AND status != 'FAILED' AND ROWID > ?
        ORDER BY created_at ASC
        LIMIT \(InitializeFTSJob.insertionLimit)
    """
    
    override func getJobId() -> String {
        return "initialize-fts"
    }
    
    override func run() throws {
        guard !AppGroupUserDefaults.Database.isFTSInitialized else {
            return
        }
        
        var didInitializedAllMessages = false
        var numberOfMessagesProcessed = 0
        let startDate = Date()
        
        try FTSDatabase.current.pool.write { (db) -> Void in
            try db.execute(sql: "ATTACH DATABASE '\(AppGroupContainer.userDatabaseUrl.path)' AS user")
        }
        defer {
            try? FTSDatabase.current.pool.write { (db) -> Void in
                try db.execute(sql: "DETACH DATABASE 'user'")
            }
        }
        
        while !didInitializedAllMessages && !MixinService.isStopProcessMessages {
            guard !isCancelled else {
                return
            }
            do {
                try FTSDatabase.current.pool.write { (db) -> Void in
                    let lastInitializedRowID: Int?
                    let lastFTSMessageIDSQL = "SELECT id FROM \(Message.ftsTableName) ORDER BY rowid DESC LIMIT 1"
                    if let lastFTSMessageID = try String.fetchOne(db, sql: lastFTSMessageIDSQL) {
                        lastInitializedRowID = try Int.fetchOne(db,
                                                                sql: "SELECT rowid FROM user.messages WHERE id=?",
                                                                arguments: [lastFTSMessageID])
                    } else {
                        lastInitializedRowID = -1
                    }
                    guard let rowID = lastInitializedRowID else {
                        throw Error.mismatchedFTSTable
                    }
                    try db.execute(sql: insertionSQL, arguments: [rowID])
                    let numberOfChanges = db.changesCount
                    numberOfMessagesProcessed += numberOfChanges
                    Logger.writeDatabase(log: "[FTS] \(numberOfChanges) messages are wrote into FTS table")
                    didInitializedAllMessages = numberOfChanges < Self.insertionLimit
                    if didInitializedAllMessages {
                        AppGroupUserDefaults.Database.isFTSInitialized = true
                    }
                }
            } catch {
                Logger.writeDatabase(error: error)
                reporter.report(error: error)
                return
            }
        }
        
        let interval = -startDate.timeIntervalSinceNow
        Logger.writeDatabase(log: "[FTS] Initialized \(numberOfMessagesProcessed) messages in \(interval)s")
    }
    
}
