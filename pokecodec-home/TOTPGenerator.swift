import SwiftUI
import Combine
import CryptoKit
import Foundation

// 抽離運算邏輯，避免在 Struct View 中直接修改
class TOTPManager: ObservableObject {
    let period: TimeInterval = 30
    
    func generateCode(secretData: Data) -> String? {
        let counter = UInt64(Date().timeIntervalSince1970 / period)
        var bigEndianCounter = counter.bigEndian
        let counterData = Data(bytes: &bigEndianCounter, count: MemoryLayout<UInt64>.size)
        
        let key = SymmetricKey(data: secretData)
        let hmac = HMAC<Insecure.SHA1>.authenticationCode(for: counterData, using: key)
        let hashData = Data(hmac)
        
        let offset = Int(hashData.last! & 0x0f)
        
        // 避免 Misaligned Load 錯誤：手動組合 Bytes
        let b0 = UInt32(hashData[offset])
        let b1 = UInt32(hashData[offset + 1])
        let b2 = UInt32(hashData[offset + 2])
        let b3 = UInt32(hashData[offset + 3])
        
        var truncatedValue = (b0 << 24) | (b1 << 16) | (b2 << 8) | b3
        truncatedValue &= 0x7fffffff
        
        let otpValue = truncatedValue % 1000000
        return String(format: "%06d", otpValue)
    }
}

struct TOTPTestView: View {
    @StateObject private var manager = TOTPManager()
    @State private var currentCode: String = "--- ---"
    @State private var timeRemaining: Int = 30
    
    let demoSecret = "BASE32SECRET".data(using: .utf8)!
    let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    
    var body: some View {
        VStack {
            Text("2FA 驗證碼").font(.headline)
            Text(currentCode).font(.largeTitle).bold().monospaced()
            Text("剩餘時間: \(timeRemaining)秒").font(.caption)
        }
        .onReceive(timer) { _ in
            let now = Date().timeIntervalSince1970
            timeRemaining = 30 - (Int(now) % 30)
            if timeRemaining == 30 || currentCode == "--- ---" {
                if let code = manager.generateCode(secretData: demoSecret) {
                    currentCode = code
                }
            }
        }
    }
}
