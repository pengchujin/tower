import SwiftUI

struct RulesView: View {
    @Environment(AppModel.self) private var model
    @State private var isImportPresented = false
    @State private var pendingDeletion: RuleScheme?

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 22) {
                RulesOverviewCard()

                VStack(spacing: 12) {
                    SectionHeading(title: "默认规则", detail: "本地快照")
                    ForEach(RulePreset.builtIns) { preset in
                        RulePresetCard(
                            preset: preset,
                            isSelected: model.selectedPresetID == preset.id,
                            ruleCount: model.ruleCount(for: preset)
                        ) {
                            model.selectPreset(preset)
                        }
                    }
                }

                bundledSchemesSection
                importedSchemesSection

                Button {
                    isImportPresented = true
                } label: {
                    Label("导入规则链接", systemImage: "arrow.down.circle")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(ResponsivePressButtonStyle())
                .accessibilityIdentifier("import-rule-scheme")

                Button {
                    model.selectedTab = .export
                } label: {
                    PrimaryActionLabel(title: "继续选择客户端", symbol: "arrow.right")
                }
                .buttonStyle(ResponsivePressButtonStyle())
                .disabled(model.enabledNodes.isEmpty)
                .accessibilityIdentifier("continue-to-export")
            }
            .padding(.horizontal, TowerTheme.pagePadding)
            .padding(.top, 12)
            .padding(.bottom, 34)
        }
        .background(TowerTheme.background.ignoresSafeArea())
        .navigationTitle("分流规则")
        .sensoryFeedback(.selection, trigger: model.selectedPresetID)
        .sheet(isPresented: $isImportPresented) {
            ImportRuleSchemeSheet()
        }
        .confirmationDialog(
            pendingDeletion.map { "删除“\($0.name)”？" } ?? "确认删除",
            isPresented: Binding(
                get: { pendingDeletion != nil },
                set: { if !$0 { pendingDeletion = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("删除", role: .destructive) {
                if let pendingDeletion { model.deleteScheme(pendingDeletion) }
                pendingDeletion = nil
            }
            Button("取消", role: .cancel) { pendingDeletion = nil }
        } message: {
            Text("这个规则方案和它下载的规则列表会从这台设备移除。")
        }
    }

    @ViewBuilder
    private var bundledSchemesSection: some View {
        let schemes = model.ruleSchemes.filter(\.isBundled)
        if !schemes.isEmpty {
            VStack(spacing: 12) {
                SectionHeading(title: "ACL4SSR", detail: "随 App 打包")
                ForEach(schemes) { scheme in
                    RuleSchemeCard(
                        scheme: scheme,
                        isSelected: model.selectedPresetID == scheme.id,
                        ruleCount: model.ruleCount(for: scheme),
                        isRefreshing: false,
                        isReady: true,
                        onSelect: { model.selectScheme(scheme) },
                        onRefresh: nil,
                        onDelete: nil
                    )
                }
            }
        }
    }

    @ViewBuilder
    private var importedSchemesSection: some View {
        let schemes = model.ruleSchemes.filter { !$0.isBundled }
        if !schemes.isEmpty {
            VStack(spacing: 12) {
                SectionHeading(title: "已导入", detail: "\(schemes.count) 个方案")
                ForEach(schemes) { scheme in
                    RuleSchemeCard(
                        scheme: scheme,
                        isSelected: model.selectedPresetID == scheme.id,
                        ruleCount: model.ruleCount(for: scheme),
                        isRefreshing: model.importingSchemeIDs.contains(scheme.id),
                        isReady: model.isSchemeReady(scheme),
                        onSelect: { model.selectScheme(scheme) },
                        onRefresh: { Task { await model.refreshScheme(scheme) } },
                        onDelete: { pendingDeletion = scheme }
                    )
                }
            }
        }
    }
}

private struct RulesOverviewCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(title)
                        .font(.title2.weight(.bold))
                    Text(summary)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 14)
                Image(systemName: symbol)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 48, height: 48)
                    .background(
                        TowerTheme.color(named: tintName).gradient,
                        in: RoundedRectangle(cornerRadius: 15, style: .continuous)
                    )
            }
            HStack {
                Label("\(ruleCount.formatted()) 条规则", systemImage: "list.bullet.rectangle.portrait.fill")
                Spacer()
                Label(sourceName, systemImage: "shippingbox.fill")
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
        }
        .padding(20)
        .towerCard()
    }

    private var title: String { model.selectedScheme?.name ?? model.selectedPreset.name }
    private var summary: String { model.selectedScheme?.summary ?? model.selectedPreset.summary }
    private var symbol: String {
        model.selectedScheme == nil ? model.selectedPreset.symbol : "square.stack.3d.down.right.fill"
    }
    private var tintName: String {
        model.selectedScheme == nil ? model.selectedPreset.tintName : "indigo"
    }
    private var ruleCount: Int {
        if let scheme = model.selectedScheme { return model.ruleCount(for: scheme) }
        return model.currentRuleCount
    }
    private var sourceName: String {
        model.selectedScheme == nil ? RuleRepository.sourceName : "ACL4SSR"
    }
}

