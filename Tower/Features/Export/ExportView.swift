import SwiftUI
import UIKit

struct ExportView: View {
    @Environment(AppModel.self) private var model
    @State private var sharePayload: ExportPayload?
    @State private var directImportService = DirectImportService()
    @State private var isImporting = false

    var body: some View {
        let configuration = model.configuration()

        ScrollView {
            LazyVStack(spacing: 22) {
                ClientPicker()
                ProtocolFilter()
                ConversionSummary(configuration: configuration)
                ImportPrivacyNote(target: model.selectedTarget)
                ConfigurationPreview(configuration: configuration)
            }
            .padding(.horizontal, TowerTheme.pagePadding)
            .padding(.top, 12)
            .padding(.bottom, 18)
        }
        .background(TowerTheme.background.ignoresSafeArea())
        .navigationTitle("生成与导入")
        .safeAreaInset(edge: .bottom, spacing: 0) {
            ImportActionBar(
                target: model.selectedTarget,
                isImporting: isImporting,
                isDisabled: configuration.supportedNodeCount == 0,
                importAction: {
                    Task { await importConfiguration(configuration) }
                },
                shareAction: export,
                copyAction: { copy(configuration) }
            )
        }
        .sheet(item: $sharePayload) { payload in
            ActivitySheet(items: [payload.url])
                .presentationDetents([.medium, .large])
        }
        .sensoryFeedback(.selection, trigger: model.selectedTarget)
        // Deliberately no .onDisappear teardown. Handing the link to another
        // app backgrounds Tower, and SwiftUI may call onDisappear when it does
        // — which killed the server before the client had fetched. Hiddify
        // reported it as `Connection refused`. The 45-second timer and the
        // background-task expiry handler already bound the lifetime.
    }

    private func export() {
        do {
            sharePayload = ExportPayload(url: try model.makeExportURL())
        } catch {
            model.showToast("生成失败：\(error.localizedDescription)", symbol: "exclamationmark.triangle.fill")
        }
    }

    @MainActor
    private func importConfiguration(_ configuration: GeneratedConfiguration) async {
        guard !isImporting else { return }
        guard configuration.target.supportsDirectConfigurationImport else {
            export()
            return
        }

        isImporting = true
        defer { isImporting = false }

        do {
            let schemeURL = try await directImportService.prepare(configuration)
            let didOpen = await withCheckedContinuation { continuation in
                UIApplication.shared.open(schemeURL, options: [:]) { opened in
                    continuation.resume(returning: opened)
                }
            }

            if didOpen {
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                model.showToast("已交给 \(configuration.target.name) 导入", symbol: "arrow.up.forward.app.fill")
            } else {
                directImportService.stop()
                model.showToast("未找到 \(configuration.target.name)，请从分享列表选择", symbol: "exclamationmark.circle.fill")
                export()
            }
        } catch {
            directImportService.stop()
            model.showToast(error.localizedDescription, symbol: "exclamationmark.triangle.fill")
            export()
        }
    }

    private func copy(_ configuration: GeneratedConfiguration) {
        UIPasteboard.general.string = configuration.content
        model.showToast("配置已复制", symbol: "doc.on.doc.fill")
    }
}

private struct ExportPayload: Identifiable {
    let id = UUID()
    let url: URL
}

private struct ClientPicker: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeading(title: "目标客户端", detail: model.selectedTarget.subtitle)
            ScrollView(.horizontal) {
                LazyHStack(spacing: 12) {
                    ForEach(ClientTarget.allCases) { target in
                        Button {
                            guard model.selectedTarget != target else { return }
                            model.selectTarget(target)
                        } label: {
                            ClientTargetCard(target: target, isSelected: model.selectedTarget == target)
                        }
                        .buttonStyle(ResponsivePressButtonStyle())
                        .accessibilityIdentifier("client-\(target.rawValue)")
                    }
                }
                .scrollTargetLayout()
                .padding(.vertical, 4)
            }
            .scrollIndicators(.hidden)
            .scrollTargetBehavior(.viewAligned(limitBehavior: .always))
        }
    }
}

private struct ClientTargetCard: View {
    let target: ClientTarget
    let isSelected: Bool

