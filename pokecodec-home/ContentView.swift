import SwiftUI
import SwiftData
import Combine
import VisionKit
import CryptoKit
import WebKit

struct ContentView: View {
    @StateObject private var settings = SecureSettings()
    @StateObject private var totpManager = TOTPManager()
    @State private var selectedTab: Int = 0

    var body: some View {
        ZStack {
            Color.archiveBG.ignoresSafeArea()
            
            VStack(spacing: 0) {
                TabView(selection: $selectedTab) {
                    PartyPage(settings: settings, totpManager: totpManager)
                        .tag(0)
                    
                    PokeBoxPage(settings: settings)
                        .tag(1)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                
                // Custom Tab Bar
                HStack(spacing: 0) {
                    Button(action: { selectedTab = 0 }) {
                        VStack(spacing: 4) {
                            Image(systemName: "circle.circle")
                                .font(.system(size: 18))
                            Text("隊伍")
                                .font(.system(size: 10, weight: .bold))
                        }
                        .foregroundColor(selectedTab == 0 ? .archiveAccent : .gray)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .contentShape(Rectangle())
                    }
                    
                    Button(action: { selectedTab = 1 }) {
                        VStack(spacing: 4) {
                            Image(systemName: "archivebox")
                                .font(.system(size: 18))
                            Text("盒子")
                                .font(.system(size: 10, weight: .bold))
                        }
                        .foregroundColor(selectedTab == 1 ? .archiveAccent : .gray)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .contentShape(Rectangle())
                    }
                }
                .background(Color.archiveBG)
                .overlay(Rectangle().frame(height: 0.5).foregroundColor(.white.opacity(0.1)), alignment: .top)
            }
        }
    }
}

/// 統一的寶可夢顯示模型 (適配 SwiftData 與 API 資料)
struct PokemonDisplayModel: Identifiable {
    let id: String; let pokedexId: Int; let name: String; let nickname: String?; let level: Int; let currentHp: Int; let maxHp: Int; let isShiny: Bool; let types: [String]; let caughtBall: String
    var displayName: String { nickname ?? name }
}

extension PokemonDisplayModel {
    // 根據屬性回傳對應顏色 (Gen 5 風格)
    var typeColor: Color {
        guard let type = types.first?.lowercased() else { return .gray }
        switch type {
        case "normal": return Color(hex: "A8A77A")
        case "fire": return Color(hex: "EE8130")
        case "water": return Color(hex: "6390F0")
        case "electric": return Color(hex: "F7D02C")
        case "grass": return Color(hex: "7AC74C")
        case "ice": return Color(hex: "96D9D6")
        case "fighting": return Color(hex: "C22E28")
        case "poison": return Color(hex: "A33EA1")
        case "ground": return Color(hex: "E2BF65")
        case "flying": return Color(hex: "A98FF3")
        case "psychic": return Color(hex: "F95587")
        case "bug": return Color(hex: "A6B91A")
        case "rock": return Color(hex: "B6A136")
        case "ghost": return Color(hex: "735797")
        case "dragon": return Color(hex: "6F35FC")
        case "steel": return Color(hex: "B7B7CE")
        case "fairy": return Color(hex: "D685AD")
        default: return .gray
        }
    }
}

extension Pokemon {
    func toDisplayModel() -> PokemonDisplayModel {
        PokemonDisplayModel(id: uid, pokedexId: pokedexId, name: name, nickname: nickname, level: level, currentHp: currentHp, maxHp: maxHp, isShiny: isShiny, types: types, caughtBall: caughtBall)
    }
}

extension PokemonSyncDTO {
    func toDisplayModel() -> PokemonDisplayModel {
        PokemonDisplayModel(id: uid, pokedexId: id, name: name, nickname: nickname, level: level, currentHp: currentHp, maxHp: maxHp, isShiny: isShiny, types: types, caughtBall: caughtBall)
    }
}

// MARK: - 色彩擴充
extension Color {
    init(hex: String) {
        let scanner = Scanner(string: hex)
        var rgbValue: UInt64 = 0
        scanner.scanHexInt64(&rgbValue)
        self.init(red: Double((rgbValue & 0xFF0000) >> 16) / 255, green: Double((rgbValue & 0x00FF00) >> 8) / 255, blue: Double(rgbValue & 0x0000FF) / 255)
    }

    // 主背景：溫暖的碳黑 (不帶藍調，護眼)
    static let archiveBG = Color(hex: "1C1C1C")
    
    // 卡片背景：深泥灰色
    static let archiveCard = Color(hex: "2D2D2D")
    
    // 主強調色：羊皮紙黃 (取代原本刺眼的青色)
    static let archiveAccent = Color(hex: "EADBB2")
    
    // 次要資訊：亞麻灰
    static let archiveSecondary = Color(hex: "A89984")
    
    // 狀態顏色：低飽和度
    static let archiveGreen = Color(hex: "98971A") // 橄欖綠
    static let archiveRed = Color(hex: "CC241D")   // 鐵鏽紅
    static let archiveGold = Color(hex: "D79921")  // 舊金色 (用於 Lv. 和 閃光)
}
