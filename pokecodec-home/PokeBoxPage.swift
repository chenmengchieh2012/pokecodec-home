import SwiftUI
import SwiftData

struct PokeBoxPage: View {
    @Query var box: [PokeBox]
    @Query var devices: [ConnectedDevice]
    @Environment(\.modelContext) private var modelContext
    @ObservedObject var settings: SecureSettings
    
    @State private var searchText = ""
    @State private var selectedType: String?
    @State private var isShowingScanner = false
    @State private var showingDeviceNameInput = false
    @State private var newDeviceName = ""
    @State private var pendingPayload: SyncPayload?
    @State private var selectedDevice: ConnectedDevice?
    @State private var showingExportAlert = false
    @State private var exportedString = ""
    @State private var showingUploadSuccessAlert = false
    @State private var showingCopySuccessAlert = false
    
    var filteredBox: [PokeBox] {
        var filtered = box
        
        if !searchText.isEmpty {
            filtered = filtered.filter { pokemon in
                pokemon.name.lowercased().contains(searchText.lowercased()) ||
                pokemon.nickname?.lowercased().contains(searchText.lowercased()) ?? false
            }
        }
        
        if let type = selectedType {
            filtered = filtered.filter { $0.types.contains(type) }
        }
        
        return filtered.sorted { $0.pokedexId < $1.pokedexId }
    }
    
    var allTypes: [String] {
        Array(Set(box.flatMap { $0.types })).sorted()
    }
    
