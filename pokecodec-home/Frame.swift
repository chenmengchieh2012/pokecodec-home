import SwiftUI
import WebKit

// MARK: - 核心像素 UI 元件

/// 顯示 GIF 圖片的 View (使用 WKWebView)
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


/// 寶可夢網格卡片：強化像素感與背景深度
struct PixelPokemonGridCard: View {
    let pokemon: PokemonDisplayModel
    
    var body: some View {
        VStack(spacing: 0) {
            // 圖像顯示區：包含背景色、精靈球浮水印與寶可夢 GIF
            ZStack {
                // 1. 最底層：根據屬性決定的背景顏色
                Rectangle()
                    .fill(pokemon.typeColor.opacity(0.2))
                
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
                
                // 3. 最上層：寶可夢主體 GIF (優先顯示 GIF，若無則顯示靜態圖)
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
                
                // 4. 異色標記 (移至右上角)
                if pokemon.isShiny {
                    VStack {
                        HStack {
                            Spacer()
                            Image(systemName: "sparkles")
                                .font(.system(size: 12))
                                .foregroundColor(.archiveGold)
                                .shadow(color: .black.opacity(0.5), radius: 1, x: 1, y: 1)
                        }
                        Spacer()
                    }
                    .padding(6)
                }
            }
            .frame(height: 100)
            .clipped() // 確保內容不會超出這一格
            
            // 資訊區域：名字、等級、血條、數值
            VStack(spacing: 6) {
                // 第一排：名字 (左) + 等級 (右)
                HStack {
                    Text(pokemon.displayName.uppercased())
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .foregroundColor(.archiveAccent)
                        .lineLimit(1)
                    Spacer()
                    Text("Lv.\(pokemon.level)")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(.archiveGold)
                }
                
                // 第二排：血條
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Rectangle().fill(Color.black.opacity(0.6))
                        let ratio = CGFloat(pokemon.currentHp) / CGFloat(pokemon.maxHp)
                        // 血量顏色邏輯：>50% 綠色, >20% 黃色, <20% 紅色
                        Rectangle()
                            .fill(ratio > 0.5 ? Color.archiveGreen : (ratio > 0.2 ? Color.archiveGold : Color.archiveRed))
                            .frame(width: max(0, geo.size.width * ratio))
                    }
                }
                .frame(height: 6)
                .overlay(Rectangle().stroke(Color.white.opacity(0.2), lineWidth: 1))
                
                // 第三排：HP 數值
                Text("\(pokemon.currentHp)/\(pokemon.maxHp)")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundColor(.gray)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .padding(8)
            .background(Color.black.opacity(0.3))
        }
        .background(Color.archiveCard)
        .overlay(PixelBorder(color: .white.opacity(0.15)))
        .shadow(color: .black.opacity(0.4), radius: 0, x: 4, y: 4)
    }
}

/// 設備行元件：顯示設備名稱與 TOTP 驗證碼
struct PixelTerminalRow: View {
    let device: ConnectedDevice
    let timeRemaining: Int
    let totpManager: TOTPManager // 傳入 Manager 以便即時計算
    let onEdit: () -> Void // 編輯回調
    let onDelete: () -> Void // 刪除回調
    @State private var codeWidth: CGFloat = 100
    
    // Swipe state
    @State private var offset: CGFloat = 0
    @State private var isSwiped = false
    private let buttonWidth: CGFloat = 60
    
    // 計算當前的 TOTP 驗證碼
    var code: String {
        // 確保 secret 是有效的 Base32 字串
        // 注意：這裡假設 device.secret 已經是 Base32 格式的字串
        // 如果它是 Base64 編碼的，需要先解碼
        
        // 嘗試 1: 直接視為 Base32 字串
        if let code = totpManager.generateCode(secretBase32: device.secret) {
            return code
        }
        
        // 嘗試 2: 如果是 Base64 編碼的 Secret (相容舊資料)
        if let data = Data(base64Encoded: device.secret),
           let secretString = String(data: data, encoding: .utf8),
           let code = totpManager.generateCode(secretBase32: secretString) {
            return code
        }
        
        return "ERROR"
    }
    
