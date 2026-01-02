import SwiftUI
import SwiftData
import Combine
import VisionKit
import CryptoKit

struct ContentView: View {
    @Query(sort: \Pokemon.pokedexId) var team: [Pokemon]
    @Query var devices: [ConnectedDevice]
    @Query(sort: \TeamHistory.timestamp, order: .reverse) var histories: [TeamHistory]
    @Environment(\.modelContext) private var modelContext

    @State private var isShowingScanner = false
    @State private var selectedPokemon: Pokemon?
    
    // 匯出與版本相關
    @State private var selectedHistory: TeamHistory?
    @State private var exportedString = ""
    @State private var exportedLockId = 0
    @State private var showingExportAlert = false
    
    // 設定
    @AppStorage("githubToken") private var githubToken = ""
    @AppStorage("PokecodecGistId") private var gistId = "YOUR_DEFAULT_GIST_ID"
    @State private var showingSettings = false
    
    // 2FA 相關
    @StateObject private var totpManager = TOTPManager()
    @State private var selectedDevice: ConnectedDevice?
    @State private var totpCode: String = "--- ---"
    @State private var timeRemaining: Int = 30
    let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    // 處理掃描
    @State private var pendingPayload: SyncPayload?
    @State private var showingDeviceNameInput = false
    @State private var newDeviceName = ""

