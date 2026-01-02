import Foundation
import SwiftData
import CryptoKit

// 對齊 pokemon.ts 的 JSON 結構
struct PokemonSyncDTO: Codable {
    let uid: String
    let id: Int
    let name: String
    let nickname: String?
    let level: Int
    let currentHp: Int
    let maxHp: Int
    let ailment: String?
    
    let baseStats: PokemonStats
    let iv: PokemonStats
    let ev: PokemonStats
    
    let types: [String]
    let gender: String
    let nature: String
    let ability: String
    let isHiddenAbility: Bool
    let isLegendary: Bool
    let isMythical: Bool
    let height: Double
    let weight: Double
    let baseExp: Int
    let currentExp: Int
    let toNextLevelExp: Int
    let isShiny: Bool
    
    let originalTrainer: String
    let caughtDate: Double
    let caughtBall: String
    let heldItem: String?
    
    let pokemonMoves: [PokemonMove]
    let codingStats: CodingStats?
}

enum SyncType: String, Codable {
    case party
    case achievement
    case bindSetup
}

struct SyncPayload: Codable {
    let secret: String
    let type: SyncType?
    let party: [PokemonSyncDTO]?
    let lockId: Int
    let timestamp: Double?
}

struct SyncService {
    static func getTimeHash(_ timestamp: Double) -> String {
        let data = Data(String(timestamp).utf8)
        let hash = SHA256.hash(data: data)
        return String(hash.compactMap { String(format: "%02x", $0) }.joined().prefix(6))
    }

    @MainActor
    static func decodePayload(base64: String) -> SyncPayload? {
        // 1. 清理字串
        var processingBase64 = base64
        if processingBase64.hasPrefix("GZIP:") {
            processingBase64 = String(processingBase64.dropFirst(5))
        }
        let cleanedBase64 = processingBase64.cleanBase64()
        
        // 2. Base64 轉 Data 檢查
        guard let compressedData = Data(base64Encoded: cleanedBase64) else {
            print("❌ 錯誤：Base64 格式無效")
            return nil
        }
        
        // 3. 解壓縮檢查
        guard let jsonData = compressedData.gunzipped() else {
            print("❌ 錯誤：Gzip 解壓縮失敗")
            return nil
        }
        
        do {
            let payload = try JSONDecoder().decode(SyncPayload.self, from: jsonData)
            return payload
        } catch {
            print("❌ JSON 解析失敗: \(error)")
            return nil
        }
    }
    
    @MainActor
    static func saveDevice(payload: SyncPayload, name: String, context: ModelContext) {
        let secret = payload.secret
        let descriptor = FetchDescriptor<ConnectedDevice>(
            predicate: #Predicate<ConnectedDevice> { $0.secret == secret }
        )
        
        do {
            let device: ConnectedDevice
            if let existing = try context.fetch(descriptor).first {
                // 更新版本號與時間戳 (如果有，且 lockId 非負值)
                if payload.lockId >= 0 {
                    existing.lockId = payload.lockId
                }
                if let newTimestamp = payload.timestamp {
                    existing.lastSyncTimestamp = newTimestamp
                }
                device = existing
            } else {
                let newDevice = ConnectedDevice(
                    secret: payload.secret,
                    name: name,
                    lockId: payload.lockId < 0 ? 0 : payload.lockId,
                    timestamp: payload.timestamp ?? Date().timeIntervalSince1970
                )
                context.insert(newDevice)
                device = newDevice
            }
            
            try context.save()
            print("✅ 裝置資訊已儲存: \(name)")
        } catch {
            print("❌ 儲存裝置資訊失敗: \(error)")
        }
    }

