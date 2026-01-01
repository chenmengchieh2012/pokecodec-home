import Foundation

extension Data {
    /// 簡單的 Base32 解碼器
    static func fromBase32(_ base32String: String) -> Data? {
        let alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567"
        let base32String = base32String.uppercased().replacingOccurrences(of: " ", with: "")
        
        var data = Data()
        var buffer: UInt32 = 0
        var bitsLeft: Int = 0
        
        for char in base32String {
            guard let val = alphabet.firstIndex(of: char)?.utf16Offset(in: alphabet) else {
                continue // 跳過無效字元
            }
            
            buffer = (buffer << 5) | UInt32(val)
            bitsLeft += 5
            
            if bitsLeft >= 8 {
                data.append(UInt8((buffer >> (bitsLeft - 8)) & 0xFF))
                bitsLeft -= 8
            }
        }
        return data.isEmpty ? nil : data
    }
}
