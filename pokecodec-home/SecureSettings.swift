import Foundation
import Combine

class SecureSettings: ObservableObject {
    @Published var githubToken: String {
        didSet {
            KeychainHelper.shared.save(githubToken, account: "githubToken")
        }
    }
    
    @Published var gistId: String {
        didSet {
            KeychainHelper.shared.save(gistId, account: "gistId")
        }
    }
    
    init() {
        // Migration from UserDefaults to Keychain
        if let oldToken = UserDefaults.standard.string(forKey: "githubToken"), !oldToken.isEmpty {
            KeychainHelper.shared.save(oldToken, account: "githubToken")
            UserDefaults.standard.removeObject(forKey: "githubToken")
        }
        if let oldGistId = UserDefaults.standard.string(forKey: "PokecodecGistId"), !oldGistId.isEmpty {
            KeychainHelper.shared.save(oldGistId, account: "gistId")
            UserDefaults.standard.removeObject(forKey: "PokecodecGistId")
        }
        
        self.githubToken = KeychainHelper.shared.read(account: "githubToken") ?? ""
        self.gistId = KeychainHelper.shared.read(account: "gistId") ?? ""
    }
    
    func reset() {
        githubToken = ""
        gistId = ""
        KeychainHelper.shared.delete(account: "githubToken")
        KeychainHelper.shared.delete(account: "gistId")
    }
}
