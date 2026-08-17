import SwiftUI
import UIKit

struct ExportView: View {
    @Environment(AppModel.self) private var model
    @State private var sharePayload: ExportPayload?
    @State private var directImportService = DirectImportService()
    @State private var isImporting = false
    @State private var isSettingsPresented = false
    @State private var configurationNameDraft = ConfigurationNameDraft()
    @State private var previewPayload: ConfigurationPreviewPayload?

    var body: some View {
        let configuration = model.configuration()

        ScrollView {
            LazyVStack(spacing: 22) {
                ClientPicker()
                ExportContentModePicker()
                if configuration.contentMode != .rulesOnly {
                    ProtocolFilter()
                }
                ConversionSummary(configuration: configuration)
                ImportPrivacyNote(
                    target: model.selectedTarget,
                    contentMode: model.exportContentMode(for: model.selectedTarget)
                )
                ConfigurationPreview(configuration: configuration) {
                    previewPayload = ConfigurationPreviewPayload(configuration: configuration)
                }
            }
            .padding(.horizontal, TowerTheme.pagePadding)
            .padding(.top, 12)
            .padding(.bottom, 18)
        }
        .background(TowerTheme.background.ignoresSafeArea())
        .navigationTitle("生成与导出")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    configurationNameDraft = ConfigurationNameDraft(text: model.configurationName)
                    isSettingsPresented = true
                } label: {
                    Label("设置", systemImage: "gearshape")
                }
                .accessibilityIdentifier("open-settings")
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            ImportActionBar(
                target: model.selectedTarget,
                contentMode: configuration.contentMode,
                isImporting: isImporting,
                isDisabled: configuration.contentMode == .rulesOnly
                    ? configuration.ruleCount == 0
                    : configuration.supportedNodeCount == 0,
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
        .sheet(isPresented: $isSettingsPresented) {
            ExportSettingsSheet(configurationNameDraft: $configurationNameDraft)
        }
        // "完成" is not the only way out of that sheet — it can also be dragged
        // down — and a name typed but never committed is simply lost. Catching
        // the flag covers every path; committing twice is harmless because the
        // draft is the same either way.
        .onChange(of: isSettingsPresented) { _, isPresented in
            guard !isPresented else { return }
            model.setConfigurationName(configurationNameDraft.committedName)
        }
        .fullScreenCover(item: $previewPayload) { payload in
            ConfigurationPreviewSheet(configuration: payload.configuration)
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
            model.showToast(String(localized: "生成失败：\(error.localizedDescription)"), symbol: "exclamationmark.triangle.fill")
        }
    }

    @MainActor
    private func importConfiguration(_ configuration: GeneratedConfiguration) async {
        guard !isImporting else { return }
        guard configuration.target.supportsDirectImport(mode: configuration.contentMode) else {
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
                model.showToast(String(localized: "已交给 \(configuration.target.name) 导入"), symbol: "arrow.up.forward.app.fill")
            } else {
                directImportService.stop()
                model.showToast(String(localized: "未找到 \(configuration.target.name)，请从分享列表选择"), symbol: "exclamationmark.circle.fill")
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
        model.showToast(String(localized: "配置已复制"), symbol: "doc.on.doc.fill")
    }
}

private struct ExportContentModePicker: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if model.selectedTarget.supportsNodesOnlyImport {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeading(title: "导出内容", detail: model.selectedTarget.name)
                Picker(
                    "导出内容",
                    selection: Binding(
                        get: { model.exportContentMode(for: model.selectedTarget) },
                        set: { model.setExportContentMode($0, for: model.selectedTarget) }
                    )
                ) {
                    ForEach(model.selectedTarget.supportedContentModes) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("export-content-mode")

                Text(modeExplanation)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(16)
            .towerCard()
        }
    }

    private var modeExplanation: String {
        switch model.exportContentMode(for: model.selectedTarget) {
        case .nodesOnly:
            return String(localized: "只添加节点订阅，不替换客户端现有的规则和策略组。")
        case .rulesOnly:
            return String(localized: "导出节点、规则和策略组组成的完整配置。")
        case .fullConfiguration:
            return String(localized: "导出节点、规则和策略组组成的完整配置。")
        }
    }
}

private struct ExportSettingsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppModel.self) private var model
    @Binding var configurationNameDraft: ConfigurationNameDraft

    var body: some View {
        NavigationStack {
            SettingsView(configurationNameDraft: $configurationNameDraft)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("完成") {
                            model.setConfigurationName(configurationNameDraft.committedName)
                            dismiss()
                        }
                    }
                }
                .towerToast()
        }
    }
}

private struct ExportPayload: Identifiable {
    let id = UUID()
    let url: URL
}

private struct ConfigurationPreviewPayload: Identifiable {
    let id = UUID()
    let configuration: GeneratedConfiguration
}