    @MainActor // 確保在主執行緒執行，UI 才能即時反應
    static func saveParty(payload: SyncPayload, context: ModelContext, githubToken: String, gistIdKey: String = "PokecodecGistId") {
        guard let dtos = payload.party else {
            print("⚠️ Payload 中沒有隊伍資料，跳過儲存隊伍")
            return
        }
        print("📦 開始儲存 \(dtos.count) 隻寶可夢數據")

        do {
            // 1. 清空現有寶可夢
            try context.delete(model: Pokemon.self)
            
            // 2. 插入新數據
            for dto in dtos {
                print("🆕 插入新成員: \(dto.name)")
                let new = Pokemon(
                    uid: dto.uid,
                    id: dto.id,
                    name: dto.name,
                    nickname: dto.nickname,
                    level: dto.level,
                    currentHp: dto.currentHp,
                    maxHp: dto.maxHp,
                    ailment: dto.ailment,
                    baseStats: dto.baseStats,
                    iv: dto.iv,
                    ev: dto.ev,
                    types: dto.types,
                    gender: dto.gender,
                    nature: dto.nature,
                    ability: dto.ability,
                    isHiddenAbility: dto.isHiddenAbility,
                    isLegendary: dto.isLegendary,
                    isMythical: dto.isMythical,
                    height: dto.height,
                    weight: dto.weight,
                    baseExp: dto.baseExp,
                    currentExp: dto.currentExp,
                    toNextLevelExp: dto.toNextLevelExp,
                    isShiny: dto.isShiny,
                    originalTrainer: dto.originalTrainer,
                    caughtDate: dto.caughtDate,
                    caughtBall: dto.caughtBall,
                    heldItem: dto.heldItem,
                    pokemonMoves: dto.pokemonMoves,
                    codingStats: dto.codingStats
                )
                context.insert(new)
            }
            
            // 3. 儲存歷史紀錄 (全域最多 5 筆)
            if payload.lockId >= 0,
               let timestamp = payload.timestamp,
               let teamData = try? JSONEncoder().encode(dtos) {
                
                let history = TeamHistory(timestamp: timestamp, lockId: payload.lockId, teamJson: teamData)
                context.insert(history)
                
                // 檢查數量並刪除舊的
                let allHistoryDescriptor = FetchDescriptor<TeamHistory>(sortBy: [SortDescriptor(\.timestamp, order: .reverse)])
                if let allHistories = try? context.fetch(allHistoryDescriptor), allHistories.count > 5 {
                    let toDelete = allHistories.suffix(from: 5)
                    for item in toDelete {
                        context.delete(item)
                            
                            // 同步刪除 Gist 上的檔案
                            let hash = getTimeHash(item.timestamp)
                            let filename = "pokecodec-party-\(hash).txt"
                            deleteFromGist(filename: filename, token: githubToken, gistIdKey: gistIdKey) { result in
                                if case .failure(let error) = result {
                                    print("❌ Failed to delete file from Gist: \(error)")
                                } else {
                                    print("🗑️ Deleted file from Gist: \(filename)")
                                }
                            }
                        }
                    }
                print("✅ 已新增歷史紀錄 (v\(payload.lockId))")
                
                // 上傳至 GitHub Gist (壓縮格式)
                let exportPayload = SyncPayload(
                    secret: "", 
                    type: payload.type,
                    party: payload.party,
                    lockId: payload.lockId,
                    timestamp: timestamp
                )
                
                if let compressed = try? JSONEncoder().encode(exportPayload).gzipped() {
                    let content = "GZIP:" + compressed.base64EncodedString()
                    let hash = getTimeHash(timestamp)
                    let filename = "pokecodec-party-\(hash).txt"
                    
                    uploadToGist(content: content, filename: filename, token: githubToken, gistIdKey: gistIdKey) { result in
                        switch result {
                        case .success(let url):
                            print("✅ Gist uploaded/updated: \(url)")
                        case .failure(let error):
                            print("❌ Gist upload failed: \(error)")
                        }
                    }
                }
            }
            
            // 修正點 2: 手動提交變更
            try context.save()
            print("✅ SwiftData 儲存成功")
            
        } catch {
            print("❌ 同步過程出錯: \(error)")
        }
    }
    
    static func uploadToGist(content: String, filename: String, token: String, gistIdKey: String, completion: @escaping (Result<URL, Error>) -> Void) {
        let storedGistId = UserDefaults.standard.string(forKey: gistIdKey)
        
        let url: URL
        let method: String
        
        if let gistId = storedGistId {
            url = URL(string: "https://api.github.com/gists/\(gistId)")!
            method = "PATCH"
        } else {
            url = URL(string: "https://api.github.com/gists")!
            method = "POST"
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.addValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.addValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        
        let body: [String: Any] = [
            "description": "Uploaded from PokéCodec",
            "public": false,
            "files": [
                filename: [
                    "content": content
                ]
            ]
        ]
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        } catch {
            completion(.failure(error))
            return
        }
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                completion(.failure(error))
                return
            }
            
            if let httpResponse = response as? HTTPURLResponse {
                if httpResponse.statusCode == 404 && method == "PATCH" {
                    // Gist ID 失效，清除並重試 (遞迴呼叫會變成 POST)
                    UserDefaults.standard.removeObject(forKey: gistIdKey)
                    uploadToGist(content: content, filename: filename, token: token, gistIdKey: gistIdKey, completion: completion)
                    return
                }
                
                if !(200...299).contains(httpResponse.statusCode) {
                    let msg = String(data: data ?? Data(), encoding: .utf8) ?? "Unknown error"
                    completion(.failure(NSError(domain: "GistError", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "GitHub API Error: \(msg)"])))
                    return
                }
            }
            
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let htmlUrlString = json["html_url"] as? String,
                  let htmlUrl = URL(string: htmlUrlString),
                  let id = json["id"] as? String else {
                completion(.failure(NSError(domain: "GistError", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to parse response"])))
                return
            }
            
            // 儲存 Gist ID 以供下次更新使用
            UserDefaults.standard.set(id, forKey: gistIdKey)
            
            completion(.success(htmlUrl))
        }.resume()
    }
    
    static func deleteFromGist(filename: String, token: String, gistIdKey: String, completion: @escaping (Result<Bool, Error>) -> Void) {
        guard let gistId = UserDefaults.standard.string(forKey: gistIdKey) else {
            completion(.failure(NSError(domain: "GistError", code: -1, userInfo: [NSLocalizedDescriptionKey: "No Gist ID found"])))
            return
        }
        
        let url = URL(string: "https://api.github.com/gists/\(gistId)")!
        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        request.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.addValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.addValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        
        // To delete a file, set it to null
        let body: [String: Any] = [
            "files": [
                filename: NSNull()
            ]
        ]
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        } catch {
            completion(.failure(error))
            return
        }
        
        URLSession.shared.dataTask(with: request) { _, response, error in
            if let error = error {
                completion(.failure(error))
                return
            }
            
            if let httpResponse = response as? HTTPURLResponse, !(200...299).contains(httpResponse.statusCode) {
                completion(.failure(NSError(domain: "GistError", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "GitHub API Error"])))
                return
            }
            
            completion(.success(true))
        }.resume()
    }
}
