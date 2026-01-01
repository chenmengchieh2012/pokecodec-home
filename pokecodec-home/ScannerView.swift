import SwiftUI
import VisionKit // 處理掃描 UI
import Vision    // 處理 QR Code 辨識邏輯

struct ScannerView: UIViewControllerRepresentable {
    @Binding var isScanning: Bool
    var onScanResult: (String) -> Void

    func makeUIViewController(context: Context) -> DataScannerViewController {
        // 初始化掃描器，指定只偵測 QR Code
        let scanner = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: [.qr])], // 這裡需要 import Vision
            qualityLevel: .balanced,
            isHighlightingEnabled: true
        )
        scanner.delegate = context.coordinator
        return scanner
    }

    func updateUIViewController(_ uiViewController: DataScannerViewController, context: Context) {
        if isScanning {
            try? uiViewController.startScanning()
        } else {
            uiViewController.stopScanning()
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, DataScannerViewControllerDelegate {
        var parent: ScannerView
        init(_ parent: ScannerView) { self.parent = parent }

        func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            for item in addedItems {
                if case .barcode(let barcode) = item, let result = barcode.payloadStringValue {
                    parent.onScanResult(result)
                    parent.isScanning = false // 掃描到就關閉視窗
                }
            }
        }
    }
}
