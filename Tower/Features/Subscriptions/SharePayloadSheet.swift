import CoreImage
import CoreImage.CIFilterBuiltins
import SwiftUI
import UIKit

struct SharePayloadSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let payload: SharePayload
    @State private var copied = false
    @State private var qrImage: UIImage?
    @State private var qrFileURL: URL?
    @State private var qrGenerationFailed = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    VStack(spacing: 8) {
                        if let kind = payload.protocolKind {
                            ProtocolGlyph(kind: kind, size: 24)
                                .foregroundStyle(Color.accentColor)
                        } else {
                            Image(systemName: payload.symbol)
                                .font(.title2.weight(.semibold))
                                .foregroundStyle(Color.accentColor)
                        }
                        Text(payload.title)
                            .font(.title3.weight(.semibold))
                            .multilineTextAlignment(.center)
                        Text(payload.detail)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    qrCode

                    Text(payload.value)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14)
                        .background(Color.primary.opacity(0.055), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                    HStack(spacing: 10) {
                        shareAction(
                            title: copied ? String(localized: "已复制") : String(localized: "复制链接"),
                            symbol: copied ? "checkmark" : "doc.on.doc"
                        ) {
                            UIPasteboard.general.string = payload.value
                            copied = true
                        }

                        ShareLink(item: payload.value) {
                            shareActionLabel(title: String(localized: "分享链接"), symbol: "square.and.arrow.up")
                        }
                        .buttonStyle(ResponsivePressButtonStyle())

                        if let qrFileURL {
                            ShareLink(item: qrFileURL) {
                                shareActionLabel(title: String(localized: "分享二维码"), symbol: "qrcode")
                            }
                            .buttonStyle(ResponsivePressButtonStyle())
                        } else {
                            shareAction(title: String(localized: "分享二维码"), symbol: "qrcode") {}
                                .disabled(true)
                        }
                    }

                    Label("链接可能包含访问凭据，请只分享给可信设备。", systemImage: "lock.shield")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(20)
            }
            .background(TowerTheme.background.ignoresSafeArea())
            .navigationTitle("分享")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
            .task(id: payload.id) { await renderQRCode() }
            .sensoryFeedback(.success, trigger: copied)
        }
        .presentationDetents([.large])
    }

    @ViewBuilder
    private var qrCode: some View {
        ZStack {
            if let qrImage {
                Image(uiImage: qrImage)
                    .resizable()
                    .interpolation(.none)
                    .scaledToFit()
                    .frame(width: 230, height: 230)
                    .padding(15)
                    .background(.white, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .shadow(color: .black.opacity(0.08), radius: 18, y: 8)
                    .accessibilityLabel("\(payload.title) 的二维码")
                    .transition(.opacity)
            } else if qrGenerationFailed {
                ContentUnavailableView("无法生成二维码", systemImage: "qrcode")
            } else {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("正在生成二维码")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
            }
        }
        .frame(height: 260)
    }

    private func shareAction(title: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            shareActionLabel(title: title, symbol: symbol)
        }
        .buttonStyle(ResponsivePressButtonStyle())
    }

    private func shareActionLabel(title: String, symbol: String) -> some View {
        VStack(spacing: 7) {
            Image(systemName: symbol)
                .font(.headline)
            Text(title)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
    }

    @MainActor
    private func renderQRCode() async {
        qrGenerationFailed = false
        guard let artifact = await QRCodeShareArtifactBuilder.make(
            value: payload.value,
            id: payload.id
        ) else {
            guard !Task.isCancelled else { return }
            qrGenerationFailed = true
            return
        }
        guard !Task.isCancelled else { return }

        qrFileURL = artifact.fileURL
        if reduceMotion {
            qrImage = artifact.image
        } else {
            withAnimation(.easeOut(duration: 0.16)) {
                qrImage = artifact.image
            }
        }
    }
}

struct QRCodeShareArtifact: @unchecked Sendable {
    let image: UIImage
    let fileURL: URL
}

enum QRCodeShareArtifactBuilder {
    /// The rendered code encodes the full node link, so the PNG is as sensitive
    /// as the link itself: it is written with complete protection into a folder
    /// that is purged before each render instead of left in `tmp` forever.
    static let folderName = "TowerQRCodes"

    static func make(value: String, id: UUID) async -> QRCodeShareArtifact? {
        await Task.detached(priority: .userInitiated) {
            guard let rendered = QRCodeRenderer.render(value) else { return nil }
            let folder = FileManager.default.temporaryDirectory
                .appendingPathComponent(folderName, isDirectory: true)
            do {
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                ExportFileService().purge(in: folder)
                let url = folder.appendingPathComponent("Tower-QR-\(id.uuidString).png")
                try rendered.pngData.write(to: url, options: [.atomic, .completeFileProtection])
                return QRCodeShareArtifact(image: rendered.image, fileURL: url)
            } catch {
                return nil
            }
        }.value
    }
}

private enum QRCodeRenderer {
    private static let context = CIContext()

    static func render(_ value: String) -> (image: UIImage, pngData: Data)? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(value.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }

        let scaled = output.transformed(by: CGAffineTransform(scaleX: 12, y: 12))
        guard let cgImage = context.createCGImage(scaled, from: scaled.extent) else { return nil }
        let image = UIImage(cgImage: cgImage)
        guard let pngData = image.pngData() else { return nil }
        return (image, pngData)
    }
}