    var body: some View {
        ZStack {
            Color.archiveBG.ignoresSafeArea()
            ScanlineOverlay().opacity(0.1).ignoresSafeArea()
            
            VStack(spacing: 0) {
                // MARK: - Header
                HStack {
                    Text("▶ POKÉBOX")
                        .font(.system(size: 18, weight: .black, design: .monospaced))
                        .foregroundColor(.white)
                    Spacer()
                    PixelIconButton(icon: "qrcode.viewfinder") { isShowingScanner = true }
                }
                .padding(.horizontal, 20)
                .padding(.top, 15)
                .padding(.bottom, 20)
                
                // MARK: - 搜尋與篩選
                VStack(spacing: 12) {
                    SearchBar(text: $searchText)
                    
                    if !allTypes.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                Button(action: { selectedType = nil }) {
                                    Text("全部")
                                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                                        .foregroundColor(selectedType == nil ? .archiveBG : .archiveAccent)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 6)
                                        .background(selectedType == nil ? Color.archiveAccent : Color.black.opacity(0.4))
                                        .overlay(PixelBorder(color: Color.archiveAccent.opacity(0.5)))
                                }
                                
                                ForEach(allTypes, id: \.self) { type in
                                    Button(action: { selectedType = type }) {
                                        Text(type)
                                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                                            .foregroundColor(selectedType == type ? .archiveBG : .archiveAccent)
                                            .padding(.horizontal, 10)
                                            .padding(.vertical, 6)
                                            .background(selectedType == type ? Color.archiveAccent : Color.black.opacity(0.4))
                                            .overlay(PixelBorder(color: Color.archiveAccent.opacity(0.5)))
                                    }
                                }
                            }
                            .padding(.horizontal, 20)
                        }
                    }
                }
                .padding(.bottom, 16)
                
                // MARK: - 寶可夢列表
                if filteredBox.isEmpty {
                    VStack {
                        Spacer()
                        Text("沒有找到寶可夢")
                            .font(.system(size: 14, weight: .bold, design: .monospaced))
                            .foregroundColor(.archiveSecondary)
                        Spacer()
                    }
                } else {
                    ScrollView {
                        LazyVStack(spacing: 8, pinnedViews: []) {
                            ForEach(filteredBox) { pokemon in
                                PokeBoxCard(pokemon: pokemon, onExport: {
                                    exportPokemon(pokemon)
                                }, onUpload: {
                                    uploadPokemon(pokemon)
                                }, onCopyUID: {
                                    UIPasteboard.general.string = pokemon.uid
                                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                                    showingCopySuccessAlert = true
                                }, onDelete: {
                                    deletePokemon(pokemon)
                                })
                                .padding(.horizontal, 20)
                            }
                        }
                        .padding(.vertical, 16)
                    }
                }
            }
            
            if showingExportAlert {
                ExportPopup(isShowing: $showingExportAlert, dataString: exportedString)
                    .zIndex(100)
            }
        }
        .sheet(isPresented: $isShowingScanner) {
            ScannerSheet(isShowing: $isShowingScanner) { handleQRCodeScanned($0) }
        }
        .alert("上傳成功", isPresented: $showingUploadSuccessAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("寶可夢資料已成功上傳至 Gist")
        }
        .alert("已複製 UID", isPresented: $showingCopySuccessAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("UID 已複製到剪貼簿")
        }
    }


    private func handleQRCodeScanned(_ code: String) {
        guard let payload = SyncService.decodePayload(base64: code) else {
            print("QR Code 解碼失敗")
            return
        }
        
        isShowingScanner = false
        pendingPayload = payload
        if payload.type == .box {
            let descriptor = FetchDescriptor<ConnectedDevice>(predicate: #Predicate<ConnectedDevice> { $0.secret == payload.secret })
            let existingName = (try? modelContext.fetch(descriptor).first)?.name ?? "Unknown Device"
            savePayloadByType(payload: payload, name: existingName)
        }
    }
    
    
    private func savePayloadByType(payload: SyncPayload, name: String) {
        SyncService.processPayload(payload: payload, name: name, context: modelContext, settings: settings)
        
        // 如果是 Box 類型且有設定 Gist，則自動上傳
        if payload.type == .box,
           let pokemons = payload.transferPokemons,
           !settings.githubToken.isEmpty,
           !settings.gistId.isEmpty {
            
            print("🔄 自動上傳 \(pokemons.count) 隻寶可夢到 Gist...")
            
            for dto in pokemons {
                uploadDTO(dto, isManual: false) { success in
                    if success {
                        DispatchQueue.main.async {
                            markPokemonAsSynced(uid: dto.uid)
                        }
                    }
                }
            }
        }
        
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        print("✅ 裝置已儲存/更新，Secret: \(payload.secret)")
        
        pendingPayload = nil
        showingDeviceNameInput = false
    }
    
    private func markPokemonAsSynced(uid: String) {
        let descriptor = FetchDescriptor<PokeBox>(predicate: #Predicate<PokeBox> { $0.uid == uid })
        if let pokemon = try? modelContext.fetch(descriptor).first {
            pokemon.isSynced = true
            try? modelContext.save()
        }
    }
    
    private func uploadPokemon(_ pokemon: PokeBox) {
        guard !settings.githubToken.isEmpty, !settings.gistId.isEmpty else {
            print("❌ 缺少 GitHub Token 或 Gist ID")
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            return
        }
        
        let dto = createDTO(from: pokemon)
        uploadDTO(dto, isManual: true) { success in
            if success {
                pokemon.isSynced = true
                try? modelContext.save()
            }
        }
    }
    
    private func uploadDTO(_ dto: PokemonSyncDTO, isManual: Bool, completion: ((Bool) -> Void)? = nil) {
        let payload = SyncPayload(
            secret: "",
            type: .box,
            transferPokemons: [dto],
            lockId: -1,
            timestamp: Date().timeIntervalSince1970
        )
        
        guard let jsonData = try? JSONEncoder().encode(payload),
              let compressed = jsonData.gzipped() else {
            completion?(false)
            return
        }
              
        let content = "GZIP:" + compressed.base64EncodedString()
        let filename = "pokecodec-box-\(dto.uid).txt"
        
        SyncService.uploadToGist(content: content, filename: filename, token: settings.githubToken, gistId: settings.gistId) { result in
             if isManual {
                 DispatchQueue.main.async {
                     switch result {
                     case .success(_):
                         print("✅ 上傳成功")
                         UINotificationFeedbackGenerator().notificationOccurred(.success)
                         showingUploadSuccessAlert = true
                         completion?(true)
                     case .failure(let error):
                         print("❌ 上傳失敗: \(error)")
                         UINotificationFeedbackGenerator().notificationOccurred(.error)
                         completion?(false)
                     }
                 }
             } else {
                 switch result {
                 case .success(_):
                     print("✅ 自動上傳成功 (\(dto.name))")
                     completion?(true)
                 case .failure(let error):
                     print("❌ 自動上傳失敗 (\(dto.name)): \(error)")
                     completion?(false)
                 }
             }
        }
    }

    private func deletePokemon(_ pokemon: PokeBox) {
        let uid = pokemon.uid
        
        // Delete from local
        modelContext.delete(pokemon)
        try? modelContext.save()
        
        // Delete from Gist
        if !settings.githubToken.isEmpty, !settings.gistId.isEmpty {
            let filename = "pokecodec-box-\(uid).txt"
            SyncService.deleteFromGist(filename: filename, token: settings.githubToken, gistId: settings.gistId) { result in
                DispatchQueue.main.async {
                    switch result {
                    case .success:
                        print("🗑️ Gist file deleted: \(filename)")
                    case .failure(let error):
                        print("⚠️ Failed to delete Gist file: \(error)")
                    }
                }
            }
        }
        
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    private func exportPokemon(_ pokemon: PokeBox) {
        let dto = createDTO(from: pokemon)
        
        let payload = SyncPayload(
            secret: "",
            type: .box,
            transferPokemons: [dto],
            lockId: -1,
            timestamp: Date().timeIntervalSince1970
        )
        
        if let jsonData = try? JSONEncoder().encode(payload),
           let compressed = jsonData.gzipped() {
            exportedString = "GZIP:" + compressed.base64EncodedString()
            showingExportAlert = true
        }
    }
    
    private func createDTO(from pokemon: PokeBox) -> PokemonSyncDTO {
        return PokemonSyncDTO(
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
}

// MARK: - 搜尋條
struct SearchBar: View {
    @Binding var text: String
    @FocusState private var isSearchFocused: Bool
    
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.archiveSecondary)
            
            TextField("搜尋寶可夢...", text: $text)
                .font(.system(size: 14, design: .monospaced))
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .disableAutocorrection(true)
                .autocapitalization(.none)
                .focused($isSearchFocused)
            
            if !text.isEmpty {
                Button(action: { text = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.archiveSecondary)
                }
            }
            
            // 完成按鈕用來收起鍵盤
            if isSearchFocused {
                Button(action: { isSearchFocused = false }) {
                    Text("完成")
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .foregroundColor(.archiveAccent)
                }
            }
        }
        .padding(.horizontal, 20)
    }
}

// MARK: - 寶可夢卡片
struct PokeBoxCard: View {
    let pokemon: PokeBox
    var onExport: () -> Void
    var onUpload: () -> Void
    var onCopyUID: () -> Void
    var onDelete: () -> Void
    
    @State private var isPressingUID = false
    
    // Swipe state
    @State private var offset: CGFloat = 0
    @State private var isSwiped = false
    private let buttonWidth: CGFloat = 50
    
    var body: some View {
        ZStack(alignment: .trailing) {
            // Background Buttons
            HStack(spacing: 0) {
                Spacer()
                
                // Upload
                Button(action: {
                    withAnimation { offset = 0; isSwiped = false }
                    onUpload()
                }) {
                    VStack(spacing: 2) {
                        Image(systemName: "icloud.and.arrow.up")
                            .font(.system(size: 16, weight: .bold))
                        Text("SYNC")
                            .font(.system(size: 8, weight: .bold, design: .monospaced))
                    }
                    .foregroundColor(.white)
                    .frame(width: buttonWidth)
                    .frame(maxHeight: .infinity)
                    .background(Color.archiveAccent)
                    .overlay(PixelBorder(color: .white.opacity(0.2)))
                }
                
                // Export
                Button(action: {
                    withAnimation { offset = 0; isSwiped = false }
                    onExport()
                }) {
                    VStack(spacing: 2) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 16, weight: .bold))
                        Text("EXP")
                            .font(.system(size: 8, weight: .bold, design: .monospaced))
                    }
                    .foregroundColor(.white)
                    .frame(width: buttonWidth)
                    .frame(maxHeight: .infinity)
                    .background(Color.gray)
                    .overlay(PixelBorder(color: .white.opacity(0.2)))
                }
                
                // Delete
                Button(action: {
                    withAnimation { offset = 0; isSwiped = false }
                    onDelete()
                }) {
                    VStack(spacing: 2) {
                        Image(systemName: "trash")
                            .font(.system(size: 16, weight: .bold))
                        Text("DEL")
                            .font(.system(size: 8, weight: .bold, design: .monospaced))
                    }
                    .foregroundColor(.white)
                    .frame(width: buttonWidth)
                    .frame(maxHeight: .infinity)
                    .background(Color.archiveRed)
                    .overlay(PixelBorder(color: .white.opacity(0.2)))
                }
            }
            .padding(.vertical, 1)
            
            // Main Content
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top) {
                    // 寶可夢圖片區域
                    VStack(spacing: 4) {
                        ZStack {
                            // 背景色
                            Rectangle()
                                .fill(
                                    PokemonDisplayModel(
                                        id: pokemon.uid,
                                        pokedexId: pokemon.pokedexId,
                                        name: pokemon.name,
                                        nickname: pokemon.nickname,
                                        level: pokemon.level,
                                        currentHp: pokemon.currentHp,
                                        maxHp: pokemon.maxHp,
                                        isShiny: pokemon.isShiny,
                                        types: pokemon.types,
                                        caughtBall: pokemon.caughtBall
                                    ).typeColor.opacity(0.2)
                                )
                                .frame(width: 60, height: 60)
                                .overlay(PixelBorder(color: Color.archiveAccent.opacity(0.3)))
                            
                            // GIF
                            let gifUrlString = pokemon.isShiny 
                                ? "https://raw.githubusercontent.com/PokeAPI/sprites/master/sprites/pokemon/versions/generation-v/black-white/animated/shiny/\(pokemon.pokedexId).gif"
                                : "https://raw.githubusercontent.com/PokeAPI/sprites/master/sprites/pokemon/versions/generation-v/black-white/animated/\(pokemon.pokedexId).gif"

                            if let url = URL(string: gifUrlString) {
                                GifImage(url: url)
                                    .frame(width: 50, height: 50)
                            }
                        }
                        
                        // HP Bar
                        VStack(spacing: 1) {
                            GeometryReader { geometry in
                                ZStack(alignment: .leading) {
                                    Rectangle()
                                        .fill(Color.gray.opacity(0.3))
                                    
                                    Rectangle()
                                        .fill(Double(pokemon.currentHp) / Double(pokemon.maxHp) > 0.5 ? Color.green : (Double(pokemon.currentHp) / Double(pokemon.maxHp) > 0.2 ? Color.yellow : Color.red))
                                        .frame(width: geometry.size.width * CGFloat(pokemon.currentHp) / CGFloat(pokemon.maxHp))
                                }
                            }
                            .frame(height: 3)
                            .cornerRadius(1.5)
                        }
                        .frame(width: 60)
                    }
                    .padding(.trailing, 8)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("#\(String(format: "%03d", pokemon.pokedexId))")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundColor(.gray)
                        HStack{
                            Text(pokemon.nickname ?? pokemon.name)
                                .font(.system(size: 14, weight: .bold, design: .monospaced))
                                .foregroundColor(.archiveAccent)

                            Text("Lv.\(pokemon.level)")
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundColor(.archiveGold)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.archiveGold.opacity(0.1))
                                .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.archiveGold.opacity(0.3), lineWidth: 1))
                        }
                        
                        HStack(spacing: 4) {
                            ForEach(pokemon.types, id: \.self) { type in
                                Text(type)
                                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(
                                        PokemonDisplayModel(
                                            id: pokemon.uid,
                                            pokedexId: pokemon.pokedexId,
                                            name: pokemon.name,
                                            nickname: pokemon.nickname,
                                            level: pokemon.level,
                                            currentHp: pokemon.currentHp,
                                            maxHp: pokemon.maxHp,
                                            isShiny: pokemon.isShiny,
                                            types: pokemon.types,
                                            caughtBall: pokemon.caughtBall
                                        ).typeColor
                                    )
                                    .overlay(PixelBorder(color: Color.gray.opacity(0.5)))
                            }
                            Spacer()
                        }
                    }
                    
                    Spacer()
                    
                    VStack(alignment: .trailing, spacing: 4) {
                        if pokemon.isShiny {
                            HStack(spacing: 2) {
                                Image(systemName: "star.fill")
                                Text("SHINY")
                            }
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundColor(.archiveGold)
                        }
                    }
                }
                
                // 基本資訊與標籤
                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 6) {

                        Text("UID: \(pokemon.uid)")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(isPressingUID ? .archiveAccent : .gray)
                            .scaleEffect(isPressingUID ? 1.1 : 1.0)
                            .shadow(color: isPressingUID ? .archiveAccent.opacity(0.8) : .clear, radius: 2)
                            .lineLimit(1)
                            .onLongPressGesture(minimumDuration: 0.5, pressing: { pressing in
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    isPressingUID = pressing
                                }
                            }, perform: {
                                onCopyUID()
                            })
                        
                        
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                // Gender
                                if !pokemon.gender.isEmpty {
                                    Text("#\(pokemon.gender)")
                                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                                        .foregroundColor(.archiveSecondary)
                                }
                                
                                // Nature
                                if !pokemon.nature.isEmpty {
                                    Text("#\(pokemon.nature)")
                                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                                        .foregroundColor(.archiveSecondary)
                                }
                                
                                // Ability
                                if !pokemon.ability.isEmpty {
                                    Text("#\(pokemon.ability)")
                                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                                        .foregroundColor(.archiveSecondary)
                                }
                                
                                // Item
                                if let item = pokemon.heldItem, !item.isEmpty {
                                    Text("#\(item)")
                                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                                        .foregroundColor(.archiveGold)
                                }
                            }
                        }
                    }
                    
                    Spacer()
                    
                    // Status Icon
                    Image(systemName: pokemon.isSynced ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundColor(pokemon.isSynced ? .green : .red)
                }
            }
            .padding(12)
            .background(Color.archiveCard)
            .overlay(PixelBorder(color: Color.archiveAccent.opacity(0.3)))
            .offset(x: offset)
            .gesture(
                DragGesture()
                    .onChanged { value in
                        if value.translation.width < 0 {
                            offset = value.translation.width
                        } else if isSwiped && value.translation.width > 0 {
                             offset = (-buttonWidth * 3) + value.translation.width
                             if offset > 0 { offset = 0 }
                        }
                    }
                    .onEnded { value in
                        withAnimation(.spring()) {
                            if value.translation.width < -buttonWidth {
                                offset = -buttonWidth * 3
                                isSwiped = true
                            } else {
                                offset = 0
                                isSwiped = false
                            }
                        }
                    }
            )
        }
    }
}