    var body: some View {
        NavigationView {
            mainList
                .navigationTitle("PokéCodec")
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button(action: { showingSettings = true }) {
                            Image(systemName: "gearshape")
                        }
                    }
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button(action: { isShowingScanner = true }) {
                            Image(systemName: "qrcode.viewfinder").font(.title2)
                        }
                    }
                }
                .sheet(isPresented: $isShowingScanner) {
                    // Scanner 視圖邏輯保持不變
                    ScannerSheet(isShowing: $isShowingScanner) { handleQRCodeScanned($0) }
                }
                .sheet(isPresented: $showingSettings) {
                    SettingsView(githubToken: $githubToken, gistId: $gistId, onReset: resetAll)
                }
                .alert("匯出資料", isPresented: $showingExportAlert) {
                    Button("複製") { UIPasteboard.general.string = exportedString }
                    Button("關閉", role: .cancel) { }
                } message: {
                    Text("已產生加密字串 (v\(exportedLockId))")
                }
                .alert("新裝置連線", isPresented: $showingDeviceNameInput) {
                    TextField("裝置名稱", text: $newDeviceName)
                    Button("取消", role: .cancel) { pendingPayload = nil }
                    Button("儲存") { 
                        guard let payload = pendingPayload else { return }
                        savePayloadByType(payload: payload, name: newDeviceName)
                    }   
                } message: {
                    Text("偵測到新的 VS Code 實例，請為其命名以方便識別。")
                }
                .onReceive(timer) { _ in updateTOTP() }
                .onAppear {
                    // 如果 Gist ID 為空，載入預設值 (解決 AppStorage 保留舊空值的問題)
                    if gistId.isEmpty { gistId = "YOUR_DEFAULT_GIST_ID" }
                    
                    if selectedDevice == nil { selectedDevice = devices.first }
                    updateTOTP()
                }
        }
    }

    var mainList: some View {
        List {
            exportSection
            teamSection
            deviceSection
        }
        .listStyle(.insetGrouped)
    }

    var displayedTeam: [PokemonDisplayModel] {
        if let history = selectedHistory,
           let dtos = try? JSONDecoder().decode([PokemonSyncDTO].self, from: history.teamJson) {
            return dtos.map { $0.toDisplayModel() }
        }
        return team.map { $0.toDisplayModel() }
    }
    
    var currentHashDisplay: String {
        if let history = selectedHistory {
            return SyncService.getTimeHash(history.timestamp)
        }
        if let latest = histories.first {
            return SyncService.getTimeHash(latest.timestamp)
        }
        return ""
    }
    
    var allHistories: [TeamHistory] {
        histories
    }

    var teamSection: some View {
        Section(header: 
            HStack {
                Text("我的隊伍 (\(displayedTeam.count)/6)")
                    .font(.headline)
                Spacer()
                if !currentHashDisplay.isEmpty {
                    Text("#\(currentHashDisplay)")
                        .font(.system(.caption, design: .monospaced))
                        .fontWeight(.bold)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.1))
                        .cornerRadius(4)
                }
            }
        ) {
            ForEach(displayedTeam) { pokemon in
                PokemonListRow(pokemon: pokemon)
                    .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
            }
            
            if displayedTeam.isEmpty {
                Text("目前隊伍中沒有寶可夢")
                    .foregroundColor(.secondary)
                    .font(.caption)
            }
        }
    }

    var deviceSection: some View {
        Section(header: Text("已綁定設備").font(.headline)) {
            if devices.isEmpty {
                Text("尚未綁定任何 VS Code 實例").font(.caption).foregroundColor(.secondary)
            } else {
                ForEach(devices) { device in
                    DeviceListRow(device: device, totpCode: (device == selectedDevice) ? totpCode : "------", timeRemaining: timeRemaining)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            selectedDevice = device
                            updateTOTP()
                        }
                        .listRowBackground(selectedDevice == device ? Color.blue.opacity(0.1) : Color.clear)
                }
            }
        }
    }

    var exportSection: some View {
        Section(header: Text("資料管理")) {
            HStack {
                // 左側：版本選擇 (下拉選單)
                Picker("版本", selection: $selectedHistory) {
                    Text("最新").tag(nil as TeamHistory?)
                    ForEach(allHistories) { history in
                        let hash = SyncService.getTimeHash(history.timestamp)
                        Text("v\(history.lockId) [\(hash)] (\(formatDate(history.timestamp)))").tag(history as TeamHistory?)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                
                Spacer()
                
                // 右側：匯出按鈕 (獨立按鈕)
                Button(action: { exportData() }) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(width: 36, height: 36)
                        .background(Color.blue)
                        .clipShape(Circle())
                }
                .buttonStyle(.borderless)
            }
        }
    }

    // MARK: - Helper Functions (邏輯與原本雷同，稍作整理)
    
    func updateTOTP() {
        guard let device = selectedDevice,
              let secretData = Data.fromBase32(device.secret) else {
            totpCode = "--- ---"
            return
        }
        let now = Date().timeIntervalSince1970
        timeRemaining = 30 - (Int(now) % 30)
        totpCode = totpManager.generateCode(secretData: secretData) ?? "--- ---"
    }

    func exportData() {
        let dtos: [PokemonSyncDTO]
        let lockId: Int
        let timestamp: Double
        
        if let history = selectedHistory {
            // Export from history
            guard let historyDtos = try? JSONDecoder().decode([PokemonSyncDTO].self, from: history.teamJson) else {
                print("Failed to decode history")
                return
            }
            dtos = historyDtos
            lockId = history.lockId
            timestamp = history.timestamp
        } else {
            // Export current
            dtos = team.map { $0.toDTO() }
            // Use the lockId from the latest history
            lockId = allHistories.first?.lockId ?? 0
            timestamp = Date().timeIntervalSince1970
        }
        
        exportedLockId = lockId
        
        let payload = SyncPayload(
            secret: "", // Secret is not exported
            type: .party,
            party: dtos,
            lockId: lockId,
            timestamp: timestamp
        )
        
        // ... 編碼與壓縮邏輯 ...
        if let compressed = try? JSONEncoder().encode(payload).gzipped() {
            exportedString = "GZIP:" + compressed.base64EncodedString()
            showingExportAlert = true
        }
    }
    
    func formatDate(_ timestamp: Double) -> String {
        // 判斷是否為毫秒 (若大於 2030 年的秒數，假設為毫秒)
        let seconds = timestamp > 1893456000 ? timestamp / 1000 : timestamp
        let date = Date(timeIntervalSince1970: seconds)
        
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy/MM/dd HH:mm"
        return formatter.string(from: date)
    }
    
    func savePayloadByType(payload: SyncPayload, name: String) {

        if payload.type == .party && !(payload.party?.isEmpty ?? true) && payload.lockId >= 0 {
            SyncService.saveParty(payload: payload, context: modelContext, githubToken: githubToken)
        }else if payload.type == .bindSetup {
            SyncService.saveDevice(payload: payload, name: name, context: modelContext)
        }
        
        // 重新抓取並設定為選中
        let descriptor = FetchDescriptor<ConnectedDevice>(predicate: #Predicate<ConnectedDevice> { $0.secret == payload.secret })
        if let newDevice = try? modelContext.fetch(descriptor).first {
            self.selectedDevice = newDevice
        }
        
        updateTOTP() // 立即更新
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        print("✅ 裝置已儲存/更新，Secret: \(payload.secret)")
        
        pendingPayload = nil
    }
    
    func handleQRCodeScanned(_ code: String) {
        print("📏 掃描到的字串長度：\(code.count)")
        
        guard let payload = SyncService.decodePayload(base64: code) else {
            print("❌ 解碼失敗")
            return
        }
        
        self.pendingPayload = payload
        
        // 檢查裝置是否已存在
        let secret = payload.secret
        let descriptor = FetchDescriptor<ConnectedDevice>(
            predicate: #Predicate<ConnectedDevice> { $0.secret == secret }
        )
        
        do {
            if let existing = try modelContext.fetch(descriptor).first {
                // 裝置已存在
                print("✅ 識別到已知裝置: \(existing.name)")
                
                // 如果是單純的 Setup Payload (lockId 為負值)，只更新選中狀態
                if payload.lockId < 0 {
                    self.selectedDevice = existing
                    updateTOTP()
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    self.pendingPayload = nil
                    return
                }
                
                // 只有當 party 不為空且 lockId >= 0 時才儲存隊伍
                savePayloadByType(payload: payload, name: existing.name)
            } else {
                // 新裝置，跳出輸入名稱視窗
                print("🆕 偵測到新裝置")
                self.newDeviceName = "My VS Code"
                self.showingDeviceNameInput = true
            }
        } catch {
            print("❌ 檢查裝置失敗: \(error)")
        }
    }

    func resetAll() {
        try? modelContext.delete(model: Pokemon.self)
        try? modelContext.delete(model: ConnectedDevice.self)
        selectedDevice = nil
    }
}

// MARK: - Models & Extensions

struct PokemonDisplayModel: Identifiable {
    let id: String
    let pokedexId: Int
    let name: String
    let nickname: String?
    let level: Int
    let currentHp: Int
    let maxHp: Int
    let isShiny: Bool
    let linesOfCode: Int
    let bugsFixed: Int
    let types: [String]
    
    var displayName: String { nickname ?? name }
    
    var color: Color {
        guard let type = types.first?.lowercased() else { return .blue }
        switch type {
        case "fire": return .red
        case "water": return .blue
        case "grass": return .green
        case "electric": return .yellow
        case "psychic": return .purple
        case "normal": return .gray
        case "fighting": return .orange
        case "poison": return .purple
        case "ground": return .brown
        case "flying": return .cyan
        case "bug": return .green
        case "rock": return .brown
        case "ghost": return .indigo
        case "dragon": return .indigo
        case "steel": return .gray
        case "ice": return .cyan
        case "fairy": return .pink
        default: return .blue
        }
    }
}

extension Pokemon {
    func toDisplayModel() -> PokemonDisplayModel {
        PokemonDisplayModel(
            id: uid,
            pokedexId: pokedexId,
            name: name,
            nickname: nickname,
            level: level,
            currentHp: currentHp,
            maxHp: maxHp,
            isShiny: isShiny,
            linesOfCode: linesOfCode,
            bugsFixed: bugsFixed,
            types: types
        )
    }
}

extension PokemonSyncDTO {
    func toDisplayModel() -> PokemonDisplayModel {
        PokemonDisplayModel(
            id: uid,
            pokedexId: id,
            name: name,
            nickname: nickname,
            level: level,
            currentHp: currentHp,
            maxHp: maxHp,
            isShiny: isShiny,
            linesOfCode: codingStats?.linesOfCode ?? 0,
            bugsFixed: codingStats?.bugsFixed ?? 0,
            types: types
        )
    }
}

// MARK: - 子視圖：寶可夢列表列
struct PokemonListRow: View {
    let pokemon: PokemonDisplayModel
    
    var body: some View {
        HStack(spacing: 15) {
            // 左側：圖片/圓形背景
            ZStack {
                Circle()
                    .fill(pokemon.color.opacity(0.2))
                    .frame(width: 60, height: 60)
                
                let spriteUrl = pokemon.isShiny 
                    ? "https://raw.githubusercontent.com/PokeAPI/sprites/master/sprites/pokemon/shiny/\(pokemon.pokedexId).png"
                    : "https://raw.githubusercontent.com/PokeAPI/sprites/master/sprites/pokemon/\(pokemon.pokedexId).png"

                AsyncImage(url: URL(string: spriteUrl)) { phase in
                    switch phase {
                    case .empty:
                        ProgressView()
                    case .success(let image):
                        image.resizable()
                             .aspectRatio(contentMode: .fit)
                    case .failure:
                        Text(String(pokemon.name.prefix(1)))
                            .font(.title2).bold()
                            .foregroundColor(pokemon.color)
                    @unknown default:
                        EmptyView()
                    }
                }
                .frame(width: 50, height: 50)
            }
            
            // 右側：詳細資料
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .center) {
                    Text(pokemon.displayName)
                        .font(.headline)
                    
                    if pokemon.isShiny {
                        Image(systemName: "sparkles")
                            .foregroundColor(.yellow)
                            .font(.caption)
                    }
                    
                    Spacer()
                    
                    Text("Lv.\(pokemon.level)")
                        .font(.system(.caption, design: .monospaced))
                        .fontWeight(.bold)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.1))
                        .cornerRadius(4)
                }
                
                // 血條設計
                VStack(spacing: 2) {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.gray.opacity(0.2))
                            
                            let ratio = Double(pokemon.currentHp) / Double(pokemon.maxHp)
                            let barColor: Color = ratio > 0.5 ? .green : (ratio > 0.2 ? .yellow : .red)
                            
                            Capsule().fill(barColor)
                                .frame(width: geo.size.width * ratio)
                        }
                    }
                    .frame(height: 8)
                    
                    HStack {
                        Text("\(pokemon.currentHp)/\(pokemon.maxHp) HP")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                }
            }
        }
        .padding(.vertical, 6)
    }
}