private struct RulePresetCard: View {
    let preset: RulePreset
    let isSelected: Bool
    let ruleCount: Int
    let onSelect: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Button(action: onSelect) {
                HStack(alignment: .top, spacing: 14) {
                    Image(systemName: preset.symbol)
                        .font(.headline)
                        .foregroundStyle(TowerTheme.color(named: preset.tintName))
                        .frame(width: 42, height: 42)
                        .background(
                            TowerTheme.color(named: preset.tintName).opacity(0.1),
                            in: RoundedRectangle(cornerRadius: 13, style: .continuous)
                        )
                    VStack(alignment: .leading, spacing: 5) {
                        HStack(spacing: 7) {
                            Text(preset.name)
                                .font(.headline)
                            if preset.isRecommended {
                                Text("推荐")
                                    .font(.caption2.weight(.bold))
                                    .foregroundStyle(Color.accentColor)
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 3)
                                    .background(Color.accentColor.opacity(0.1), in: Capsule())
                            }
                        }
                        Text(preset.summary)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("\(ruleCount.formatted()) 条 · \(preset.assignments.count) 个规则组")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    Spacer(minLength: 6)
                    ZStack {
                        Circle()
                            .stroke(isSelected ? Color.accentColor : Color.secondary.opacity(0.3), lineWidth: 1.5)
                            .frame(width: 25, height: 25)
                        if isSelected {
                            Circle()
                                .fill(Color.accentColor)
                                .frame(width: 25, height: 25)
                            Image(systemName: "checkmark")
                                .font(.caption2.weight(.black))
                                .foregroundStyle(.white)
                        }
                    }
                    .padding(.top, 2)
                }
                .contentShape(Rectangle())
                .padding(16)
            }
            .buttonStyle(ResponsivePressButtonStyle())
            .accessibilityIdentifier("rule-\(preset.id)")

            Divider().padding(.leading, 72)

            NavigationLink {
                RuleDetailView(preset: preset)
            } label: {
                HStack {
                    Text("查看包含的规则")
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.bold))
                }
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .towerCard()
        .overlay {
            if isSelected {
                RoundedRectangle(cornerRadius: TowerTheme.cornerRadius, style: .continuous)
                    .stroke(Color.accentColor.opacity(0.65), lineWidth: 1.5)
            }
        }
    }
}