    var body: some View {
        ZStack(alignment: .leading) {
            // 背景按鈕層
            HStack(spacing: 0) {
                // 編輯按鈕
                Button(action: {
                    withAnimation { offset = 0; isSwiped = false }
                    onEdit()
                }) {
                    VStack(spacing: 4) {
                        Image(systemName: "pencil")
                            .font(.system(size: 18, weight: .bold))
                        Text("EDIT")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                    }
                    .foregroundColor(.white)
                    .frame(width: buttonWidth)
                    .frame(maxHeight: .infinity)
                    .background(Color.gray)
                    .overlay(PixelBorder(color: .white.opacity(0.2)))
                }
                
                // 刪除按鈕
                Button(action: {
                    withAnimation { offset = 0; isSwiped = false }
                    onDelete()
                }) {
                    VStack(spacing: 4) {
                        Image(systemName: "trash")
                            .font(.system(size: 18, weight: .bold))
                        Text("DEL")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                    }
                    .foregroundColor(.white)
                    .frame(width: buttonWidth)
                    .frame(maxHeight: .infinity)
                    .background(Color.archiveRed)
                    .overlay(PixelBorder(color: .white.opacity(0.2)))
                }
                
                Spacer()
            }
            .padding(.vertical, 1) // 微調以配合邊框
            
            // 主要內容層
            HStack(spacing: 16) {
                // 設備名稱
                Text(device.name.uppercased())
                    .font(.system(size: 20, weight: .black, design: .monospaced))
                    .foregroundColor(.archiveAccent)
                    .frame(maxWidth: .infinity, alignment: .leading)
                
                // 驗證碼與倒數計時條
                VStack(alignment: .trailing, spacing: 2) {
                    Text(code)
                        .font(.system(size: 26, weight: .black, design: .monospaced))
                        .kerning(3)
                        .foregroundColor(.archiveAccent)
                        .shadow(color: Color.archiveAccent.opacity(0.3), radius: 2, x: 0, y: 0)
                        .background(GeometryReader { geo in
                            Color.clear.preference(key: WidthPreferenceKey.self, value: geo.size.width)
                        })
                    
                    // 倒數計時條 (Progress Bar)
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
            .offset(x: offset)
            .gesture(
                DragGesture()
                    .onChanged { value in
                        // 限制只能向右滑動
                        if value.translation.width > 0 {
                            offset = value.translation.width
                        } else if isSwiped && value.translation.width < 0 {
                             // 如果已經滑開，允許向左滑回來
                             offset = (buttonWidth * 2) + value.translation.width
                             if offset < 0 { offset = 0 }
                        }
                    }
                    .onEnded { value in
                        withAnimation(.spring()) {
                            if value.translation.width > buttonWidth {
                                offset = buttonWidth * 2
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

/// 寬度測量 PreferenceKey
struct WidthPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

/// 像素風格圖示按鈕
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

/// 小型像素風格圖示按鈕
struct PixelIconSmallButton: View {
    let icon: String
    let color: Color
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(color)
                .frame(width: 28, height: 28)
                .background(Color.archiveCard)
                .overlay(PixelBorder(color: color.opacity(0.5)))
                .shadow(color: .black, radius: 0, x: 1, y: 1)
        }
    }
}

/// 掃描線覆蓋層：模擬 CRT 螢幕效果
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

/// 空狀態視圖：當沒有綁定設備時顯示
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

/// 空插槽視圖：用於填補網格中的空白位置
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

/// 區塊標題元件
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
/// 匯出資料彈窗
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

/// 設備設定彈窗
struct DeviceConfigPopup: View {
    @Binding var isShowing: Bool
    @Binding var deviceName: String
    var onSave: () -> Void
    var onCancel: () -> Void
    
    var body: some View {
        ZStack {
            Color.black.opacity(0.6).ignoresSafeArea()
                .onTapGesture { onCancel() }
            
            VStack(spacing: 20) {
                Text("DEVICE CONFIG")
                    .font(.system(size: 16, weight: .black, design: .monospaced))
                    .foregroundColor(.white)
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("TERMINAL NAME")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(.gray)
                    
                    TextField("", text: $deviceName)
                        .font(.system(size: 14, design: .monospaced))
                        .foregroundColor(.white)
                        .padding(8)
                        .background(Color.black.opacity(0.3))
                        .overlay(PixelBorder(color: .gray.opacity(0.5)))
                }
                
                HStack(spacing: 12) {
                    Button(action: onCancel) {
                        Text("CANCEL")
                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(Color.gray.opacity(0.3))
                            .overlay(PixelBorder(color: .white.opacity(0.2)))
                    }
                    
                    Button(action: onSave) {
                        Text("SAVE")
                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                            .foregroundColor(.black)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(Color.archiveAccent)
                            .overlay(PixelBorder(color: .white.opacity(0.5)))
                    }
                }
            }
            .padding(24)
            .background(Color.archiveCard)
            .overlay(PixelBorder(color: .archiveAccent))
            .padding(.horizontal, 40)
        }
    }
}
