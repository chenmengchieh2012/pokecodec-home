import SwiftUI
import SwiftData
import Combine
import VisionKit
import CryptoKit
import WebKit

struct ContentView: View {
    @Query(sort: \Pokemon.pokedexId) var team: [Pokemon]
    @Query var devices: [ConnectedDevice]
    @Query(sort: \TeamHistory.timestamp, order: .reverse) var histories: [TeamHistory]
    @Environment(\.modelContext) private var modelContext

    // --- AppStorage 設定 ---
    @AppStorage("githubToken") private var githubToken = ""
    @AppStorage("PokecodecGistId") private var gistId = "YOUR_DEFAULT_GIST_ID"
    
    @State private var isShowingScanner = false
    @State private var selectedHistory: TeamHistory?
    @State private var showingSettings = false
    @StateObject private var totpManager = TOTPManager()
    @State private var selectedDevice: ConnectedDevice?
    @State private var totpCode: String = "--- ---"
    @State private var timeRemaining = 30
    
    // 導航與交互
    @State private var showingExportAlert = false
    @State private var exportedString = ""
    @State private var exportedLockId = 0
    
    // 處理掃描與設備綁定
    @State private var pendingPayload: SyncPayload?
    @State private var showingDeviceNameInput = false
    @State private var newDeviceName = ""
    
    let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var displayedTeam: [PokemonDisplayModel] {
        if let history = selectedHistory,
           let decoded = try? JSONDecoder().decode([PokemonSyncDTO].self, from: history.teamJson) {
            return decoded.map { $0.toDisplayModel() }
        }
        return team.map { $0.toDisplayModel() }
    }

    var body: some View {
        ZStack {
            // 背景：深紫色系 LCD 質感
            Color.archiveBG.ignoresSafeArea()
            
            // 掃描線紋理
            ScanlineOverlay().opacity(0.1).ignoresSafeArea()
            
            VStack(spacing: 0) {
                // --- Header: 標題 ---
                HStack {
                    PixelIconButton(icon: "gearshape.fill") { showingSettings = true }
                    Spacer()
                    Text("PokéCodec")
                        .font(.system(size: 24, weight: .black, design: .monospaced))
                        .foregroundColor(.white)
                    Spacer()
                    HStack(spacing: 12) {
                        PixelIconButton(icon: "qrcode.viewfinder") { isShowingScanner = true }
                        PixelIconButton(icon: "square.and.arrow.up") { exportData() }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 15)
                .padding(.bottom, 25)
                
                ScrollView {
                    VStack(spacing: 30) {
                        // --- 隊伍狀態：2x3 網格 ---
                        VStack(alignment: .leading, spacing: 16) {
                            // Section Header with Version Picker
                            HStack {
                                Text("▶ PARTY STATUS")
                                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                                    .foregroundColor(.archiveAccent)
                                
                                Spacer()
                                
                                // Hash Display (Original Hash)
                                Text(selectedHistory != nil ? "#\(SyncService.getTimeHash(selectedHistory!.timestamp))" : (histories.first != nil ? "#\(SyncService.getTimeHash(histories.first!.timestamp))" : "---"))
                                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                                    .foregroundColor(.gray)
                                    .padding(.trailing, 8)

                                // Version Picker (Menu)
                                Menu {
                                    Button("最新") { selectedHistory = nil }
                                    ForEach(histories) { history in
                                        Button("v\(history.lockId)") { selectedHistory = history }
                                    }
                                } label: {
                                    HStack(spacing: 4) {
                                        Text("版本")
                                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                                        Image(systemName: "chevron.down")
                                            .font(.system(size: 8))
                                    }
                                    .foregroundColor(.archiveAccent)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.black.opacity(0.4))
                                    .overlay(PixelBorder(color: Color.archiveAccent.opacity(0.5)))
                                }
                            }
                            .padding(.horizontal, 24)
                            
                            LazyVGrid(columns: [
                                GridItem(.flexible(), spacing: 10),
                                GridItem(.flexible(), spacing: 10),
                                GridItem(.flexible(), spacing: 10)
                            ], spacing: 10) {
                                ForEach(0..<6, id: \.self) { index in
                                    if index < displayedTeam.count {
                                        PixelPokemonGridCard(pokemon: displayedTeam[index])
                                    } else {
                                        PixelEmptySlot()
                                    }
                                }
                            }
                            .padding(.horizontal, 20)
                        }
                        
                        // --- 連結終端 ---
                        if !devices.isEmpty {
                            VStack(alignment: .leading, spacing: 16) {
                                SectionHeader(title: "LINKED TERMINALS", count: nil)
                                
                                ForEach(devices) { device in
                                    PixelTerminalRow(
                                        device: device,
                                        timeRemaining: timeRemaining,
                                        totpManager: totpManager
                                    )
                                    .onTapGesture {
                                        selectedDevice = device
                                        updateTOTP()
                                    }
                                    .padding(.horizontal, 20)
                                }
                            }
                        }
                    }
                    .padding(.bottom, 40)
                }
            }
            if showingExportAlert {
                ExportPopup(isShowing: $showingExportAlert, dataString: exportedString)
                    .zIndex(100)
            }
        }
        .onReceive(timer) { _ in updateTOTP() }
        .sheet(isPresented: $isShowingScanner) { 
            ScannerSheet(isShowing: $isShowingScanner) { handleQRCodeScanned($0) } 
        }
        .sheet(isPresented: $showingSettings) { 
            SettingsView(githubToken: $githubToken, gistId: $gistId, onReset: resetAll) 
        }
        .alert("設備命名", isPresented: $showingDeviceNameInput) {
            TextField("輸入名稱", text: $newDeviceName)
            Button("儲存") { 
                guard let payload = pendingPayload else { return }
                savePayloadByType(payload: payload, name: newDeviceName)
            }   
        }
    }