    var body: some View {
        VStack(spacing: 8) {
            ClientAppIcon(target: target, size: 58)
                .overlay(alignment: .bottomTrailing) {
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(.white, Color.accentColor)
                            .background(.white, in: Circle())
                            .offset(x: 4, y: 4)
                    }
                }
            Text(target.name)
                .font(.caption.weight(isSelected ? .bold : .semibold))
                .foregroundStyle(isSelected ? Color.accentColor : .primary)
                .lineLimit(1)
                .minimumScaleFactor(0.78)
        }
        .frame(width: 82, height: 94)
        .padding(.horizontal, 7)
        .padding(.vertical, 9)
        .background(isSelected ? Color.accentColor.opacity(0.105) : Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(isSelected ? Color.accentColor.opacity(0.75) : Color.secondary.opacity(0.13), lineWidth: isSelected ? 1.5 : 0.7)
        }
        .scaleEffect(isSelected ? 1 : 0.97)
        .animation(.easeOut(duration: 0.16), value: isSelected)
    }
}

private struct ClientAppIcon: View {
    let target: ClientTarget
    let size: CGFloat

    var body: some View {
        // Clients with no bundled artwork fall back to their symbol. A missing
        // asset renders as a blank square, which reads as a broken icon rather
        // than as an icon we simply do not ship.
        Group {
            if let asset = target.appIconAssetName {
                Image(asset)
                    .resizable()
                    .interpolation(.high)
                    .antialiased(true)
                    .scaledToFill()
            } else {
                Image(systemName: target.symbol)
                    .font(.system(size: size * 0.52))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: size, height: size)
                    .background(Color.accentColor.opacity(0.12))
            }
        }
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                    .stroke(.black.opacity(0.075), lineWidth: 0.65)
            }
            .shadow(color: .black.opacity(0.09), radius: 5, y: 2)
            .accessibilityHidden(true)
    }
}

/// A client can support a protocol the user's licence does not cover — Surge
/// needs a paid tier for AnyTLS — and Tower cannot detect that, so the choice
/// is offered per client and only for protocols the nodes actually contain.
private struct ProtocolFilter: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let kinds = model.filterableKinds(for: model.selectedTarget)
        if kinds.count > 1 {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeading(title: "协议筛选", detail: "只影响 \(model.selectedTarget.name)")
                VStack(spacing: 0) {
                    ForEach(Array(kinds.enumerated()), id: \.element.kind) { index, entry in
                        if index > 0 { Divider().padding(.leading, 16) }
                        Toggle(isOn: binding(for: entry.kind)) {
                            HStack(spacing: 10) {
                                Image(systemName: entry.kind.symbol)
                                    .font(.subheadline)
                                    .foregroundStyle(Color.accentColor)
                                    .frame(width: 24)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(entry.kind.title)
                                        .font(.subheadline.weight(.medium))
                                    Text("\(entry.count) 个节点")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 11)
                        .accessibilityIdentifier("filter-\(entry.kind.rawValue)")
                    }
                }
                .towerCard()
                Text("关掉的协议不会写进 \(model.selectedTarget.name) 的配置，并计入“已跳过”。其他客户端不受影响。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func binding(for kind: ProxyKind) -> Binding<Bool> {
        Binding(
            get: { !model.isExcluded(kind, for: model.selectedTarget) },
            set: { model.setExcluded(!$0, kind: kind, for: model.selectedTarget) }
        )
    }
}

private struct ConversionSummary: View {
    @Environment(AppModel.self) private var model
    let configuration: GeneratedConfiguration

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 5) {
                    Text("转换已就绪")
                        .font(.title3.weight(.semibold))
                    Text("\(model.selectedPreset.name) · \(model.selectedTarget.name)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: configuration.supportedNodeCount > 0 ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                    .font(.title2)
                    .foregroundStyle(configuration.supportedNodeCount > 0 ? .green : .orange)
            }
            HStack(spacing: 16) {
                MetricPill(value: "\(configuration.supportedNodeCount)", label: "兼容节点")
                Divider().frame(height: 38)
                MetricPill(value: configuration.ruleCount.formatted(), label: "本地规则")
                Divider().frame(height: 38)
                MetricPill(value: "\(configuration.skippedNodeCount)", label: "已跳过")
            }
            if configuration.skippedNodeCount > 0 {
                Label(
                    "目标客户端不支持、或你在协议筛选里关掉的节点不会写入配置，原节点仍保留在塔台中。",
                    systemImage: "info.circle.fill"
                )
                .font(.caption)
                .foregroundStyle(.orange)
            }
        }
        .padding(20)
        .towerCard()
    }
}