private struct ClientPicker: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeading(title: "目标客户端", detail: String(localized: "长按拖动排序"))
            ScrollView(.horizontal) {
                HStack(spacing: 12) {
                    ForEach(model.clientOrder) { target in
                        Button {
                            guard model.selectedTarget != target else { return }
                            model.selectTarget(target)
                        } label: {
                            ClientTargetCard(target: target, isSelected: model.selectedTarget == target)
                        }
                        .buttonStyle(ResponsivePressButtonStyle())
                        .accessibilityIdentifier("client-\(target.rawValue)")
                        .draggable(target.rawValue)
                        .dropDestination(for: String.self) { values, _ in
                            guard let rawValue = values.first,
                                  let source = ClientTarget(rawValue: rawValue) else { return false }
                            model.moveClient(source, before: target)
                            return true
                        }
                        .accessibilityAction(named: "向前移动") {
                            model.moveClient(target, by: -1)
                        }
                        .accessibilityAction(named: "向后移动") {
                            model.moveClient(target, by: 1)
                        }
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
        Group {
            if let asset = target.appIconAssetName {
                Image(asset)
                    .resizable()
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

enum ProtocolFilterPolicy {
    static func isVisible(compatibleKindCount: Int) -> Bool {
        compatibleKindCount > 0
    }
}

/// A client can support a protocol the user's licence does not cover — Surge
/// needs a paid tier for AnyTLS — and Tower cannot detect that, so the choice
/// is offered per client and only for protocols the nodes actually contain.
private struct ProtocolFilter: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let kinds = model.filterableKinds(for: model.selectedTarget)
        if ProtocolFilterPolicy.isVisible(compatibleKindCount: kinds.count) {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeading(title: "协议筛选", detail: String(localized: "只影响 \(model.selectedTarget.name)"))
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
                    Text(summarySubtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: configuration.supportedNodeCount > 0 ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                    .font(.title2)
                    .foregroundStyle(configuration.supportedNodeCount > 0 ? .green : .orange)
            }
            HStack(spacing: 16) {
                MetricPill(
                    value: configuration.supportedNodeCount,
                    label: configuration.contentMode == .rulesOnly ? "本地规则" : "兼容节点"
                )
                Divider().frame(height: 38)
                MetricPill(value: configuration.ruleCount, label: "本地规则")
                Divider().frame(height: 38)
                MetricPill(value: configuration.skippedNodeCount, label: "已跳过")
            }
            if configuration.skippedNodeCount > 0 {
                Label(
                    "目标客户端不支持、或您在协议筛选里关掉的节点不会写入配置，原节点仍保留在塔台中。",
                    systemImage: "info.circle.fill"
                )
                .font(.caption)
                .foregroundStyle(.orange)
            }
        }
        .padding(20)
        .towerCard()
    }

    private var summarySubtitle: String {
        switch configuration.contentMode {
        case .nodesOnly:
            String(localized: "仅节点 · \(model.selectedTarget.name)")
        case .rulesOnly:
            String(localized: "本地规则")
        case .fullConfiguration:
            "\(model.activeRuleName) · \(model.selectedTarget.name)"
        }
    }
}

private struct ConfigurationPreview: View {
    let configuration: GeneratedConfiguration
    let onOpen: () -> Void

    private var preview: String {
        ConfigurationPreviewFormatter.summary(from: configuration.content)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeading(title: "配置预览", detail: configuration.fileName)
            ConfigurationSummaryView(text: preview)
                .frame(height: 220)
                .background(Color.black.opacity(0.045), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

            Button(action: onOpen) {
                Label("全屏预览", systemImage: "arrow.up.left.and.arrow.down.right")
            }
            .font(.subheadline.weight(.semibold))
        }
        .padding(16)
        .towerCard()
    }
}

private struct ConfigurationPreviewSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let configuration: GeneratedConfiguration
    @State private var isContentReady = false

    var body: some View {
        NavigationStack {
            Group {
                if isContentReady {
                    ConfigurationTextView(text: configuration.content)
                } else {
                    ProgressView("正在加载完整配置…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
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
                        model.showToast(String(localized: "配置已复制"), symbol: "doc.on.doc.fill")
                    }
                }
            }
            .task {
                await Task.yield()
                isContentReady = true
            }
        }
    }
}

private struct ImportPrivacyNote: View {
    let target: ClientTarget
    let contentMode: ExportContentMode

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
        target.supportsDirectImport(mode: contentMode)
            ? String(localized: "本机一键导出")
            : String(localized: "使用本地文件导出")
    }

    private var detail: String {
        if contentMode == .nodesOnly {
            return String(localized: "塔台只会把节点订阅交给 \(target.name)，不会替换客户端现有的规则和策略组。订阅保留在这台 iPhone 的临时地址，不会上传。")
        }
        if contentMode == .rulesOnly {
            return String(localized: "导出节点、规则和策略组组成的完整配置。")
        }
        if target.supportsDirectConfigurationImport {
            return String(localized: "塔台会通过 \(target.name) 的 URL Scheme 打开客户端。配置只在这台 iPhone 的 127.0.0.1 临时地址保留 45 秒，不会上传；需要更新时回到塔台再次导入。")
        }
        return String(localized: "Quantumult X 目前没有公开完整配置导入的 URL Scheme。点击下方按钮会立即打开系统文件分享，不上传您的订阅，也不会用不完整的远程资源替代本地规则。")
    }
}

private struct ImportActionBar: View {
    let target: ClientTarget
    let contentMode: ExportContentMode
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
                    Text(importTitle)
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

    private var importTitle: String {
        switch contentMode {
        case .nodesOnly:
            return String(localized: "仅导出节点到 \(target.name)")
        case .rulesOnly:
            return String(localized: "本地规则")
        case .fullConfiguration:
            return target.primaryImportTitle
        }
    }
}