struct RuleDetailView: View {
    @Environment(AppModel.self) private var model
    let preset: RulePreset

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Label(preset.name, systemImage: preset.symbol)
                        .font(.title3.weight(.semibold))
                    Text(preset.summary)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 6)
            }

            Section("本地规则组") {
                ForEach(preset.assignments) { assignment in
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(assignment.title)
                            Text(assignment.policy.displayName)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(model.ruleCount(for: assignment).formatted())
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
                if preset.includeGeoIPCN {
                    LabeledContent("中国大陆 IP", value: "GeoIP CN")
                }
                LabeledContent("未匹配流量", value: preset.finalPolicy.displayName)
            }

            Section {
                Link(destination: RuleRepository.sourceURL) {
                    Label("打开 Self-Configuration 项目", systemImage: "arrow.up.right.square")
                }
                LabeledContent("本地快照", value: RuleRepository.sourceRevision)
            } header: {
                Text("来源与许可")
            } footer: {
                Text("规则结构来自 Self-Configuration；它引用的规则提供者已固定版本并随 App 打包，运行时读取本地快照。")
            }
        }
        .navigationTitle("规则详情")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct RuleSchemeCard: View {
    @Environment(AppModel.self) private var model
    let scheme: RuleScheme
    let isSelected: Bool
    let ruleCount: Int
    let isRefreshing: Bool
    let isReady: Bool
    let onSelect: () -> Void
    let onRefresh: (() -> Void)?
    let onDelete: (() -> Void)?

    var body: some View {
        VStack(spacing: 0) {
            Button(action: onSelect) {
                HStack(alignment: .top, spacing: 14) {
                    Image(systemName: "square.stack.3d.down.right.fill")
                        .font(.headline)
                        .foregroundStyle(Color.indigo)
                        .frame(width: 42, height: 42)
                        .background(
                            Color.indigo.opacity(0.1),
                            in: RoundedRectangle(cornerRadius: 13, style: .continuous)
                        )
                    VStack(alignment: .leading, spacing: 5) {
                        Text(scheme.name)
                            .font(.headline)
                        Text(scheme.summary)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("\(ruleCount.formatted()) 条 · \(scheme.groups.count) 个策略组")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                        if !isReady {
                            Label("部分规则还没下载完成", systemImage: "exclamationmark.triangle.fill")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                    }
                    Spacer(minLength: 6)
                    ZStack {
                        Circle()
                            .stroke(isSelected ? Color.accentColor : Color.secondary.opacity(0.3), lineWidth: 1.5)
                            .frame(width: 25, height: 25)
                        if isSelected {
                            Circle()
                                .fill(Color.accentColor)
                                .frame(width: 25, height: 25)
                            Image(systemName: "checkmark")
                                .font(.caption2.weight(.black))
                                .foregroundStyle(.white)
                        }
                    }
                    .padding(.top, 2)
                }
                .contentShape(Rectangle())
                .padding(16)
            }
            .buttonStyle(ResponsivePressButtonStyle())
            .accessibilityIdentifier("scheme-\(scheme.id)")

            Divider().padding(.leading, 72)

            HStack(spacing: 0) {
                NavigationLink {
                    RuleSchemeDetailView(scheme: scheme)
                } label: {
                    HStack {
                        Text("查看策略组")
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.bold))
                    }
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if let onRefresh {
                    Divider().frame(height: 22)
                    Button(action: onRefresh) {
                        Group {
                            if isRefreshing {
                                ProgressView().controlSize(.small)
                            } else {
                                Image(systemName: "arrow.triangle.2.circlepath")
                            }
                        }
                        .frame(width: 46, height: 44)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(isRefreshing)
                    .accessibilityLabel("刷新 \(scheme.name)")
                }
            }
        }
        .towerCard()
        .overlay {
            if isSelected {
                RoundedRectangle(cornerRadius: TowerTheme.cornerRadius, style: .continuous)
                    .stroke(Color.accentColor.opacity(0.65), lineWidth: 1.5)
            }
        }
        .contextMenu {
            if let onRefresh {
                Button(action: onRefresh) {
                    Label("刷新规则", systemImage: "arrow.triangle.2.circlepath")
                }
            }
            if let onDelete {
                Button(role: .destructive, action: onDelete) {
                    Label("删除", systemImage: "trash")
                }
            }
        }
    }
}

struct RuleSchemeDetailView: View {
    let scheme: RuleScheme

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Label(scheme.name, systemImage: "square.stack.3d.down.right.fill")
                        .font(.title3.weight(.semibold))
                    Text(scheme.summary)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 6)
            }

            Section("策略组") {
                ForEach(scheme.groups, id: \.name) { group in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(group.name)
                        Text(description(of: group))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section {
                if let source = scheme.sourceURLString {
                    LabeledContent("来源", value: source)
                        .lineLimit(3)
                }
                if let updatedAt = scheme.updatedAt {
                    LabeledContent("更新时间", value: updatedAt.formatted(date: .abbreviated, time: .shortened))
                }
                LabeledContent("规则列表", value: "\(scheme.remoteRulesetURLs.count) 个")
            } header: {
                Text("来源")
            } footer: {
                Text(
                    scheme.isBundled
                        ? "这份方案随 App 打包，完全离线可用。"
                        : "规则列表已下载到本机，生成配置时不再联网。"
                )
            }
        }
        .navigationTitle("规则详情")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func description(of group: RuleSchemeGroup) -> String {
        let kind = group.kind == .urlTest ? "延迟优选" : "手动选择"
        let references = group.members.filter {
            if case .reference = $0 { return true }
            return false
        }.count
        let patterns = group.members.count - references
        var parts = [kind]
        if references > 0 { parts.append("\(references) 个引用") }
        if patterns > 0 { parts.append("\(patterns) 组节点匹配") }
        return parts.joined(separator: " · ")
    }
}

private struct ImportRuleSchemeSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var urlString = ""
    @State private var name = ""
    @State private var errorMessage: String?
    @State private var isSaving = false
    @FocusState private var isURLFocused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("https://…", text: $urlString, axis: .vertical)
                        .lineLimit(2...6)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($isURLFocused)
                        .accessibilityIdentifier("scheme-url-field")
                } header: {
                    Text("规则配置地址")
                } footer: {
                    Text("支持 subconverter 的远程配置（`.ini`），例如 ACL4SSR 提供的地址。塔台会下载配置和它引用的规则列表并保存在本机。粘贴 GitHub、Gitee 的网页地址也可以，会自动转成文件本身的地址。")
                }

                Section("名称（可选）") {
                    TextField("留空则使用域名", text: $name)
                }

                if let errorMessage {
                    Section {
                        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .font(.subheadline)
                            .foregroundStyle(.orange)
                    }
                }
            }
            .navigationTitle("导入规则")
            .navigationBarTitleDisplayMode(.inline)
            .scrollDismissesKeyboard(.interactively)
            .interactiveDismissDisabled(isSaving)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "正在下载…" : "导入") {
                        Task { await save() }
                    }
                    .disabled(urlString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSaving)
                    .accessibilityIdentifier("save-scheme")
                }
            }
            .onAppear { isURLFocused = true }
            .onChange(of: urlString) { errorMessage = nil }
        }
    }

    private func save() async {
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }

        do {
            try await model.importScheme(name: name, urlString: urlString)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