private struct ConfigurationPreview: View {
    let configuration: GeneratedConfiguration
    @State private var showsFullPreview = false

    private var preview: String {
        ConfigurationPreviewFormatter.summary(from: configuration.content)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeading(title: "配置预览", detail: configuration.fileName)
            ConfigurationTextView(text: preview)
                .frame(height: 220)
                .background(Color.black.opacity(0.045), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

            Button {
                showsFullPreview = true
            } label: {
                Label("全屏预览", systemImage: "arrow.up.left.and.arrow.down.right")
            }
            .font(.subheadline.weight(.semibold))
        }
        .padding(16)
        .towerCard()
        .sheet(isPresented: $showsFullPreview) {
            ConfigurationPreviewSheet(configuration: configuration)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
    }
}

private struct ConfigurationPreviewSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let configuration: GeneratedConfiguration

    var body: some View {
        NavigationStack {
            ConfigurationTextView(text: configuration.content)
                .background(Color(uiColor: .secondarySystemBackground))
                .navigationTitle(configuration.target.name)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("完成") { dismiss() }
                    }
                    ToolbarItem(placement: .primaryAction) {
                        Button("复制", systemImage: "doc.on.doc") {
                            UIPasteboard.general.string = configuration.content
                            model.showToast("配置已复制", symbol: "doc.on.doc.fill")
                        }
                    }
                }
        }
    }
}

private struct ImportPrivacyNote: View {
    let target: ClientTarget

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 10) {
                ClientAppIcon(target: target, size: 34)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(.green)
                    Text(target.name)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                }
            }
            Text(detail)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .background(.green.opacity(0.075), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var title: String {
        target.supportsDirectConfigurationImport ? "本机一键导入" : "使用本地文件导入"
    }

    private var detail: String {
        if target.supportsDirectConfigurationImport {
            return "塔台会通过 \(target.name) 的 URL Scheme 打开客户端。配置只在这台 iPhone 的 127.0.0.1 临时地址保留 45 秒，不会上传；需要更新时回到塔台再次导入。"
        }
        return "Quantumult X 目前没有公开完整配置导入的 URL Scheme。点击下方按钮会立即打开系统文件分享，不上传你的订阅，也不会用不完整的远程资源替代本地规则。"
    }
}

private struct ImportActionBar: View {
    let target: ClientTarget
    let isImporting: Bool
    let isDisabled: Bool
    let importAction: () -> Void
    let shareAction: () -> Void
    let copyAction: () -> Void

    var body: some View {
        HStack(spacing: 11) {
            Button(action: importAction) {
                HStack(spacing: 9) {
                    if isImporting {
                        ProgressView()
                            .tint(.white)
                    } else {
                        ClientAppIcon(target: target, size: 27)
                    }
                    Text(target.primaryImportTitle)
                        .font(.headline)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
                .foregroundStyle(.white)
                .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(ResponsivePressButtonStyle())
            .disabled(isDisabled || isImporting)
            .accessibilityIdentifier("export-config")

            Menu {
                Button("分享配置文件", systemImage: "square.and.arrow.up", action: shareAction)
                Button("复制配置文本", systemImage: "doc.on.doc", action: copyAction)
            } label: {
                Image(systemName: "ellipsis")
                    .font(.headline)
                    .frame(width: 50, height: 50)
                    .background(Color.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(ResponsivePressButtonStyle())
            .disabled(isDisabled || isImporting)
            .accessibilityLabel("其他导入方式")
        }
        .padding(.horizontal, TowerTheme.pagePadding)
        .padding(.top, 11)
        .padding(.bottom, 9)
        .background(.bar)
        .overlay(alignment: .top) {
            Divider().opacity(0.45)
        }
    }
}