    // MARK: - Logic (Restored)
    
    private func updateTOTP() {
        let now = Date().timeIntervalSince1970
        timeRemaining = 30 - (Int(now) % 30)
        
        // 這裡不再只更新單一 totpCode，而是讓 View 自行計算
        // 但為了相容舊邏輯，我們還是保留這個方法來觸發 UI 更新
    }

    private func exportData() {
        let dtos = team.map { pokemon in
            PokemonSyncDTO(
                uid: pokemon.uid,
                id: pokemon.pokedexId,
                name: pokemon.name,
                nickname: pokemon.nickname,
                level: pokemon.level,
                currentHp: pokemon.currentHp,
                maxHp: pokemon.maxHp,
                ailment: pokemon.ailment,
                baseStats: pokemon.baseStats,
                iv: pokemon.iv,
                ev: pokemon.ev,
                types: pokemon.types,
                gender: pokemon.gender,
                nature: pokemon.nature,
                ability: pokemon.ability,
                isHiddenAbility: pokemon.isHiddenAbility,
                isLegendary: pokemon.isLegendary,
                isMythical: pokemon.isMythical,
                height: pokemon.height,
                weight: pokemon.weight,
                baseExp: pokemon.baseExp,
                currentExp: pokemon.currentExp,
                toNextLevelExp: pokemon.toNextLevelExp,
                isShiny: pokemon.isShiny,
                originalTrainer: pokemon.originalTrainer,
                caughtDate: pokemon.caughtDate,
                caughtBall: pokemon.caughtBall,
                heldItem: pokemon.heldItem,
                pokemonMoves: pokemon.pokemonMoves,
                codingStats: pokemon.codingStats
            )
        }
        
        if let data = try? JSONEncoder().encode(dtos) {
            exportedString = data.base64EncodedString()
            exportedLockId = Int(Date().timeIntervalSince1970)
            showingExportAlert = true
        }
    }

    private func handleQRCodeScanned(_ code: String) {
        guard let data = code.data(using: .utf8),
              let payload = try? JSONDecoder().decode(SyncPayload.self, from: data) else {
            return
        }
        pendingPayload = payload
        showingDeviceNameInput = true
    }

    private func savePayloadByType(payload: SyncPayload, name: String) {
        if payload.type == .bindSetup {
            let device = ConnectedDevice(
                secret: payload.secret,
                name: name,
                lockId: payload.lockId,
                timestamp: payload.timestamp ?? Date().timeIntervalSince1970
            )
            modelContext.insert(device)
            selectedDevice = device
        }
        pendingPayload = nil
        showingDeviceNameInput = false
    }

