import SwiftUI
import SwiftData
import Combine

struct PartyPage: View {
    @Environment(\.modelContext) private var modelContext
    @ObservedObject var settings: SecureSettings
    @ObservedObject var totpManager: TOTPManager
    
    @Query(sort: \Pokemon.slotIndex) var team: [Pokemon]
    @Query(sort: \TeamHistory.timestamp, order: .reverse) var histories: [TeamHistory]
    @Query var devices: [ConnectedDevice]
    
    @State private var selectedHistory: TeamHistory?
    @State private var selectedDevice: ConnectedDevice?
    @State private var showingSettings = false
    @State private var timeRemaining = 30
    @State private var isShowingScanner = false
    @State private var showingExportAlert = false
    @State private var exportedString = ""
    @State private var exportedLockId = 0
    @State private var showingDeviceNameInput = false
    @State private var newDeviceName = ""
    @State private var editingDevice: ConnectedDevice?
    @State private var deletingDevice: ConnectedDevice?
    @State private var pendingPayload: SyncPayload?
    
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
            Color.archiveBG.ignoresSafeArea()
            ScanlineOverlay().opacity(0.1).ignoresSafeArea()
            
            VStack(spacing: 0) {
                // MARK: - Header 標題
                HStack {
                    Text("▶ PARTY")
                        .font(.system(size: 18, weight: .black, design: .monospaced))
                        .foregroundColor(.white)
                    Spacer()
                    HStack(spacing: 12) {
                        PixelIconButton(icon: "gearshape.fill") { showingSettings = true }
                        PixelIconButton(icon: "qrcode.viewfinder") { isShowingScanner = true }
                        PixelIconButton(icon: "square.and.arrow.up") { exportData() }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 15)
                .padding(.bottom, 20)
                
                ScrollView {
                    VStack(spacing: 30) {
                        // MARK: - 隊伍狀態區域
                        VStack(alignment: .leading, spacing: 16) {
                            HStack {
                                Text("▶ PARTY STATUS")
                                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                                    .foregroundColor(.archiveAccent)
                                
                                Spacer()
                                
                                HStack(spacing: 4) {
                                    Text(selectedHistory != nil ? "#\(SyncService.getTimeHash(selectedHistory!.timestamp))" : (histories.first != nil ? "#\(SyncService.getTimeHash(histories.first!.timestamp))" : "---"))
                                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                                        .foregroundColor(.gray)
                                    
                                    if let history = selectedHistory ?? histories.first, history.isSynced {
                                        Image(systemName: "checkmark.circle.fill")
                                            .font(.system(size: 10))
                                            .foregroundColor(.archiveGreen)
                                    }
                                }
                                .padding(.trailing, 8)

                                Menu {
                                    Button("最新") { selectedHistory = nil }
                                    ForEach(histories) { history in
                                        let hash = SyncService.getTimeHash(history.timestamp)
                                        Button {
                                            selectedHistory = history
                                        } label: {
                                            if history.isSynced {
                                                Label("v\(history.lockId) [\(hash)] (\(formatDate(history.timestamp)))", systemImage: "checkmark.circle.fill")
                                            } else {
                                                Text("v\(history.lockId) [\(hash)] (\(formatDate(history.timestamp)))")
                                            }
                                        }
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
                        
                        // MARK: - 連結終端區域
                        if !devices.isEmpty {
                            VStack(alignment: .leading, spacing: 16) {
                                SectionHeader(title: "LINKED TERMINALS", count: nil)
                                
                                ForEach(devices) { device in
                                    PixelTerminalRow(
                                        device: device,
                                        timeRemaining: timeRemaining,
                                        totpManager: totpManager,
                                        onEdit: {
                                            editingDevice = device
                                            newDeviceName = device.name
                                            showingDeviceNameInput = true
                                        },
                                        onDelete: {
                                            deletingDevice = device
                                        }
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
            
            if showingDeviceNameInput {
                DeviceConfigPopup(
                    isShowing: $showingDeviceNameInput,
                    deviceName: $newDeviceName,
                    onSave: {
                        if let payload = pendingPayload {
                            savePayloadByType(payload: payload, name: newDeviceName)
                        } else if let device = editingDevice {
                            device.name = newDeviceName
                            try? modelContext.save()
                            editingDevice = nil
                        }
                        showingDeviceNameInput = false
                    },
                    onCancel: {
                        pendingPayload = nil
                        editingDevice = nil
                        showingDeviceNameInput = false
                    }
                )
                .zIndex(101)
            }
        }
        .onReceive(timer) { _ in updateTOTP() }
        .sheet(isPresented: $isShowingScanner) {
            ScannerSheet(isShowing: $isShowingScanner) { handleQRCodeScanned($0) }
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView(
                settings: settings,
                unsyncedHistories: histories.filter { !$0.isSynced },
                onReset: resetAll,
                onReupload: reuploadHistory
            )
        }

        .alert("DELETE TERMINAL?", isPresented: Binding<Bool>(
            get: { deletingDevice != nil },
            set: { if !$0 { deletingDevice = nil } }
        )) {
            Button("CANCEL", role: .cancel) { deletingDevice = nil }
            Button("DELETE", role: .destructive) {
                if let device = deletingDevice {
                    modelContext.delete(device)
                    deletingDevice = nil
                }
            }
        } message: {
            if let device = deletingDevice {
                Text("Are you sure you want to remove '\(device.name)'? This action cannot be undone.")
            }
        }
        .onAppear {
            if selectedDevice == nil { selectedDevice = devices.first }
            updateTOTP()
        }
    }
    
    // MARK: - Helper Functions
    
    private func updateTOTP() {
        let now = Date().timeIntervalSince1970
        timeRemaining = 30 - (Int(now) % 30)
    }
    
    private func formatDate(_ timestamp: Double) -> String {
        let date = Date(timeIntervalSince1970: timestamp)
        let formatter = DateFormatter()
        formatter.dateFormat = "MM/dd HH:mm"
        return formatter.string(from: date)
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
        
        let timestamp = Date().timeIntervalSince1970
        let lockId = histories.first?.lockId ?? 0
        
        let payload = SyncPayload(
            secret: selectedDevice?.secret ?? "",
            type: .party,
            transferPokemons: dtos,
            lockId: lockId,
            timestamp: timestamp
        )
        
        if let jsonData = try? JSONEncoder().encode(payload),
           let compressed = jsonData.gzipped() {
            exportedString = "GZIP:" + compressed.base64EncodedString()
            exportedLockId = lockId
            showingExportAlert = true
        }
    }


    
    private func handleQRCodeScanned(_ code: String) {
        guard let payload = SyncService.decodePayload(base64: code) else {
            print("QR Code 解碼失敗")
            return
        }
        
        isShowingScanner = false
        pendingPayload = payload
        
        if payload.type == .bindSetup {
            let descriptor = FetchDescriptor<ConnectedDevice>(predicate: #Predicate<ConnectedDevice> { $0.secret == payload.secret })
            if let existing = try? modelContext.fetch(descriptor).first {
                savePayloadByType(payload: payload, name: existing.name)
            } else {
                let nextIndex = devices.count + 1
                newDeviceName = "Vscode-\(nextIndex)"
                
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    self.showingDeviceNameInput = true
                }
            }
        }
        if payload.type == .party {
            let descriptor = FetchDescriptor<ConnectedDevice>(predicate: #Predicate<ConnectedDevice> { $0.secret == payload.secret })
            let existingName = (try? modelContext.fetch(descriptor).first)?.name ?? "Unknown Device"
            savePayloadByType(payload: payload, name: existingName)
        }
    }
    
    private func savePayloadByType(payload: SyncPayload, name: String) {
        if let newDevice = SyncService.processPayload(payload: payload, name: name, context: modelContext, settings: settings) {
            self.selectedDevice = newDevice
        }
        
        updateTOTP()
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        print("✅ 裝置已儲存/更新，Secret: \(payload.secret)")
        
        pendingPayload = nil
        showingDeviceNameInput = false
    }
    
    private func reuploadHistory(_ history: TeamHistory) {
        guard !settings.githubToken.isEmpty, !settings.gistId.isEmpty else { return }
        
        guard let dtos = try? JSONDecoder().decode([PokemonSyncDTO].self, from: history.teamJson) else {
            print("❌ 無法解析歷史紀錄資料")
            return
        }
        
        let exportPayload = SyncPayload(
            secret: "",
            type: .party,
            transferPokemons: dtos,
            lockId: history.lockId,
            timestamp: history.timestamp
        )
        
        guard let compressed = try? JSONEncoder().encode(exportPayload).gzipped() else {
            print("❌ 壓縮失敗")
            return
        }
        
        let content = "GZIP:" + compressed.base64EncodedString()
        let hash = SyncService.getTimeHash(history.timestamp)
        let filename = "pokecodec-party-\(hash).txt"
        
        SyncService.uploadToGist(content: content, filename: filename, token: settings.githubToken, gistId: settings.gistId) { result in
            DispatchQueue.main.async {
                switch result {
                case .success(_):
                    print("✅ 歷史紀錄補上傳成功")
                    history.isSynced = true
                case .failure(let error):
                    print("❌ 補上傳失敗: \(error)")
                }
            }
        }
    }
    
    private func resetAll() {
        try? modelContext.delete(model: Pokemon.self)
        try? modelContext.delete(model: ConnectedDevice.self)
        try? modelContext.delete(model: TeamHistory.self)
        settings.gistId = ""
        settings.githubToken = ""
    }
}
