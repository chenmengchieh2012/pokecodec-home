import Foundation
import Security

class KeychainHelper {
    static let shared = KeychainHelper()
    private let serviceName = "com.pokecodec.home" // 使用 Bundle ID 或固定字串
    
    private init() {}
    
    func save(_ value: String, account: String) {
        guard let data = value.data(using: .utf8) else { return }
        
        let query = [
            kSecValueData: data,
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: serviceName,
            kSecAttrAccount: account
        ] as CFDictionary
        
        // 先嘗試刪除舊資料
        SecItemDelete(query)
        
        // 新增資料
        SecItemAdd(query, nil)
    }
    
    func read(account: String) -> String? {
        let query = [
            kSecAttrService: serviceName,
            kSecAttrAccount: account,
            kSecClass: kSecClassGenericPassword,
            kSecReturnData: true
        ] as CFDictionary
        
        var result: AnyObject?
        SecItemCopyMatching(query, &result)
        
        if let data = result as? Data {
            return String(data: data, encoding: .utf8)
        }
        return nil
    }
    
    func delete(account: String) {
        let query = [
            kSecAttrService: serviceName,
            kSecAttrAccount: account,
            kSecClass: kSecClassGenericPassword
        ] as CFDictionary
        
        SecItemDelete(query)
    }
}