    private func resetAll() {
        try? modelContext.delete(model: Pokemon.self)
        try? modelContext.delete(model: ConnectedDevice.self)
        try? modelContext.delete(model: TeamHistory.self)
        gistId = ""
        githubToken = ""
    }
}

// MARK: - 核心像素 UI 元件
struct GifImage: UIViewRepresentable {
    let url: URL
    
    func makeUIView(context: Context) -> WKWebView {
        let webView = WKWebView()
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.isScrollEnabled = false
        webView.isUserInteractionEnabled = false
        return webView
    }
    
    func updateUIView(_ uiView: WKWebView, context: Context) {
        // 使用更嚴謹的 HTML 封裝，並指定 BaseURL 確保圖片能顯示
        let html = """
        <html>
        <head>
            <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
            <style>
                body { 
                    background-color: transparent; margin: 0; padding: 0; 
                    display: flex; justify-content: center; align-items: center; 
                    height: 100vh; overflow: hidden; 
                }
                img { 
                    max-width: 100%; max-height: 100%; 
                    object-fit: contain; 
                    image-rendering: pixelated; /* 保持像素感 */
                }
            </style>
        </head>
        <body>
            <img src="\(url.absoluteString)" />
        </body>
        </html>
        """
        uiView.loadHTMLString(html, baseURL: url.deletingLastPathComponent())
    }
}

/// 像素邊框生成器：模擬 RPG 遊戲中的雙重邊框
struct PixelBorder: View {
    var color: Color
    var body: some View {
        ZStack {
            Rectangle().stroke(color, lineWidth: 2)
            Rectangle().stroke(Color.black.opacity(0.3), lineWidth: 4).padding(-2)
        }
    }
}

struct SectionHeader: View {
    let title: String
    let count: String?
    var body: some View {
        HStack {
            Text("▶ \(title)")
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundColor(.archiveAccent)
            if let count = count {
                Spacer()
                Text(count)
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundColor(.gray)
            }
        }
        .padding(.horizontal, 24)
    }
}

/// 寶可夢網格卡片：強化像素感與背景深度
struct PixelPokemonGridCard: View {
    let pokemon: PokemonDisplayModel
    
    var body: some View {
        VStack(spacing: 0) {
            // 頂部資訊列 (保持不變)
            HStack {
                Text("Lv.\(pokemon.level)")
                    .font(.system(size: 12, weight: .black, design: .monospaced))
                    .foregroundColor(.archiveGold)
                Spacer()
                if pokemon.isShiny {
                    Image(systemName: "sparkles")
                        .font(.system(size: 12))
                        .foregroundColor(.archiveGold)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(Color.black.opacity(0.2))
            
            // 圖像顯示區
            ZStack {
                // 1. 最底層：背景顏色
                Rectangle()
                    .fill(pokemon.typeColor.opacity(0.4))
                
                // 2. 中間層：背景精靈球 (作為浮水印)
                AsyncImage(url: URL(string: "https://raw.githubusercontent.com/PokeAPI/sprites/master/sprites/items/\(pokemon.caughtBall).png")) { img in
                    img.resizable()
                        .interpolation(.none)
                        .aspectRatio(contentMode: .fit)
                } placeholder: {
                    Color.clear
                }
                .frame(width: 80, height: 80) // 縮小尺寸，不要超過容器
                .opacity(0.15)               // 降低透明度，讓它更像背景
                .offset(x: 25, y: 15)        // 稍微偏移到右下角，增加層次感
                .allowsHitTesting(false)     // 確保背景圖不干擾觸控
                
                // 3. 最上層：寶可夢主體 GIF
                let gifUrlString = pokemon.isShiny 
                    ? "https://raw.githubusercontent.com/PokeAPI/sprites/master/sprites/pokemon/versions/generation-v/black-white/animated/shiny/\(pokemon.pokedexId).gif"
                    : "https://raw.githubusercontent.com/PokeAPI/sprites/master/sprites/pokemon/versions/generation-v/black-white/animated/\(pokemon.pokedexId).gif"

                if let url = URL(string: gifUrlString) {
                    GifImage(url: url)
                        .frame(width: 75, height: 75)
                        .zIndex(10)          // 強制指定最高層級
                } else {
                    let pngUrlString = pokemon.isShiny
                        ? "https://raw.githubusercontent.com/PokeAPI/sprites/master/sprites/pokemon/shiny/\(pokemon.pokedexId).png"
                        : "https://raw.githubusercontent.com/PokeAPI/sprites/master/sprites/pokemon/\(pokemon.pokedexId).png"

                    AsyncImage(url: URL(string: pngUrlString)) { img in
                        img.resizable().interpolation(.none).aspectRatio(contentMode: .fit)
                    } placeholder: { Color.clear }
                    .frame(width: 75, height: 75)
                    .zIndex(10)
                }
            }
            .frame(height: 100)
            .clipped() // 確保內容不會超出這一格
            
            // 血條區域 (保持不變)
            VStack(spacing: 4) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Rectangle().fill(Color.black)
                        let ratio = CGFloat(pokemon.currentHp) / CGFloat(pokemon.maxHp)
                        Rectangle()
                            .fill(ratio > 0.5 ? Color.archiveGreen : (ratio > 0.2 ? Color.archiveGold : Color.archiveRed))
                            .frame(width: max(0, geo.size.width * ratio))
                    }
                }
                .frame(height: 6)
                .overlay(Rectangle().stroke(Color.white.opacity(0.2), lineWidth: 1))
            }
            .padding(10)
            .background(Color.black.opacity(0.3))
        }
        .background(Color.archiveCard)
        .overlay(PixelBorder(color: .white.opacity(0.15)))
        .shadow(color: .black.opacity(0.4), radius: 0, x: 4, y: 4)
    }
}

