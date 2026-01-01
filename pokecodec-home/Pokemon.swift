import Foundation
import SwiftData
import SwiftUI

// MARK: - Supporting Structures

struct PokemonStats: Codable {
    var hp: Int
    var attack: Int
    var defense: Int
    var specialAttack: Int
    var specialDefense: Int
    var speed: Int
    
    static let zero = PokemonStats(hp: 0, attack: 0, defense: 0, specialAttack: 0, specialDefense: 0, speed: 0)
}

struct PokemonMove: Codable, Identifiable {
    var id: Int?
    var name: String
    var type: String?
    var power: Int?
    var accuracy: Int?
    var pp: Int
    var priority: Int?
    var maxPP: Int
    var effect: String?
    var target: String?
}

struct CodingStats: Codable {
    var caughtRepo: String
    var favoriteLanguage: String
    var linesOfCode: Int
    var bugsFixed: Int
    var commits: Int
    var coffeeConsumed: Int
    
    static let zero = CodingStats(caughtRepo: "Unknown", favoriteLanguage: "Swift", linesOfCode: 0, bugsFixed: 0, commits: 0, coffeeConsumed: 0)
}

@Model
final class Pokemon {
    // 基礎資訊 (對齊 PokemonDao)
    @Attribute(.unique) var uid: String
    var pokedexId: Int
    var name: String
    var nickname: String?
    
    // 會變動的狀態
    var level: Int
    var currentHp: Int
    var maxHp: Int
    var ailment: String? // healthy, burn, etc.
    
    // 數值
    var baseStats: PokemonStats
    var iv: PokemonStats
    var ev: PokemonStats
    
    // 詳細資訊
    var types: [String]
    var gender: String
    var nature: String
    var ability: String
    var isHiddenAbility: Bool
    var isLegendary: Bool
    var isMythical: Bool
    var height: Double
    var weight: Double
    var baseExp: Int
    var currentExp: Int
    var toNextLevelExp: Int
    var isShiny: Bool
    
    // 捕獲資訊
    var originalTrainer: String
    var caughtDate: Double
    var caughtBall: String
    var heldItem: String?
    
    // 技能與編碼數據
    var pokemonMoves: [PokemonMove]
    var codingStats: CodingStats?
    
    // UI 輔助
    var colorHex: String

    init(
        uid: String,
        id: Int,
        name: String,
        nickname: String? = nil,
        level: Int,
        currentHp: Int,
        maxHp: Int,
        ailment: String? = "healthy",
        stats: PokemonStats = .zero,
        baseStats: PokemonStats = .zero,
        iv: PokemonStats = .zero,
        ev: PokemonStats = .zero,
        types: [String] = ["normal"],
        gender: String = "♂",
        nature: String = "Hardy",
        ability: String = "Run Away",
        isHiddenAbility: Bool = false,
        isLegendary: Bool = false,
        isMythical: Bool = false,
        height: Double = 0.0,
        weight: Double = 0.0,
        baseExp: Int = 0,
        currentExp: Int = 0,
        toNextLevelExp: Int = 0,
        isShiny: Bool = false,
        originalTrainer: String = "Ash",
        caughtDate: Double = Date().timeIntervalSince1970,
        caughtBall: String = "poke-ball",
        heldItem: String? = nil,
        pokemonMoves: [PokemonMove] = [],
        codingStats: CodingStats? = nil,
        colorHex: String = "3498db"
    ) {
        self.uid = uid
        self.pokedexId = id
        self.name = name
        self.nickname = nickname
        self.level = level
        self.currentHp = currentHp
        self.maxHp = maxHp
        self.ailment = ailment
        self.baseStats = baseStats
        self.iv = iv
        self.ev = ev
        self.types = types
        self.gender = gender
        self.nature = nature
        self.ability = ability
        self.isHiddenAbility = isHiddenAbility
        self.isLegendary = isLegendary
        self.isMythical = isMythical
        self.height = height
        self.weight = weight
        self.baseExp = baseExp
        self.currentExp = currentExp
        self.toNextLevelExp = toNextLevelExp
        self.isShiny = isShiny
        self.originalTrainer = originalTrainer
        self.caughtDate = caughtDate
        self.caughtBall = caughtBall
        self.heldItem = heldItem
        self.pokemonMoves = pokemonMoves
        self.codingStats = codingStats
        self.colorHex = colorHex
    }
    
    // 相容性計算屬性 (為了不破壞現有 UI 太多)
    var linesOfCode: Int {
        get { codingStats?.linesOfCode ?? 0 }
        set {
            if codingStats == nil { codingStats = .zero }
            codingStats?.linesOfCode = newValue
        }
    }
    
    var bugsFixed: Int {
        get { codingStats?.bugsFixed ?? 0 }
        set {
            if codingStats == nil { codingStats = .zero }
            codingStats?.bugsFixed = newValue
        }
    }
    
    var commits: Int {
        get { codingStats?.commits ?? 0 }
        set {
            if codingStats == nil { codingStats = .zero }
            codingStats?.commits = newValue
        }
    }
    
    // 提供 UI 使用的計算屬性
    var color: Color {
        switch colorHex.lowercased() {
        case "ffd700": return .yellow
        case "ff4500": return .red
        case "2ecc71": return .green
        default: return .blue
        }
    }
    
    func toDTO() -> PokemonSyncDTO {
        return PokemonSyncDTO(
            uid: uid,
            id: pokedexId,
            name: name,
            nickname: nickname,
            level: level,
            currentHp: currentHp,
            maxHp: maxHp,
            ailment: ailment,
            baseStats: baseStats,
            iv: iv,
            ev: ev,
            types: types,
            gender: gender,
            nature: nature,
            ability: ability,
            isHiddenAbility: isHiddenAbility,
            isLegendary: isLegendary,
            isMythical: isMythical,
            height: height,
            weight: weight,
            baseExp: baseExp,
            currentExp: currentExp,
            toNextLevelExp: toNextLevelExp,
            isShiny: isShiny,
            originalTrainer: originalTrainer,
            caughtDate: caughtDate,
            caughtBall: caughtBall,
            heldItem: heldItem,
            pokemonMoves: pokemonMoves,
            codingStats: codingStats
        )
    }
}
