import Foundation
import SwiftData

@Model
final class ConnectedDevice {
    @Attribute(.unique) var secret: String
    var name: String
    var lockId: Int
    var lastSyncTimestamp: Double
    
    @Relationship(deleteRule: .cascade, inverse: \TeamHistory.device) var history: [TeamHistory] = []
    
    init(secret: String, name: String, lockId: Int, timestamp: Double) {
        self.secret = secret
        self.name = name
        self.lockId = lockId
        self.lastSyncTimestamp = timestamp
    }
}