/// 設備行：簡潔但有終端感
struct PixelTerminalRow: View {
    let device: ConnectedDevice
    let timeRemaining: Int
    let totpManager: TOTPManager // 傳入 Manager 以便即時計算
    @State private var codeWidth: CGFloat = 100
    
    var code: String {
        guard let secretData = Data(base64Encoded: device.secret),
              let code = totpManager.generateCode(secretData: secretData) else {
            return "------"
        }
        return code // 直接回傳 6 碼，不加空格
    }
    
    var body: some View {
        HStack(spacing: 16) {
            Text(device.name.uppercased())
                .font(.system(size: 20, weight: .black, design: .monospaced)) // 加大字體
                .foregroundColor(.archiveAccent)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            VStack(alignment: .trailing, spacing: 2) {
                Text(code)
                    .font(.system(size: 26, weight: .black, design: .monospaced))
                    .foregroundColor(.archiveAccent)
                    .shadow(color: Color.archiveAccent.opacity(0.5), radius: 2, x: 0, y: 0)
                    .background(GeometryReader { geo in
                        Color.clear.preference(key: WidthPreferenceKey.self, value: geo.size.width)
                    })
                
                // Progress Bar
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Rectangle().fill(Color.white.opacity(0.2))
                        Rectangle().fill(timeRemaining < 5 ? Color.archiveRed : Color.archiveAccent)
                            .frame(width: geo.size.width * (CGFloat(timeRemaining) / 30.0))
                    }
                }
                .frame(height: 4)
                .frame(width: codeWidth)
            }
            .onPreferenceChange(WidthPreferenceKey.self) { width in
                codeWidth = width
            }
        }
        .padding(16)
        .background(Color.archiveCard)
        .overlay(PixelBorder(color: .white.opacity(0.1)))
    }
}

struct WidthPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

struct PixelIconButton: View {
    let icon: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(.white)
                .frame(width: 40, height: 40)
                .background(Color.archiveCard)
                .overlay(PixelBorder(color: .white.opacity(0.2)))
                .shadow(color: .black, radius: 0, x: 2, y: 2)
        }
    }
}

struct ScanlineOverlay: View {
    var body: some View {
        GeometryReader { geo in
            Path { path in
                for y in stride(from: 0, to: geo.size.height, by: 4) {
                    path.move(to: CGPoint(x: 0, y: y))
                    path.addLine(to: CGPoint(x: geo.size.width, y: y))
                }
            }
            .stroke(Color.black, lineWidth: 1)
        }
    }
}

