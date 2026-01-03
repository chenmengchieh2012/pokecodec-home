import Foundation
import SwiftData
import CryptoKit

enum SyncType: String, Codable {
    case party
    case box
    case bindSetup
}

struct SyncPayload: Codable {
    let secret: String
    let type: SyncType?
    let transferPokemons: [PokemonSyncDTO]?
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
    static func processPayload(payload: SyncPayload, name: String, context: ModelContext, settings: SecureSettings) -> ConnectedDevice? {
        if payload.type == .party && !(payload.transferPokemons?.isEmpty ?? true) && payload.lockId >= 0 {
            saveParty(payload: payload, context: context, githubToken: settings.githubToken, gistId: settings.gistId)
        } else if payload.type == .box {
            saveBoxPokemon(payload: payload, context: context)
        } else if payload.type == .bindSetup {
            saveDevice(payload: payload, name: name, context: context)
        }
        
        let descriptor = FetchDescriptor<ConnectedDevice>(predicate: #Predicate<ConnectedDevice> { $0.secret == payload.secret })
        return try? context.fetch(descriptor).first
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
    static func saveParty(payload: SyncPayload, context: ModelContext, githubToken: String, gistId: String, completion: ((Bool) -> Void)? = nil) {
        guard let dtos = payload.transferPokemons else {
            print("⚠️ Payload 中沒有隊伍資料，跳過儲存隊伍")
            completion?(false)
            return
        }
        print("📦 開始儲存 \(dtos.count) 隻寶可夢數據")

        do {
            // 1. 清空現有寶可夢
            try context.delete(model: Pokemon.self)
            
            // 2. 插入新數據
            for (index, dto) in dtos.enumerated() {
                print("🆕 插入新成員: \(dto.name)")
                let new = Pokemon(
                    uid: dto.uid,
                    slotIndex: index,
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
                
                let history = TeamHistory(timestamp: timestamp, lockId: payload.lockId, teamJson: teamData, isSynced: false)
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
                            deleteFromGist(filename: filename, token: githubToken, gistId: gistId) { result in
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
                    transferPokemons: payload.transferPokemons,
                    lockId: payload.lockId,
                    timestamp: timestamp
                )
                
                if let compressed = try? JSONEncoder().encode(exportPayload).gzipped() {
                    let content = "GZIP:" + compressed.base64EncodedString()
                    let hash = getTimeHash(timestamp)
                    let filename = "pokecodec-party-\(hash).txt"
                    
                    uploadToGist(content: content, filename: filename, token: githubToken, gistId: gistId) { result in
                        DispatchQueue.main.async {
                            switch result {
                            case .success(let url):
                                print("✅ Gist uploaded/updated: \(url)")
                                history.isSynced = true
                                try? context.save()
                                completion?(true)
                            case .failure(let error):
                                print("❌ Gist upload failed: \(error)")
                                completion?(false)
                            }
                        }
                    }
                } else {
                    completion?(false)
                }
            } else {
                // 如果沒有要上傳 (例如 lockId < 0)，視為成功 (本地儲存成功)
                completion?(true)
            }
            
            // 修正點 2: 手動提交變更
            try context.save()
            print("✅ SwiftData 儲存成功")
            
        } catch {
            print("❌ 同步過程出錯: \(error)")
            completion?(false)
        }
    }

    @MainActor
    static func saveBoxPokemon(payload: SyncPayload, context: ModelContext) {
        guard let dtos = payload.transferPokemons else {
            print("⚠️ Payload 中沒有盒子資料，跳過儲存盒子")
            return
        }
        print("📦 開始儲存 \(dtos.count) 隻盒子寶可夢數據")

        do {
            // 1. 檢查是否有相同uid的寶可夢
            let existingPokemonsDescriptor = FetchDescriptor<PokeBox>()
            let existingPokemons = try context.fetch(existingPokemonsDescriptor)
            var existingDict = [String: PokeBox]()
            for pokemon in existingPokemons {
                existingDict[pokemon.uid] = pokemon
            }
            // 2. 更新或插入新數據
            for dto in dtos {
                if let existing = existingDict[dto.uid] {
                    print("🔄 更新盒子成員: \(dto.name)")
                    existing.update(from: dto)
                } else {
                    print("🆕 插入新盒子成員: \(dto.name)")
                    let new = PokeBox(
                        uid: dto.uid,
                        pokedexId: dto.id,
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
            }
            
            try context.save()
            print("✅ 盒子數據儲存成功")
            
        } catch {
            print("❌ 儲存盒子數據失敗: \(error)")
        }
    }
    
    static func uploadToGist(content: String, filename: String, token: String, gistId: String, completion: @escaping (Result<URL, Error>) -> Void) {
        let url: URL
        let method: String
        
        if !gistId.isEmpty {
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
                    // 注意：這裡無法直接清除 Keychain，因為 SyncService 是靜態的且不依賴 KeychainHelper
                    // 我們只能嘗試用空 ID 重新上傳 (POST)
                    uploadToGist(content: content, filename: filename, token: token, gistId: "", completion: completion)
                    return
                }
                
                if !(200...299).contains(httpResponse.statusCode) {
                    let msg = String(data: data ?? Data(), encoding: .utf8) ?? "Unknown error"
                    completion(.failure(NSError(domain: "GistError", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "GitHub API Error: \(msg)"])))
                    return
                }
            }
            
            if let data = data,
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let htmlUrl = json["html_url"] as? String,
               let newGistId = json["id"] as? String,
               let url = URL(string: htmlUrl) {
                
                // 如果是新建立的 Gist，需要通知外部更新 ID
                if method == "POST" {
                    DispatchQueue.main.async {
                        KeychainHelper.shared.save(newGistId, account: "gistId")
                    }
                }
                
                completion(.success(url))
            } else {
                completion(.failure(NSError(domain: "GistError", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid response"])))
            }
        }
        .resume()
    }
    
    static func deleteFromGist(filename: String, token: String, gistId: String, completion: @escaping (Result<Void, Error>) -> Void) {
        guard !gistId.isEmpty else {
            completion(.failure(NSError(domain: "GistError", code: -1, userInfo: [NSLocalizedDescriptionKey: "No Gist ID"])))
            return
        }
        
        let url = URL(string: "https://api.github.com/gists/\(gistId)")!
        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        request.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.addValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.addValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        
        // 刪除檔案的方式是將內容設為 null
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
            
            completion(.success(()))
        }
        .resume()
    }
}
