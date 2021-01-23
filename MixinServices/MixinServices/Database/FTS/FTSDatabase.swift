import GRDB

public class FTSDatabase: Database {
    
    public private(set) static var current: FTSDatabase! = loadCurrent()
    
    public override class var config: Configuration {
        var config = super.config
        config.label = "FTS"
        config.prepareDatabase { (db) in
            db.add(tokenizer: MixinTokenizer.self)
        }
        return config
    }
    
    private var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        
        migrator.registerMigration("create") { db in
            try db.create(virtualTable: Message.ftsTableName, ifNotExists: true, using: FTS5()) { t in
                t.tokenizer = MixinTokenizer.tokenizerDescriptor()
                t.column("id").notIndexed()
                t.column("conversation_id").notIndexed()
                t.column("content")
                t.column("name")
            }
        }
        
        return migrator
    }
    
    public static func reloadCurrent() {
        current = loadCurrent()
    }
    
    private static func loadCurrent() -> FTSDatabase {
        let db = try! FTSDatabase(url: AppGroupContainer.ftsDatabaseUrl)
        db.migrate()
        return db
    }
    
    private func migrate() {
        try! migrator.migrate(pool)
    }
    
}