// MARK: - 輔助 View 與 Sheet
struct PixelEmptyView: View {
    var body: some View {
        VStack(spacing: 15) {
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 30))
                .foregroundColor(.white.opacity(0.1))
            Text("NO PARTY DATA")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundColor(.white.opacity(0.2))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
        .background(Color.black.opacity(0.2))
        .overlay(PixelBorder(color: .white.opacity(0.05)))
        .padding(.horizontal, 20)
    }
}

struct PixelEmptySlot: View {
    var body: some View {
        VStack {
            Image(systemName: "plus")
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(.white.opacity(0.1))
        }
        .frame(height: 140) // Match card height roughly
        .frame(maxWidth: .infinity)
        .background(Color.black.opacity(0.1))
        .overlay(
            RoundedRectangle(cornerRadius: 0)
                .stroke(style: StrokeStyle(lineWidth: 2, dash: [5]))
                .foregroundColor(.white.opacity(0.1))
        )
    }
}

struct ScannerSheet: View {
    @Binding var isShowing: Bool
    let onScan: (String) -> Void
    
    var body: some View {
        ZStack {
            // 背景：深紫色系 LCD 質感
            Color.archiveBG.ignoresSafeArea()
            ScanlineOverlay().opacity(0.1).ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Header
                HStack {
                    Text("▶ SCANNER_MODULE")
                        .font(.system(size: 16, weight: .black, design: .monospaced))
                        .foregroundColor(.archiveAccent)
                    
                    Spacer()
                    
                    Button(action: { isShowing = false }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.white)
                            .frame(width: 32, height: 32)
                            .background(Color.archiveCard)
                            .overlay(PixelBorder(color: .white.opacity(0.2)))
                    }
                }
                .padding(20)
                .background(Color.archiveCard)
                .overlay(Rectangle().frame(height: 2).foregroundColor(Color.black.opacity(0.5)), alignment: .bottom)
                
                // Scanner Container
                ZStack {
                    // Scanner View
                    ScannerView(isScanning: $isShowing, onScanResult: onScan)
                        .clipShape(RoundedRectangle(cornerRadius: 0))
                        .overlay(PixelBorder(color: Color.archiveAccent.opacity(0.3)))
                    
                    // Viewfinder Overlay
                    ZStack {
                        Rectangle()
                            .stroke(Color.archiveAccent.opacity(0.5), style: StrokeStyle(lineWidth: 2, dash: [10]))
                            .padding(10)
                        
                        // Corners
                        VStack {
                            HStack {
                                CornerBracket()
                                Spacer()
                                CornerBracket().rotationEffect(.degrees(90))
                            }
                            Spacer()
                            HStack {
                                CornerBracket().rotationEffect(.degrees(-90))
                                Spacer()
                                CornerBracket().rotationEffect(.degrees(180))
                            }
                        }
                        .padding(10)
                    }
                }
                .padding(20)
                .frame(maxHeight: .infinity)
                
                // Footer Text
                Text("ALIGN QR CODE WITHIN FRAME")
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.5))
                    .padding(.bottom, 30)
            }
        }
    }
}

struct CornerBracket: View {
    var body: some View {
        Path { path in
            path.move(to: CGPoint(x: 0, y: 20))
            path.addLine(to: CGPoint(x: 0, y: 0))
            path.addLine(to: CGPoint(x: 20, y: 0))
        }
        .stroke(Color.archiveAccent, lineWidth: 4)
        .frame(width: 20, height: 20)
    }
}

struct ExportPopup: View {
    @Binding var isShowing: Bool
    let dataString: String
    
    var body: some View {
        ZStack {
            Color.black.opacity(0.6).ignoresSafeArea()
                .onTapGesture { isShowing = false }
            
            VStack(spacing: 16) {
                Text("EXPORT DATA")
                    .font(.system(size: 16, weight: .black, design: .monospaced))
                    .foregroundColor(.white)
                
                Button(action: {
                    UIPasteboard.general.string = dataString
                    isShowing = false
                }) {
                    HStack {
                        Image(systemName: "doc.on.doc")
                        Text("COPY TO CLIPBOARD")
                    }
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundColor(.black)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color.archiveAccent)
                    .overlay(PixelBorder(color: .white.opacity(0.5)))
                }
            }
            .padding(24)
            .background(Color.archiveCard)
            .overlay(PixelBorder(color: .archiveAccent))
            .padding(.horizontal, 40)
        }
    }
}

