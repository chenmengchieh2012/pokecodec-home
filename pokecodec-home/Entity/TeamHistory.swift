import Foundation
import SwiftData

@Model
final class TeamHistory {
    var timestamp: Double
    var lockId: Int
    var teamJson: Data
    var isSynced: Bool = false
    
    // 移除與 ConnectedDevice 的關聯
    // var device: ConnectedDevice?
    
    init(timestamp: Double, lockId: Int, teamJson: Data, isSynced: Bool = false) {
        self.timestamp = timestamp
        self.lockId = lockId
        self.teamJson = teamJson
        self.isSynced = isSynced
    }
}
