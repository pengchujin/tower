import SwiftUI
import VisionKit
import UIKit
import AVFoundation

struct QRCodeScannerSheet: View {
    @Environment(\.dismiss) private var dismiss
    let onScan: (String) -> Void

    var body: some View {
        NavigationStack {
            QRCodeScannerPreview { value in
                onScan(value)
                dismiss()
            }
            .navigationTitle("扫描二维码")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } } }
        }
    }
}

struct QRCodeScannerPreview: View {
    @Environment(\.scenePhase) private var scenePhase
    let onScan: (String) -> Void
    @State private var failure: String?
    @State private var isRequestingPermission = true
    @State private var generation = UUID()
    @State private var isAvailable = DataScannerViewController.isSupported && DataScannerViewController.isAvailable

    var body: some View {
        VStack(spacing: 12) {
            if isRequestingPermission {
                ProgressView().frame(minHeight: 250)
            } else if isAvailable && failure == nil {
                QRCodeScannerView(onScan: onScan, onFailure: { failure = $0 })
                    .id(generation)
                    .frame(minHeight: 250)
            } else {
                ContentUnavailableView {
                    Label("无法使用相机扫码", systemImage: "camera.fill")
                } description: {
                    Text(failure ?? String(localized: "请检查相机权限，或切换到粘贴识别。"))
                } actions: {
                    Button("重试") { retry() }
                    Button("打开设置") {
                        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                        UIApplication.shared.open(url)
                    }
                }
                .frame(minHeight: 250)
            }
        }
        .frame(maxWidth: .infinity)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .task {
            if DataScannerViewController.isSupported, AVCaptureDevice.authorizationStatus(for: .video) == .notDetermined {
                _ = await AVCaptureDevice.requestAccess(for: .video)
            }
            guard !Task.isCancelled else { return }
            retry()
            isRequestingPermission = false
        }
        .onChange(of: scenePhase) { _, phase in if phase == .active { retry() } }
    }

    private func retry() {
        failure = nil
        generation = UUID()
        isAvailable = DataScannerViewController.isSupported && DataScannerViewController.isAvailable
    }
}

private struct QRCodeScannerView: UIViewControllerRepresentable {
    let onScan: (String) -> Void
    let onFailure: (String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onScan: onScan, onFailure: onFailure) }

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: [.qr])], qualityLevel: .balanced,
            recognizesMultipleItems: false, isHighFrameRateTrackingEnabled: false,
            isPinchToZoomEnabled: true, isGuidanceEnabled: true, isHighlightingEnabled: true
        )
        scanner.delegate = context.coordinator
        return scanner
    }

    func updateUIViewController(_ scanner: DataScannerViewController, context: Context) {
        guard !scanner.isScanning, !context.coordinator.hasDeliveredValue else { return }
        do { try scanner.startScanning() }
        catch {
            let report = onFailure
            Task { @MainActor in report(error.localizedDescription) }
        }
    }

    static func dismantleUIViewController(_ scanner: DataScannerViewController, coordinator: Coordinator) {
        scanner.stopScanning()
    }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        private let onScan: (String) -> Void
        private let onFailure: (String) -> Void
        private(set) var hasDeliveredValue = false

        init(onScan: @escaping (String) -> Void, onFailure: @escaping (String) -> Void) {
            self.onScan = onScan
            self.onFailure = onFailure
        }

        func dataScanner(_ scanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            guard !hasDeliveredValue else { return }
            for item in addedItems {
                guard case .barcode(let barcode) = item, let value = barcode.payloadStringValue else { continue }
                let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
                guard SourceInputDetector().detect(normalized).isSupported else { continue }
                hasDeliveredValue = true
                scanner.stopScanning()
                onScan(normalized)
                return
            }
        }

        func dataScanner(_ dataScanner: DataScannerViewController, becameUnavailableWithError error: DataScannerViewController.ScanningUnavailable) {
            onFailure(error.localizedDescription)
        }
    }
}
