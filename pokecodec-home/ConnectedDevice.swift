import Foundation
import SwiftData

@Model
final class ConnectedDevice {
    @Attribute(.unique) var secret: String
    var name: String
    var lockId: Int
    var lastSyncTimestamp: Double
    
    init(secret: String, name: String, lockId: Int, timestamp: Double) {
        self.secret = secret
        self.name = name
        self.lockId = lockId
        self.lastSyncTimestamp = timestamp
    }
}
