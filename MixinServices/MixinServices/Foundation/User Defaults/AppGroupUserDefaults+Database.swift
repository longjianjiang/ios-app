import Foundation

extension AppGroupUserDefaults {
    
    public enum Database {
        
        @Default(namespace: .database, key: "vacuum_date", defaultValue: .distantPast)
        public static var vacuumDate: Date
        
        @Default(namespace: .database, key: "sent_sender_key_cleared", defaultValue: true)
        public static var isSentSenderKeyCleared: Bool
        
        // There was a "fts_initialized" existed on internal test builds
        // Use v2 and ignore the previous one
        @Default(namespace: .database, key: "fts_v2_initialized", defaultValue: false)
        public static var isFTSInitialized: Bool
        
        internal static func migrate() {
            vacuumDate = Date(timeIntervalSince1970: DatabaseUserDefault.shared.lastVacuumTime)
            isSentSenderKeyCleared = !DatabaseUserDefault.shared.clearSentSenderKey
        }
        
    }
    
}
