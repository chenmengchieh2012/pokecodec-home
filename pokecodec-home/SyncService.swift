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

struct SyncPayload: Codable {
    let secret: String
    let party: [PokemonSyncDTO]?
    let lockId: Int
    let timestamp: Double?
}

struct SyncService {
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
            
            // 儲存歷史紀錄 (只有當有隊伍資料且 lockId 非負值時)
            if let party = payload.party, 
               payload.lockId >= 0,
               let timestamp = payload.timestamp,
               let teamData = try? JSONEncoder().encode(party) {
                
                // 檢查是否已經存在相同的 lockId (避免重複儲存)
                if !device.history.contains(where: { $0.lockId == payload.lockId }) {
                    let history = TeamHistory(timestamp: timestamp, lockId: payload.lockId, teamJson: teamData)
                    device.history.append(history)
                    
                    // 排序並保留最新的 5 筆
                    device.history.sort { $0.timestamp > $1.timestamp }
                    if device.history.count > 5 {
                        let toDelete = device.history.suffix(from: 5)
                        for item in toDelete {
                            context.delete(item)
                        }
                        device.history.removeSubrange(5...)
                    }
                }
            }
            
            try context.save()
            print("✅ 裝置資訊與歷史紀錄已儲存: \(name)")
        } catch {
            print("❌ 儲存裝置資訊失敗: \(error)")
        }
    }

    @MainActor // 確保在主執行緒執行，UI 才能即時反應
    static func saveParty(payload: SyncPayload, context: ModelContext) {
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
            
            // 修正點 2: 手動提交變更
            try context.save()
            print("✅ SwiftData 儲存成功")
            
        } catch {
            print("❌ 同步過程出錯: \(error)")
        }
    }
}
