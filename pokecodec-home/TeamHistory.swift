import Foundation
import SwiftData

@Model
final class TeamHistory {
    var timestamp: Double
    var lockId: Int
    var teamJson: Data
    
    var device: ConnectedDevice?
    
    init(timestamp: Double, lockId: Int, teamJson: Data) {
        self.timestamp = timestamp
        self.lockId = lockId
        self.teamJson = teamJson
    }
}
