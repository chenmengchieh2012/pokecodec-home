import Foundation
import SwiftData

@Model
final class PokeBox {
    @Attribute(.unique) var uid: String
    var pokedexId: Int
    var name: String
    var nickname: String?
    var level: Int
    var currentHp: Int
    var maxHp: Int
    var ailment: String?
    
    var baseStats: PokemonStats
    var iv: PokemonStats
    var ev: PokemonStats
    
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
    
    var originalTrainer: String
    var caughtDate: Double
    var caughtBall: String
    var heldItem: String?
    
    var pokemonMoves: [PokemonMove]
    var codingStats: CodingStats?
    var isSynced: Bool = false
    
    init(
        uid: String,
        pokedexId: Int,
        name: String,
        nickname: String? = nil,
        level: Int,
        currentHp: Int,
        maxHp: Int,
        ailment: String? = "healthy",
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
        codingStats: CodingStats? = nil
    ) {
        self.uid = uid
        self.pokedexId = pokedexId
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
    }
    
    func update(from dto: PokemonSyncDTO) {
        self.pokedexId = dto.id
        self.name = dto.name
        self.nickname = dto.nickname
        self.level = dto.level
        self.currentHp = dto.currentHp
        self.maxHp = dto.maxHp
        self.ailment = dto.ailment
        self.baseStats = dto.baseStats
        self.iv = dto.iv
        self.ev = dto.ev
        self.types = dto.types
        self.gender = dto.gender
        self.nature = dto.nature
        self.ability = dto.ability
        self.isHiddenAbility = dto.isHiddenAbility
        self.isLegendary = dto.isLegendary
        self.isMythical = dto.isMythical
        self.height = dto.height
        self.weight = dto.weight
        self.baseExp = dto.baseExp
        self.currentExp = dto.currentExp
        self.toNextLevelExp = dto.toNextLevelExp
        self.isShiny = dto.isShiny
        self.originalTrainer = dto.originalTrainer
        self.caughtDate = dto.caughtDate
        self.caughtBall = dto.caughtBall
        self.heldItem = dto.heldItem
        self.pokemonMoves = dto.pokemonMoves
        self.codingStats = dto.codingStats
    }
}