// MARK: - 子視圖：設備列表列
struct DeviceListRow: View {
    let device: ConnectedDevice
    let totpCode: String
    let timeRemaining: Int
    
    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(device.name)
                    .font(.body)
                Text("ID: \(device.lockId)")
                    .font(.caption2).monospaced()
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            VStack(alignment: .trailing) {
                Text(totpCode)
                    .font(.system(.body, design: .monospaced)).bold()
                    .foregroundColor(.blue)
                
                // 倒數小進度條
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.gray.opacity(0.2))
                        Capsule().fill(timeRemaining < 5 ? Color.red : Color.blue)
                            .frame(width: geo.size.width * CGFloat(Double(timeRemaining) / 30.0))
                    }
                }
                .frame(width: 60, height: 4)
            }
        }
    }
}

struct ScannerSheet: View {
    @Binding var isShowing: Bool
    let onScan: (String) -> Void
    
    var body: some View {
        VStack {
            HStack {
                Text("掃描 QR Code").font(.headline)
                Spacer()
                Button("關閉") { isShowing = false }
            }
            .padding()

            #if targetEnvironment(simulator)
            ContentUnavailableView("不支援掃描",
                                   systemImage: "camera.fill",
                                   description: Text("請使用實體 iPhone 進行測試，模擬器不支援 VisionKit 掃描器。"))
            #else
            if DataScannerViewController.isSupported && DataScannerViewController.isAvailable {
                ScannerView(isScanning: $isShowing, onScanResult: onScan)
                    .cornerRadius(12)
                    .padding()
            } else {
                ContentUnavailableView("不支援掃描",
                                       systemImage: "camera.fill",
                                       description: Text("此裝置不支援 VisionKit 掃描器。"))
            }
            #endif
        }
    }
}