struct SettingsView: View {
    @Binding var githubToken: String
    @Binding var gistId: String
    var onReset: () -> Void
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationView {
            ZStack {
                Color.archiveBG.ignoresSafeArea()
                ScanlineOverlay().opacity(0.1).ignoresSafeArea()
                
                VStack(spacing: 24) {
                    // Header
                    HStack {
                        Text("SYSTEM CONFIG")
                            .font(.system(size: 20, weight: .black, design: .monospaced))
                            .foregroundColor(.white)
                        Spacer()
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 20)
                    
                    ScrollView {
                        VStack(spacing: 30) {
                            // Section 1: Credentials
                            VStack(alignment: .leading, spacing: 16) {
                                SectionHeader(title: "CREDENTIALS", count: nil)
                                
                                VStack(spacing: 12) {
                                    // Token Input
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("GITHUB TOKEN")
                                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                                            .foregroundColor(.gray)
                                        SecureField("Paste Token Here", text: $githubToken)
                                            .textFieldStyle(PlainTextFieldStyle())
                                            .font(.system(size: 12, design: .monospaced))
                                            .foregroundColor(.white)
                                            .padding(12)
                                            .background(Color.black.opacity(0.3))
                                            .overlay(PixelBorder(color: .white.opacity(0.2)))
                                    }
                                    
                                    // Gist ID Input
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("GIST ID")
                                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                                            .foregroundColor(.gray)
                                        TextField("Paste Gist ID Here", text: $gistId)
                                            .textFieldStyle(PlainTextFieldStyle())
                                            .font(.system(size: 12, design: .monospaced))
                                            .foregroundColor(.white)
                                            .autocapitalization(.none)
                                            .padding(12)
                                            .background(Color.black.opacity(0.3))
                                            .overlay(PixelBorder(color: .white.opacity(0.2)))
                                    }
                                    
                                    // GitHub Link Button
                                    Link(destination: URL(string: "https://github.com/settings/tokens")!) {
                                        HStack {
                                            Image(systemName: "link")
                                            Text("APPLY FOR TOKEN")
                                        }
                                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                                        .foregroundColor(.black)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 10)
                                        .background(Color.archiveAccent)
                                        .overlay(PixelBorder(color: .white.opacity(0.5)))
                                    }
                                }
                                .padding(.horizontal, 20)
                            }
                            
                            // Section 2: Danger Zone
                            VStack(alignment: .leading, spacing: 16) {
                                SectionHeader(title: "DANGER ZONE", count: nil)
                                
                                Button(action: onReset) {
                                    HStack {
                                        Image(systemName: "exclamationmark.triangle.fill")
                                        Text("FACTORY RESET")
                                    }
                                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                                    .foregroundColor(.white)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                                    .background(Color.archiveRed.opacity(0.8))
                                    .overlay(PixelBorder(color: .white.opacity(0.2)))
                                }
                                .padding(.horizontal, 20)
                            }
                        }
                    }
                }
            }
            .navigationBarHidden(true)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("DONE") { dismiss() }
                        .font(.monospaced(.body)())
                        .foregroundColor(.archiveAccent)
                }
            }
            .overlay(
                // Custom Close Button since we hid the nav bar
                VStack {
                    HStack {
                        Spacer()
                        Button(action: { dismiss() }) {
                            Image(systemName: "xmark")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundColor(.white)
                                .frame(width: 40, height: 40)
                                .background(Color.black.opacity(0.5))
                                .overlay(PixelBorder(color: .white.opacity(0.2)))
                        }
                    }
                    Spacer()
                }
                .padding(20)
            )
        }
    }
}

// MARK: - 模型轉換
struct PokemonDisplayModel: Identifiable {
    let id: String; let pokedexId: Int; let name: String; let nickname: String?; let level: Int; let currentHp: Int; let maxHp: Int; let isShiny: Bool; let types: [String]; let caughtBall: String
    var displayName: String { nickname ?? name }
}

extension PokemonDisplayModel {
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