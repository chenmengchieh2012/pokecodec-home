import SwiftUI
import VisionKit


/// 掃描器頁面：用於掃描 QR Code 綁定設備
struct ScannerSheet: View {
    @Binding var isShowing: Bool
    let onScan: (String) -> Void
    
    var body: some View {
        ZStack {
            // 背景：深色系 LCD 質感
            Color.archiveBG.ignoresSafeArea()
            ScanlineOverlay().opacity(0.1).ignoresSafeArea()
            
            VStack(spacing: 0) {
                // 標題列
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
                
                // 掃描器容器
                ZStack {
                    // 掃描器相機畫面
                    ScannerView(isScanning: $isShowing, onScanResult: onScan)
                        .clipShape(RoundedRectangle(cornerRadius: 0))
                        .overlay(PixelBorder(color: Color.archiveAccent.opacity(0.3)))
                    
                    // 觀景窗覆蓋層 (Viewfinder)
                    ZStack {
                        Rectangle()
                            .stroke(Color.archiveAccent.opacity(0.5), style: StrokeStyle(lineWidth: 2, dash: [10]))
                            .padding(10)
                        
                        // 四個角落的括號裝飾
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
                
                // 底部提示文字
                Text("ALIGN QR CODE WITHIN FRAME")
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.5))
                    .padding(.bottom, 30)
            }
        }
    }
}




/// 角落括號裝飾：用於觀景窗四角
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