struct SettingsView: View {
    @Binding var githubToken: String
    @Binding var gistId: String
    var onReset: () -> Void
    @State private var showingResetAlert = false
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("GitHub 設定")) {
                    SecureField("Personal Access Token", text: $githubToken)
                    
                    VStack(alignment: .leading) {
                        Text("Gist ID")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        HStack {
                            Text((gistId.isEmpty || gistId == "YOUR_DEFAULT_GIST_ID") ? "尚未產生" : gistId)
                                .font(.system(.body, design: .monospaced))
                                .foregroundColor((gistId.isEmpty || gistId == "YOUR_DEFAULT_GIST_ID") ? .secondary : .primary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            
                            Spacer()
                            
                            if !gistId.isEmpty && gistId != "YOUR_DEFAULT_GIST_ID" {
                                Button(action: {
                                    UIPasteboard.general.string = gistId
                                }) {
                                    Image(systemName: "doc.on.doc")
                                        .foregroundColor(.blue)
                                }
                                .buttonStyle(.borderless)
                            }
                        }
                    }
                    
                    if !gistId.isEmpty && gistId != "YOUR_DEFAULT_GIST_ID" {
                        Button("清除 Gist ID (重新產生)") {
                            gistId = ""
                        }
                        .foregroundColor(.red)
                    }
                }
                
                Section(footer: Text("Token 需要 Gist 權限以進行雲端備份。")) {
                    Link("取得 GitHub Token", destination: URL(string: "https://github.com/settings/tokens")!)
                }
                
                Section(header: Text("危險區域")) {
                    Button(role: .destructive, action: { showingResetAlert = true }) {
                        HStack {
                            Image(systemName: "trash")
                            Text("重置所有資料")
                        }
                    }
                }
            }
            .navigationTitle("設定")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
            .alert("確定要重置嗎？", isPresented: $showingResetAlert) {
                Button("取消", role: .cancel) { }
                Button("刪除", role: .destructive) { 
                    onReset()
                    dismiss()
                }
            } message: {
                Text("此動作將刪除所有寶可夢與綁定裝置，且無法復原。")
            }
        }
    }
}
