import SwiftUI

struct RulesView: View {
    @Environment(AppModel.self) private var model
    @State private var isImportPresented = false
    @State private var pendingDeletion: RuleScheme?
    @State private var editingImportedScheme: RuleScheme?
    @State private var customizationScheme: RuleScheme?
    @State private var selfConfigurationError: String?

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 22) {
                VStack(spacing: 8) {
                    RulesOverviewCard()
                    Label("点击规则方案即可修改规则", systemImage: "hand.tap")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 4)
                        .accessibilityIdentifier("rules-editing-hint")
                }
                builtInSection
                importedSchemesSection

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
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    isImportPresented = true
                } label: {
                    Label("导入规则链接", systemImage: "link.badge.plus")
                }
                .accessibilityIdentifier("import-rule-scheme")
            }
        }
        .sensoryFeedback(.selection, trigger: model.selectedPresetID)
        .sheet(isPresented: $isImportPresented) {
            ImportRuleSchemeSheet()
        }
        .sheet(item: $customizationScheme) { scheme in
            RuleCustomizationSheet(scheme: scheme)
        }
        .sheet(item: $editingImportedScheme) { scheme in
            ImportedRuleSchemeEditor(scheme: scheme)
        }
        .confirmationDialog(
            pendingDeletion.map { String(localized: "删除“\($0.name)”？") } ?? String(localized: "确认删除"),
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

    private var builtInSection: some View {
        let schemes = model.ruleSchemes.filter(\.isBundled)
        return VStack(spacing: 12) {
            SectionHeading(title: "本机规则", detail: String(localized: "安装后离线可用"))
            ForEach(schemes) { scheme in
                RuleSchemeCard(
                    scheme: scheme,
                    isSelected: model.selectedPresetID == scheme.id,
                    ruleCount: model.ruleCount(for: scheme),
                    isRefreshing: false,
                    isReady: true,
                    showsInlineRefreshAction: true,
                    onCustomize: { customizationScheme = scheme },
                    onSelect: { model.selectScheme(scheme) },
                    onRefresh: nil,
                    onEdit: nil,
                    onDelete: nil
                )
            }
            if let selfConfigurationScheme = model.selfConfigurationScheme {
                RuleSchemeCard(
                    scheme: selfConfigurationScheme,
                    isSelected: model.selectedPresetID == selfConfigurationScheme.id,
                    ruleCount: model.ruleCount(for: selfConfigurationScheme),
                    isRefreshing: model.importingSchemeIDs.contains(selfConfigurationScheme.id),
                    isReady: model.isSchemeReady(selfConfigurationScheme),
                    showsInlineRefreshAction: false,
                    onCustomize: { customizationScheme = selfConfigurationScheme },
                    onSelect: { model.selectScheme(selfConfigurationScheme) },
                    onRefresh: { Task { await model.refreshScheme(selfConfigurationScheme) } },
                    onEdit: { editingImportedScheme = selfConfigurationScheme },
                    onDelete: { pendingDeletion = selfConfigurationScheme }
                )
            } else {
                SelfConfigurationDownloadCard(
                    isWorking: model.isImportingScheme,
                    errorMessage: selfConfigurationError,
                    onDownload: { Task { await downloadSelfConfiguration() } }
                )
            }
        }
    }

    @ViewBuilder
    private var importedSchemesSection: some View {
        let schemes = model.ruleSchemes.filter {
            !$0.isBundled && !SelfConfigurationSource.matches($0)
        }
        VStack(spacing: 12) {
            SectionHeading(title: "已导入", detail: String(localized: "\(schemes.count) 个方案"))
            if schemes.isEmpty {
                Text("还没有导入规则，使用右上角按钮添加。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .towerCard()
            } else {
                ForEach(schemes) { scheme in
                    RuleSchemeCard(
                        scheme: scheme,
                        isSelected: model.selectedPresetID == scheme.id,
                        ruleCount: model.ruleCount(for: scheme),
                        isRefreshing: model.importingSchemeIDs.contains(scheme.id),
                        isReady: model.isSchemeReady(scheme),
                        showsInlineRefreshAction: true,
                        onCustomize: { customizationScheme = scheme },
                        onSelect: { model.selectScheme(scheme) },
                        onRefresh: { Task { await model.refreshScheme(scheme) } },
                        onEdit: { editingImportedScheme = scheme },
                        onDelete: { pendingDeletion = scheme }
                    )
                }
            }
        }
    }

    private func downloadSelfConfiguration() async {
        selfConfigurationError = nil
        do {
            try await model.importScheme(
                name: SelfConfigurationSource.name,
                urlString: SelfConfigurationSource.downloadURL.absoluteString
            )
        } catch {
            selfConfigurationError = error.localizedDescription
        }
    }
}

private struct RulesOverviewCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(title)
                        .font(.title2.weight(.bold))
                        .lineLimit(1, reservesSpace: true)
                        .minimumScaleFactor(0.8)
                    Text(summary)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2, reservesSpace: true)
                }
                Spacer(minLength: 0)
                Image(systemName: symbol)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 48, height: 48)
                    .background(
                        TowerTheme.color(named: tintName).gradient,
                        in: RoundedRectangle(cornerRadius: 15, style: .continuous)
                    )
            }

            HStack(spacing: 14) {
                overviewLabel(String(localized: "\(ruleCount.formatted()) 条"), symbol: "list.bullet.rectangle")
                overviewLabel(String(localized: "\(groupCount) 组"), symbol: "square.stack.3d.up")
                Spacer(minLength: 0)
                overviewLabel(sourceName, symbol: "shippingbox")
            }
        }
        .padding(20)
        .towerCard()
        .accessibilityIdentifier("rules-overview-card")
    }

    private func overviewLabel(_ text: String, symbol: String) -> some View {
        Label(text, systemImage: symbol)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .lineLimit(1)
    }

    private var title: String { model.selectedScheme?.name ?? model.selectedPreset.name }
    private var summary: String {
        model.selectedScheme?.localizedSummary() ?? model.selectedPreset.summary
    }
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
    private var groupCount: Int {
        model.selectedScheme?.groups.count ?? model.selectedPreset.assignments.count
    }
    private var sourceName: String {
        guard let scheme = model.selectedScheme else { return String(localized: "本机规则") }
        if scheme.isBundled { return String(localized: "本机") }
        return URL(string: scheme.sourceURLString ?? "")?.host ?? String(localized: "已导入")
    }
}

/// The row that expands a card in place. Matches the home page: opacity and
/// layout only, never a slide-in from the top.
private struct RuleDisclosureRow: View {
    let title: String
    let isExpanded: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Text(title)
                Spacer()
                Image(systemName: "chevron.down")
                    .font(.caption.weight(.bold))
                    .rotationEffect(.degrees(isExpanded ? 180 : 0))
            }
            .font(.subheadline.weight(.medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct RuleDetailLine: View {
    let title: String
    let detail: String
    var trailing: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            if let trailing {
                Text(trailing)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct LocalRuleSetEditorRequest: Identifiable {
    let ruleSet: LocalRuleSet?

    var id: String {
        ruleSet?.id.uuidString ?? "new"
    }
}

private struct SelfConfigurationDownloadCard: View {
    let isWorking: Bool
    let errorMessage: String?
    let onDownload: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(SelfConfigurationSource.name)
                .font(.headline)

            Text(SelfConfigurationSource.summary)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button(action: onDownload) {
                HStack {
                    if isWorking { ProgressView().controlSize(.small) }
                    Text(isWorking ? "正在下载…" : "手动下载")
                        .font(.subheadline.weight(.semibold))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 11)
            }
            .buttonStyle(.borderedProminent)
            .disabled(isWorking)
            .accessibilityIdentifier("download-self-configuration")

            Link("查看项目来源", destination: SelfConfigurationSource.projectURL)
                .font(.caption)

            Text("规则由您直接从上游下载，不随 App 分发。下载后保存在本机。")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .towerCard()
    }
}

private struct RuleSchemeCard: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let scheme: RuleScheme
    let isSelected: Bool
    let ruleCount: Int
    let isRefreshing: Bool
    let isReady: Bool
    let showsInlineRefreshAction: Bool
    let onCustomize: () -> Void
    let onSelect: () -> Void
    let onRefresh: (() -> Void)?
    let onEdit: (() -> Void)?
    let onDelete: (() -> Void)?
    @State private var isExpanded = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 8) {
                Button(action: onCustomize) {
                    HStack(alignment: .center, spacing: 10) {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(scheme.name)
                                .font(.headline)
                            Text(scheme.localizedSummary())
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
                        Spacer(minLength: 4)
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.tertiary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("rule-customization-\(scheme.id)")
                .accessibilityLabel("编辑 \(scheme.name)")

                Button(action: onSelect) {
                    SelectionIndicator(isSelected: isSelected)
                        .frame(width: 44, height: 44, alignment: .topTrailing)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isSelected ? "\(scheme.name)，当前使用" : "使用 \(scheme.name)")
            }
            .padding(16)
            .accessibilityIdentifier("scheme-\(scheme.id)")
            .contextMenu {
                if let onEdit {
                    Button(action: onEdit) {
                        Label("编辑", systemImage: "pencil")
                    }
                }
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

            Divider()

            HStack(spacing: 0) {
                RuleDisclosureRow(title: String(localized: "查看策略组"), isExpanded: isExpanded) {
                    withAnimation(expansionAnimation) { isExpanded.toggle() }
                }
                .accessibilityIdentifier("scheme-detail-\(scheme.id)")

                if showsInlineRefreshAction, let onRefresh {
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

            if isExpanded {
                LazyVStack(alignment: .leading, spacing: 10) {
                    ForEach(scheme.groups, id: \.name) { group in
                        RuleDetailLine(title: group.name, detail: description(of: group))
                    }
                    Divider()
                    RuleDetailLine(
                        title: String(localized: "规则列表"),
                        detail: String(localized: "\(scheme.remoteRulesetURLs.count) 个")
                    )
                    if let updatedAt = scheme.updatedAt {
                        RuleDetailLine(
                            title: String(localized: "更新时间"),
                            detail: updatedAt.formatted(date: .abbreviated, time: .shortened)
                        )
                    }
                    Text(scheme.isBundled
                        ? String(localized: "这份方案随 App 打包，完全离线可用。")
                        : String(localized: "规则列表已下载到本机，生成配置时不再联网。"))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
                .transition(.opacity)
            }
        }
        .towerCard()
        .overlay {
            RoundedRectangle(cornerRadius: TowerTheme.cornerRadius, style: .continuous)
                .stroke(isSelected ? Color.accentColor.opacity(0.65) : Color.clear, lineWidth: 1.5)
        }
        .sensoryFeedback(.selection, trigger: isExpanded)
    }

    private var expansionAnimation: Animation {
        reduceMotion ? .easeOut(duration: 0.14) : .interactiveSpring(response: 0.34, dampingFraction: 1)
    }

    private func description(of group: RuleSchemeGroup) -> String {
        let kind = group.kind == .urlTest
            ? String(localized: "延迟优选")
            : String(localized: "手动选择")
        let references = group.members.filter {
            if case .reference = $0 { return true }
            return false
        }.count
        let patterns = group.members.count - references
        var parts = [kind]
        if references > 0 { parts.append(String(localized: "\(references) 个引用")) }
        if patterns > 0 { parts.append(String(localized: "\(patterns) 组节点匹配")) }
        return parts.joined(separator: " · ")
    }
}

private struct ImportedRuleSchemeEditor: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let scheme: RuleScheme
    @State private var name: String
    @State private var summary: String

    init(scheme: RuleScheme) {
        self.scheme = scheme
        _name = State(initialValue: scheme.name)
        _summary = State(initialValue: scheme.localizedSummary())
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("名称", text: $name)
                    TextField("简介", text: $summary, axis: .vertical)
                        .lineLimit(3...6)
                } footer: {
                    Text("只修改显示信息，不会更改规则内容或来源链接。")
                }
            }
            .navigationTitle("编辑规则方案")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        if model.updateImportedSchemeMetadata(
                            id: scheme.id,
                            name: name,
                            summary: summary
                        ) {
                            dismiss()
                        }
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .presentationDetents([.medium])
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
                    Text("支持 Clash YAML、subconverter（`.ini`）和 Surge 配置。塔台会下载配置及其引用的规则列表并保存在本机。粘贴 GitHub、Gitee 的网页地址也可以，会自动转成文件本身的地址。")
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

private struct CatalogRuleEditorRequest: Identifiable {
    let scheme: RuleScheme
    let flow: CustomRuleFlow

    var id: UUID { flow.id }
}

private struct RuleGroupEditorRequest: Identifiable {
    let scheme: RuleScheme
    let group: RuleSchemeGroup

    var id: String { "\(scheme.id)::\(group.name)" }
}

private struct RuleGroupIdentityEditorRequest: Identifiable {
    let scheme: RuleScheme
    let group: RuleSchemeGroup

    var id: String { "identity::\(scheme.id)::\(group.name)" }
}

private struct RuleGroupDeletionRequest: Identifiable {
    let scheme: RuleScheme
    let group: RuleSchemeGroup
    let references: [String]

    var id: String { "\(scheme.id)::\(group.name)" }
}

/// One predictable place for every rule-level decision: existing service
/// groups, protected routing primitives, maintained catalogs and advanced
/// hand-written rules. Search is the primary path; raw syntax stays one level
/// deeper for people who actually need it.
private struct RuleCustomizationSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let scheme: RuleScheme
    @State private var ruleEditMode: EditMode = .inactive
    @State private var editingGroups: [RuleSchemeGroup] = []
    @State private var initialEditingGroupNames: [String] = []
    @State private var searchText = ""
    @State private var selectedCategory: RuleCatalogCategory?
    @State private var manualEditor: LocalRuleSetEditorRequest?
    @State private var catalogEditor: CatalogRuleEditorRequest?
    @State private var groupEditor: RuleGroupEditorRequest?
    @State private var identityEditor: RuleGroupIdentityEditorRequest?
    @State private var pendingCatalogDeletion: CustomRuleFlow?
    @State private var pendingLocalRuleSetDeletion: LocalRuleSet?
    @State private var pendingGroupDeletion: RuleGroupDeletionRequest?
    @State private var installingIDs = Set<String>()
    @State private var errorMessage: String?
    @State private var showsSaveScheme = false
    @State private var showsResetConfirmation = false

    private var trimmedSearch: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var visibleGroups: [RuleSchemeGroup] {
        let groups = editingGroups.isEmpty
            ? model.customizableRuleGroups(for: scheme)
            : editingGroups
        guard !ruleEditMode.isEditing, !trimmedSearch.isEmpty else { return groups }
        return groups.filter {
            $0.name.localizedCaseInsensitiveContains(trimmedSearch)
                || groupModeTitle($0).localizedCaseInsensitiveContains(trimmedSearch)
        }
    }

    private var visibleCatalogEntries: [RuleCatalogEntry] {
        RuleCatalog.builtIn.entries.filter { entry in
            (selectedCategory == nil || entry.category == selectedCategory)
                && (trimmedSearch.isEmpty || entry.matches(trimmedSearch))
        }
    }

    private var visibleLocalRuleSets: [LocalRuleSet] {
        guard !trimmedSearch.isEmpty else { return model.localRuleSets }
        return model.localRuleSets.filter {
            $0.name.localizedCaseInsensitiveContains(trimmedSearch)
                || $0.normalizedRules.contains { $0.localizedCaseInsensitiveContains(trimmedSearch) }
        }
    }

    private var compactRuleRowInsets: EdgeInsets {
        EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16)
    }

    var body: some View {
        NavigationStack {
            List {
                customRuleGroupsSection
                localRuleSetsSection
                catalogSections
            }
            .environment(\.editMode, $ruleEditMode)
            .navigationTitle("规则定制")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(
                text: $searchText,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: "在线搜索规则：如 YouTube OpenAI"
            )
            .scrollDismissesKeyboard(.interactively)
            .accessibilityIdentifier("rule-customization-list")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Menu {
                        Button {
                            toggleRuleGroupEmojiVisibilityAfterMenuDismiss()
                        } label: {
                            Label("显示策略组 Emoji", systemImage: "face.smiling")
                        }
                        .menuActionDismissBehavior(.enabled)
                        Button {
                            showsSaveScheme = true
                        } label: {
                            Label("另存为新方案", systemImage: "square.and.arrow.down")
                        }
                        Divider()
                        Button(role: .destructive) {
                            showsResetConfirmation = true
                        } label: {
                            Label("恢复初始规则", systemImage: "arrow.counterclockwise")
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.title2.weight(.bold))
                            .foregroundStyle(.tint)
                            .accessibilityLabel("更多")
                    }
                    .accessibilityIdentifier("rule-actions-menu")
                }
                ToolbarItemGroup(placement: .confirmationAction) {
                    Button {
                        toggleRuleEditing()
                    } label: {
                        if ruleEditMode.isEditing {
                            Image(systemName: "checkmark")
                        } else {
                            Text("编辑")
                        }
                    }
                    .accessibilityLabel(ruleEditMode.isEditing ? "结束编辑" : "编辑规则")
                    Button("完成") {
                        commitEditingGroupOrder()
                        dismiss()
                    }
                }
            }
            .sheet(item: $manualEditor) { request in
                LocalRuleSetEditor(ruleSet: request.ruleSet)
            }
            .sheet(item: $catalogEditor) { request in
                CatalogRuleRouteEditor(scheme: request.scheme, flow: request.flow)
            }
            .sheet(item: $groupEditor) { request in
                RuleGroupEditor(scheme: request.scheme, group: request.group)
            }
            .sheet(item: $identityEditor, onDismiss: reloadEditingGroupsIfNeeded) { request in
                RuleGroupIdentityEditor(scheme: request.scheme, group: request.group)
            }
            .sheet(isPresented: $showsSaveScheme) {
                SaveCustomizedSchemeSheet(scheme: scheme) {
                    dismiss()
                }
            }
            .confirmationDialog("恢复初始规则",
                isPresented: $showsResetConfirmation,
                titleVisibility: .visible
            ) {
                Button("恢复初始规则", role: .destructive) {
                    restoreInitialRules()
                }
                Button("取消", role: .cancel) {}
            } message: {
                Text("这会移除当前方案后来添加的规则、改名、Emoji 设置和排序；“我的规则集”中的本地内容会保留。")
            }
            .confirmationDialog(
                pendingCatalogDeletion.map { String(localized: "删除“\($0.name)”？") } ?? String(localized: "确认删除"),
                isPresented: Binding(
                    get: { pendingCatalogDeletion != nil },
                    set: { if !$0 { pendingCatalogDeletion = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("删除", role: .destructive) {
                    if let pendingCatalogDeletion { model.deleteCustomRuleFlow(pendingCatalogDeletion) }
                    pendingCatalogDeletion = nil
                }
                Button("取消", role: .cancel) { pendingCatalogDeletion = nil }
            } message: {
                Text("只移除塔台保存的这项自定义，不会修改上游仓库。")
            }
            .confirmationDialog(
                pendingLocalRuleSetDeletion.map { String(localized: "删除“\($0.name)”？") }
                    ?? String(localized: "确认删除"),
                isPresented: Binding(
                    get: { pendingLocalRuleSetDeletion != nil },
                    set: { if !$0 { pendingLocalRuleSetDeletion = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("删除本地规则集", role: .destructive) {
                    if let pendingLocalRuleSetDeletion {
                        model.deleteLocalRuleSet(pendingLocalRuleSetDeletion)
                    }
                    pendingLocalRuleSetDeletion = nil
                }
                Button("取消", role: .cancel) { pendingLocalRuleSetDeletion = nil }
            } message: {
                Text("这会删除本机保存的规则内容，并从所有当前方案中移除；不会修改上游仓库。")
            }
            .confirmationDialog(
                pendingGroupDeletion.map { String(localized: "删除“\($0.group.name)”？") }
                    ?? String(localized: "确认删除"),
                isPresented: Binding(
                    get: { pendingGroupDeletion != nil },
                    set: { if !$0 { pendingGroupDeletion = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("删除", role: .destructive) {
                    if let request = pendingGroupDeletion {
                        model.deleteRuleGroup(named: request.group.name, for: request.scheme)
                    }
                    pendingGroupDeletion = nil
                }
                Button("取消", role: .cancel) { pendingGroupDeletion = nil }
            } message: {
                if let request = pendingGroupDeletion, !request.references.isEmpty {
                    Text("以下分组正在引用它：\(request.references.joined(separator: "、"))。继续删除后会同时移除这些引用；没有候选项的分组会回退到 DIRECT。")
                } else {
                    Text("这会移除该分组以及指向它的规则，不会修改上游仓库。")
                }
            }
            .alert("无法添加规则", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("好的") { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
            .towerToast()
        }
        .presentationDetents([.large])
        .onAppear {
            synchronizeGroupDraft(with: model.customizableRuleGroups(for: scheme))
        }
        .onChange(of: model.customizableRuleGroups(for: scheme)) { _, groups in
            guard !ruleEditMode.isEditing else { return }
            synchronizeGroupDraft(with: groups)
        }
        .onDisappear { commitEditingGroupOrder() }
    }

    private func restoreInitialRules() {
        ruleEditMode = .inactive
        searchText = ""
        selectedCategory = nil
        model.resetRuleCustomization(for: scheme)
        synchronizeGroupDraft(with: model.customizableRuleGroups(for: scheme))
    }

    private func toggleRuleGroupEmojiVisibilityAfterMenuDismiss() {
        let enabled = !model.ruleGroupEmojisAreEnabled(for: scheme)
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(180))
            guard !Task.isCancelled else { return }
            var transaction = Transaction(animation: nil)
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                model.setRuleGroupEmojisEnabled(enabled, for: scheme)
            }
        }
    }

    private func toggleRuleEditing() {
        if ruleEditMode.isEditing {
            finishRuleEditing()
        } else {
            beginRuleEditing()
        }
    }

    private func beginRuleEditing() {
        searchText = ""
        editingGroups = model.customizableRuleGroups(for: scheme)
        initialEditingGroupNames = editingGroups.map(\.name)
        withAnimation { ruleEditMode = .active }
    }

    private func finishRuleEditing() {
        commitEditingGroupOrder()
        withAnimation { ruleEditMode = .inactive }
    }

    private func commitEditingGroupOrder() {
        guard !editingGroups.isEmpty else { return }
        let names = editingGroups.map(\.name)
        guard names != initialEditingGroupNames else { return }
        model.setRuleGroupOrder(names, for: scheme)
        initialEditingGroupNames = names
    }

    private func reloadEditingGroupsIfNeeded() {
        guard ruleEditMode.isEditing else { return }
        synchronizeGroupDraft(with: model.customizableRuleGroups(for: scheme))
    }

    private func synchronizeGroupDraft(with groups: [RuleSchemeGroup]) {
        guard editingGroups != groups else { return }
        editingGroups = groups
        initialEditingGroupNames = groups.map(\.name)
    }

    private func moveRuleGroupsInNormalMode(
        fromOffsets source: IndexSet,
        toOffset destination: Int
    ) {
        guard trimmedSearch.isEmpty else { return }
        if editingGroups.isEmpty {
            editingGroups = model.customizableRuleGroups(for: scheme)
        }
        editingGroups.move(fromOffsets: source, toOffset: destination)
        let names = editingGroups.map(\.name)
        initialEditingGroupNames = names
        model.setRuleGroupOrder(names, for: scheme)
    }

    private var categoryPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                categoryButton(nil, title: String(localized: "全部"))
                ForEach(RuleCatalogCategory.allCases, id: \.self) { category in
                    categoryButton(category, title: category.displayName)
                }
            }
            .padding(.horizontal, 16)
        }
    }

    @ViewBuilder
    private var catalogSections: some View {
        Section {
            categoryPicker
                .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
        } header: {
            HStack {
                Text("在线规则库")
                Spacer()
                Text("\(visibleCatalogEntries.count) 项")
            }
        } footer: {
            Text("规则从 ACL4SSR 与 blackmatrix7 的官方仓库按需下载。点击加号后会直接加入当前规则。")
        }

        if visibleCatalogEntries.isEmpty {
            ContentUnavailableView.search(text: trimmedSearch)
                .listRowBackground(Color.clear)
        } else {
            Section {
                ForEach(visibleCatalogEntries) { entry in
                    catalogRow(entry)
                }
            }
        }
    }

    private var localRuleSetsSection: some View {
        Section {
            Button {
                manualEditor = LocalRuleSetEditorRequest(ruleSet: nil)
            } label: {
                Label {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("新建规则集")
                            .foregroundStyle(.primary)
                        Text("支持手动创建规则和引用规则集。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: "text.badge.plus")
                        .foregroundStyle(Color.accentColor)
                }
            }
            .listRowInsets(compactRuleRowInsets)

            ForEach(visibleLocalRuleSets) { ruleSet in
                localRuleSetRow(ruleSet)
                    .listRowInsets(compactRuleRowInsets)
                    .contextMenu {
                        Button {
                            manualEditor = LocalRuleSetEditorRequest(ruleSet: ruleSet)
                        } label: {
                            Label("编辑规则内容", systemImage: "pencil")
                        }
                        Button(role: .destructive) {
                            pendingLocalRuleSetDeletion = ruleSet
                        } label: {
                            Label("删除本地规则集", systemImage: "trash")
                        }
                    }
            }
        } header: {
            HStack {
                Text("我的规则集")
                Spacer()
                Text("\(model.localRuleSets.count) 个")
            }
        } footer: {
            Text("新建的规则集先保存在本机。点击右侧加号后才会加入当前规则，更新上游方案时不会被覆盖。")
        }
    }

    @ViewBuilder
    private var customRuleGroupsSection: some View {
        if !visibleGroups.isEmpty {
            Section {
                if ruleEditMode.isEditing {
                    ForEach(editingGroups, id: \.name) { group in
                        customRuleGroupActionRow(group)
                            .listRowInsets(compactRuleRowInsets)
                    }
                    .onMove { source, destination in
                        editingGroups.move(fromOffsets: source, toOffset: destination)
                    }
                } else {
                    ForEach(visibleGroups, id: \.name) { group in
                        customRuleGroupActionRow(group)
                            .listRowInsets(compactRuleRowInsets)
                            .moveDisabled(!trimmedSearch.isEmpty)
                            .contextMenu {
                                if let flow = userCreatedFlow(for: group) {
                                    if let ruleSet = localRuleSet(for: flow) {
                                        Button {
                                            manualEditor = LocalRuleSetEditorRequest(ruleSet: ruleSet)
                                        } label: {
                                            Label("编辑规则内容", systemImage: "doc.text.magnifyingglass")
                                        }
                                    }
                                }
                                Button(role: .destructive) {
                                    requestDeletion(of: group)
                                } label: {
                                    Label("删除", systemImage: "trash")
                                }
                            }
                    }
                    .onMove { source, destination in
                        moveRuleGroupsInNormalMode(
                            fromOffsets: source,
                            toOffset: destination
                        )
                    }
                }
            } header: {
                HStack {
                    Text("当前规则")
                    Spacer()
                    Text("\(ruleEditMode.isEditing ? editingGroups.count : model.customizableRuleGroups(for: scheme).count) 组")
                }
            }
        }
    }

    private func userCreatedFlow(for group: RuleSchemeGroup) -> CustomRuleFlow? {
        let sourceName = model.sourceRuleGroupName(group.name, for: scheme)
        return model.customRuleFlows(for: scheme).first { flow in
            flow.catalogID == nil
                && [group.name, sourceName].contains(flow.generatedPolicyGroup?.name)
        }
    }

    private func localRuleSet(for flow: CustomRuleFlow) -> LocalRuleSet? {
        guard let localRuleSetID = flow.localRuleSetID else { return nil }
        return model.localRuleSets.first { $0.id == localRuleSetID }
    }

    private func localRuleSetRow(_ ruleSet: LocalRuleSet) -> some View {
        let isAdded = model.isLocalRuleSetAdded(ruleSet, to: scheme)
        return HStack(spacing: 12) {
            Button {
                manualEditor = LocalRuleSetEditorRequest(ruleSet: ruleSet)
            } label: {
                HStack(spacing: 12) {
                    Text("🧩")
                        .font(.title3)
                        .frame(width: 36, height: 36)
                        .background(Color.accentColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
                    VStack(alignment: .leading, spacing: 3) {
                        Text(ruleSet.name)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                        Text(localRuleSetSummary(ruleSet))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 8)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button {
                if isAdded {
                    model.removeLocalRuleSet(ruleSet, from: scheme)
                } else {
                    model.addLocalRuleSet(ruleSet, to: scheme)
                }
            } label: {
                Image(systemName: isAdded ? "checkmark.circle.fill" : "plus.circle")
                    .font(.title3)
                    .foregroundStyle(isAdded ? Color.green : Color.accentColor)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isAdded ? "从当前规则移除" : "加入当前规则")
            .accessibilityValue(isAdded ? "已添加" : "未添加")
        }
    }

    private func localRuleSetSummary(_ ruleSet: LocalRuleSet) -> String {
        if ruleSet.remoteRuleURL != nil {
            return String(localized: "本地 · 远程规则集")
        }
        return String(localized: "本地 · \(ruleSet.normalizedRules.count) 条规则")
    }

    private func requestDeletion(of group: RuleSchemeGroup) {
        pendingGroupDeletion = RuleGroupDeletionRequest(
            scheme: scheme,
            group: group,
            references: model.ruleGroupReferences(to: group.name, for: scheme)
        )
    }

    private func customRuleGroupRow(
        _ group: RuleSchemeGroup
    ) -> some View {
        HStack(spacing: 10) {
            visibleRuleGroupEmoji(group)
            Text(RulePolicyPresentation.nameWithoutLeadingEmoji(group.name))
                .foregroundStyle(Color.primary)
            Spacer()
            Text(groupSelectionSummary(group))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private func customRuleGroupActionRow(_ group: RuleSchemeGroup) -> some View {
        if ruleEditMode.isEditing {
            HStack(spacing: 10) {
                editableRuleIdentityButton(group)
                Spacer(minLength: 8)
                Text(groupSelectionSummary(group))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        } else {
            Button {
                groupEditor = RuleGroupEditorRequest(scheme: scheme, group: group)
            } label: {
                customRuleGroupRow(group)
            }
            .buttonStyle(.plain)
        }
    }

    private func editableRuleIdentityButton(_ group: RuleSchemeGroup) -> some View {
        Button {
            openIdentityEditor(for: group)
        } label: {
            HStack(spacing: 10) {
                visibleRuleGroupEmoji(group)
                Text(RulePolicyPresentation.nameWithoutLeadingEmoji(group.name))
                    .foregroundStyle(Color.primary)
                Image(systemName: "pencil")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
            }
            .contentShape(Rectangle())
            .frame(minHeight: 44)
        }
        .buttonStyle(.borderless)
        .accessibilityLabel("修改 \(group.name) 的 Emoji 和名称")
    }

    private func visibleRuleGroupEmoji(_ group: RuleSchemeGroup) -> some View {
        let emojisVisible = model.ruleGroupEmojisAreEnabled(for: scheme)
        return Text(RulePolicyPresentation.emoji(for: group.name, kind: group.kind))
            .font(.body)
            .frame(width: 28, height: 28)
            .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
            .opacity(emojisVisible ? 1 : 0)
            .accessibilityHidden(!emojisVisible)
            .animation(nil, value: emojisVisible)
    }

    private func openIdentityEditor(for group: RuleSchemeGroup) {
        commitEditingGroupOrder()
        identityEditor = RuleGroupIdentityEditorRequest(
            scheme: scheme,
            group: group
        )
    }

    private func groupModeTitle(_ group: RuleSchemeGroup) -> String {
        switch group.kind {
        case .select: return String(localized: "手动选择")
        case .urlTest: return String(localized: "延迟优选")
        }
    }

    private func groupSelectionSummary(_ group: RuleSchemeGroup) -> String {
        if let reference = group.members.compactMap({ member -> String? in
            guard case .reference(let name) = member else { return nil }
            return name
        }).first {
            return RulePolicyPresentation.nameWithoutLeadingEmoji(reference)
        }
        return group.kind == .urlTest
            ? String(localized: "自动选择")
            : String(localized: "节点匹配")
    }

    private func categoryButton(_ category: RuleCatalogCategory?, title: String) -> some View {
        Button {
            selectedCategory = category
        } label: {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(selectedCategory == category ? Color.white : Color.primary)
                .padding(.horizontal, 13)
                .padding(.vertical, 8)
                .background(
                    selectedCategory == category ? Color.accentColor : Color.secondary.opacity(0.1),
                    in: Capsule()
                )
        }
        .buttonStyle(.plain)
    }

    private func catalogRow(_ entry: RuleCatalogEntry) -> some View {
        let installed = model.catalogFlow(for: entry, in: scheme)
        let isInstalling = installingIDs.contains(entry.id)
        return Button {
            if installed != nil {
                model.removeCatalogEntry(entry, from: scheme)
            } else {
                install(entry)
            }
        } label: {
            HStack(spacing: 12) {
                Text(entry.emoji)
                    .font(.title3)
                    .frame(width: 36, height: 36)
                    .background(tint(for: entry.defaultRoute).opacity(0.11), in: RoundedRectangle(cornerRadius: 10))
                VStack(alignment: .leading, spacing: 3) {
                    Text(entry.name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text("\(entry.provider.displayName) · \(routeTitle(entry))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                if isInstalling {
                    ProgressView()
                } else {
                    Image(systemName: installed == nil ? "plus.circle" : "checkmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(installed == nil ? Color.accentColor : Color.green)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isInstalling)
        .listRowInsets(compactRuleRowInsets)
        .accessibilityValue(installed == nil ? "未添加" : "已添加")
        .accessibilityHint(installed == nil ? "添加到自定义规则" : "从自定义规则移除")
        .contextMenu {
            if let installed {
                Button {
                    catalogEditor = CatalogRuleEditorRequest(scheme: scheme, flow: installed)
                } label: {
                    Label("编辑", systemImage: "pencil")
                }
                Button(role: .destructive) { pendingCatalogDeletion = installed } label: {
                    Label("删除", systemImage: "trash")
                }
            }
        }
    }

    private func install(_ entry: RuleCatalogEntry) {
        installingIDs.insert(entry.id)
        Task {
            defer { installingIDs.remove(entry.id) }
            do {
                try await model.installCatalogEntry(entry, for: scheme)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func symbol(for category: RuleCatalogCategory) -> String {
        switch category {
        case .ai: "sparkles"
        case .streaming: "play.rectangle.fill"
        case .social: "message.fill"
        case .gaming: "gamecontroller.fill"
        case .advertising: "hand.raised.fill"
        case .domestic: "location.fill"
        case .infrastructure: "network"
        case .other: "square.grid.2x2.fill"
        }
    }

    private func tint(for route: RuleCatalogDefaultRoute) -> Color {
        switch route {
        case .proxy: .accentColor
        case .direct: .green
        case .reject: .red
        }
    }

    private func routeTitle(_ entry: RuleCatalogEntry) -> String {
        switch entry.defaultRoute {
        case .proxy: entry.suggestedPolicyName ?? String(localized: "节点选择")
        case .direct: String(localized: "直连")
        case .reject: String(localized: "拒绝")
        }
    }

}

private struct RuleGroupIdentityEditor: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let scheme: RuleScheme
    let group: RuleSchemeGroup
    @State private var emoji: String
    @State private var name: String
    @State private var errorMessage: String?

    init(scheme: RuleScheme, group: RuleSchemeGroup) {
        self.scheme = scheme
        self.group = group
        _emoji = State(initialValue: RulePolicyPresentation.emoji(for: group.name, kind: group.kind))
        _name = State(initialValue: RulePolicyPresentation.nameWithoutLeadingEmoji(group.name))
    }

    private var selectedEmoji: String? {
        let value = emoji.trimmingCharacters(in: .whitespacesAndNewlines)
        guard value.count == 1,
              let character = value.first,
              character.unicodeScalars.contains(where: { $0.properties.isEmoji }) else {
            return nil
        }
        return String(character)
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 12) {
                        TextField("Emoji", text: $emoji)
                            .font(.title2)
                            .multilineTextAlignment(.center)
                            .frame(width: 58)
                            .accessibilityLabel("规则 Emoji")
                        TextField("规则名称", text: $name)
                            .textInputAutocapitalization(.never)
                    }
                } footer: {
                    Text("Emoji 与名称会同步更新规则绑定和其他策略组引用。")
                }
            }
            .navigationTitle("修改规则名称")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }
                        .disabled(selectedEmoji == nil || trimmedName.isEmpty)
                }
            }
            .alert("无法修改规则", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("好") { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        }
        .presentationDetents([.medium])
    }

    private func save() {
        guard let selectedEmoji else { return }
        do {
            try model.renameRuleGroup(
                named: group.name,
                to: "\(selectedEmoji) \(trimmedName)",
                for: scheme
            )
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct RuleGroupEditor: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let scheme: RuleScheme
    let group: RuleSchemeGroup
    @State private var selectedReferences: [String]
    @State private var selectedNodePatterns: Set<String>

    init(scheme: RuleScheme, group: RuleSchemeGroup) {
        self.scheme = scheme
        self.group = group
        var seenReferences = Set<String>()
        let references = group.members.compactMap { member -> String? in
            guard case .reference(let name) = member else { return nil }
            return name
        }.filter { seenReferences.insert($0).inserted }
        _selectedReferences = State(initialValue: references)
        _selectedNodePatterns = State(initialValue: Set(group.members.compactMap { member in
            guard case .nodePattern(let pattern) = member else { return nil }
            return pattern
        }))
    }

    private var editorMode: RuleSchemeGroupEditorMode {
        scheme.groupEditorMode(for: group)
    }

    private var referenceOptions: [String] {
        scheme.routingTargetGroupNames(
            from: model.customizableRuleGroups(for: scheme),
            excluding: group.name
        )
    }

    private var nodePatternOptions: [String] {
        group.members.compactMap { member in
            guard case .nodePattern(let pattern) = member else { return nil }
            return pattern
        }
    }

    private var saveIsDisabled: Bool {
        switch editorMode {
        case .routingTargets: selectedReferences.isEmpty
        case .nodePatternsOnly: selectedNodePatterns.isEmpty
        }
    }

    var body: some View {
        NavigationStack {
            List {
                switch editorMode {
                case .routingTargets:
                    OrderedPolicyCandidateSections(
                        selected: $selectedReferences,
                        options: referenceOptions
                    )

                case .nodePatternsOnly:
                    Section {
                        ForEach(nodePatternOptions, id: \.self) { pattern in
                            candidateRow(
                                pattern == ".*" ? String(localized: "全部节点") : pattern,
                                isSelected: selectedNodePatterns.contains(pattern),
                                emoji: "🔎"
                            ) {
                                toggleNodePattern(pattern)
                            }
                        }
                    } header: {
                        Text("节点名称匹配")
                    }
                }
            }
            .navigationTitle(RulePolicyPresentation.nameWithoutLeadingEmoji(group.name))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }
                        .disabled(saveIsDisabled)
                }
            }
        }
    }

    private func candidateRow(
        _ policy: String,
        isSelected: Bool,
        emoji: String? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Text(emoji ?? RulePolicyPresentation.emoji(for: policy, kind: .select))
                    .frame(width: 28)
                Text(RulePolicyPresentation.nameWithoutLeadingEmoji(policy))
                    .foregroundStyle(.primary)
                Spacer()
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Color.accentColor)
                    .opacity(isSelected ? 1 : 0)
                    .accessibilityHidden(!isSelected)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityValue(isSelected ? "已选" : "未选")
    }

    private func toggleNodePattern(_ value: String) {
        if selectedNodePatterns.contains(value) {
            selectedNodePatterns.remove(value)
        } else {
            selectedNodePatterns.insert(value)
        }
    }

    private func save() {
        let referenceMembers = selectedReferences.map(RuleSchemeGroupMember.reference)
        let patternMembers = nodePatternOptions.compactMap { pattern in
            selectedNodePatterns.contains(pattern) ? RuleSchemeGroupMember.nodePattern(pattern) : nil
        }
        let members: [RuleSchemeGroupMember]
        switch editorMode {
        case .routingTargets:
            members = referenceMembers
        case .nodePatternsOnly:
            members = patternMembers
        }
        model.updateRuleGroup(
            RuleSchemeGroup(
                name: group.name,
                kind: editorMode == .routingTargets ? .select : group.kind,
                members: members,
                testURLString: group.testURLString,
                interval: group.interval,
                tolerance: group.tolerance
            ),
            for: scheme
        )
        dismiss()
    }
}

/// Policy candidates are intentionally ordered: clients use the first member
/// as the initial/default policy, while still exposing every later member for
/// manual switching after import.
private struct OrderedPolicyCandidateSections: View {
    @Binding var selected: [String]
    let options: [String]

    private var available: [String] {
        options.filter { !selected.contains($0) }
    }

    var body: some View {
        Section {
            ForEach(selected, id: \.self) { policy in
                HStack(spacing: 12) {
                    Text(RulePolicyPresentation.emoji(for: policy, kind: .select))
                        .frame(width: 28)
                    Text(policyTitle(policy))
                    Spacer(minLength: 8)
                    if selected.first == policy {
                        Text("默认")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.accentColor)
                    }
                }
            }
            .onMove { selected.move(fromOffsets: $0, toOffset: $1) }
            .onDelete { selected.remove(atOffsets: $0) }
        } header: {
            HStack {
                Text("候选策略")
                Spacer()
                EditButton()
            }
        } footer: {
            Text("第一项是默认策略。可拖动排序；导入客户端后仍可手动切换。")
        }

        if !available.isEmpty {
            Section("可添加策略") {
                ForEach(available, id: \.self) { policy in
                    Button {
                        selected.append(policy)
                    } label: {
                        HStack(spacing: 12) {
                            Text(RulePolicyPresentation.emoji(for: policy, kind: .select))
                                .frame(width: 28)
                            Text(policyTitle(policy))
                                .foregroundStyle(.primary)
                            Spacer()
                            Image(systemName: "plus.circle")
                                .font(.title3)
                                .foregroundStyle(Color.accentColor)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func policyTitle(_ policy: String) -> String {
        switch policy.uppercased() {
        case "DIRECT": String(localized: "直连")
        case "REJECT": String(localized: "拒绝")
        default: RulePolicyPresentation.nameWithoutLeadingEmoji(policy)
        }
    }
}

private struct SaveCustomizedSchemeSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let scheme: RuleScheme
    let onSaved: () -> Void
    @State private var name: String

    init(scheme: RuleScheme, onSaved: @escaping () -> Void) {
        self.scheme = scheme
        self.onSaved = onSaved
        _name = State(initialValue: "\(scheme.name) · \(String(localized: "自定义"))")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("方案名称", text: $name)
                        .textInputAutocapitalization(.never)
                } footer: {
                    Text("会保存当前分组顺序、候选策略与规则，下次可直接选择。")
                }
            }
            .navigationTitle("另存为新方案")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        _ = model.saveCustomizedScheme(named: name, from: scheme)
                        dismiss()
                        onSaved()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .presentationDetents([.medium])
    }
}

enum RulePolicyPresentation {
    static func emoji(for name: String, kind: RuleSchemeGroup.Kind) -> String {
        if let first = name.first,
           first.unicodeScalars.contains(where: { $0.properties.isEmoji }) {
            return String(first)
        }
        let key = nameWithoutLeadingEmoji(name).lowercased()
        let mappings: [(needles: [String], emoji: String)] = [
            (["节点选择", "proxy"], "🚀"),
            (["手动切换", "manual"], "🎛️"),
            (["自动选择", "url-test"], "♻️"),
            (["全球直连", "direct"], "🎯"),
            (["广告拦截", "reject"], "🛑"),
            (["应用净化"], "🍃"),
            (["漏网之鱼", "final"], "🐟"),
            (["香港", "hong kong"], "🇭🇰"),
            (["日本", "japan"], "🇯🇵"),
            (["美国", "united states"], "🇺🇸"),
            (["狮城", "新加坡", "singapore"], "🇸🇬"),
            (["台湾", "taiwan"], "🇹🇼"),
            (["韩国", "korea"], "🇰🇷"),
            (["openai", "chatgpt", "ai 服务"], "🤖"),
            (["gemini"], "🔷"),
            (["telegram"], "✈️"),
            (["youtube"], "📹"),
            (["netflix", "奈飞"], "🎞️"),
            (["disney"], "🧸"),
            (["apple"], "🍎"),
            (["microsoft"], "🪟"),
            (["国外媒体", "流媒体"], "🌍"),
        ]
        if let match = mappings.first(where: { mapping in
            mapping.needles.contains(where: key.contains)
        }) {
            return match.emoji
        }
        return kind == .urlTest ? "⚡️" : "🧩"
    }

    static func nameWithoutLeadingEmoji(_ name: String) -> String {
        var result = name.trimmingCharacters(in: .whitespacesAndNewlines)
        while let first = result.first,
              first.unicodeScalars.contains(where: { $0.properties.isEmoji }) {
            result.removeFirst()
            result = result.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return result.isEmpty ? name : result
    }
}

private struct CatalogRuleRouteEditor: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let scheme: RuleScheme
    let flow: CustomRuleFlow
    @State private var selectedReferences: [String]

    init(scheme: RuleScheme, flow: CustomRuleFlow) {
        self.scheme = scheme
        self.flow = flow
        let initialGroup = flow.generatedPolicyGroup ?? scheme.groups.first { $0.name == flow.policyName }
        let initialReferences = initialGroup?.members.compactMap { member -> String? in
            guard case .reference(let name) = member else { return nil }
            return name
        } ?? [flow.policyName]
        var seenReferences = Set<String>()
        _selectedReferences = State(
            initialValue: initialReferences.filter { seenReferences.insert($0).inserted }
        )
    }

    private var policyOptions: [String] {
        scheme.routingTargetGroupNames(
            from: model.customizableRuleGroups(for: scheme),
            excluding: servicePolicyGroup?.name
        )
    }

    private var servicePolicyGroup: RuleSchemeGroup? {
        let groups = model.customizableRuleGroups(for: scheme)
        guard let group = groups.first(where: { $0.name == flow.policyName }) else {
            return flow.generatedPolicyGroup
        }
        let routingTargets = Set(scheme.routingTargetGroupNames(from: groups))
        return routingTargets.contains(group.name) ? nil : group
    }

    var body: some View {
        NavigationStack {
            Form {
                OrderedPolicyCandidateSections(
                    selected: $selectedReferences,
                    options: policyOptions
                )
            }
            .navigationTitle("规则流向")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }
                        .disabled(selectedReferences.isEmpty)
                }
            }
            .onAppear { loadCurrentGroup() }
        }
    }

    private func loadCurrentGroup() {
        guard let group = servicePolicyGroup else { return }
        var seenReferences = Set<String>()
        selectedReferences = group.members.compactMap { member in
            guard case .reference(let name) = member else { return nil }
            return name
        }.filter { seenReferences.insert($0).inserted }
    }

    private func save() {
        var updated = flow
        let members = selectedReferences.map(RuleSchemeGroupMember.reference)

        if let group = servicePolicyGroup {
            let edited = RuleSchemeGroup(
                name: group.name,
                kind: .select,
                members: members,
                testURLString: group.testURLString,
                interval: group.interval,
                tolerance: group.tolerance
            )
            updated.policyName = group.name
            if flow.generatedPolicyGroup != nil {
                updated.generatedPolicyGroup = edited
            } else {
                model.updateRuleGroup(edited, for: scheme)
                updated.generatedPolicyGroup = nil
            }
        } else {
            let groupName = flow.generatedPolicyGroup?.name ?? flow.name
            updated.policyName = groupName
            updated.generatedPolicyGroup = RuleSchemeGroup(
                name: groupName,
                kind: .select,
                members: members
            )
        }
        model.upsertCustomRuleFlow(updated)
        dismiss()
    }
}

private struct LocalRuleSetEditor: View {
    private enum Field: Hashable {
        case name
        case rules
    }

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let existingRuleSet: LocalRuleSet?
    @State private var name: String
    @State private var rulesText: String
    @State private var isSaving = false
    @State private var errorMessage: String?
    @FocusState private var focusedField: Field?

    init(ruleSet: LocalRuleSet?) {
        existingRuleSet = ruleSet
        _name = State(initialValue: ruleSet?.name ?? "")
        _rulesText = State(initialValue: ruleSet?.ruleInputText ?? "")
    }

    private var normalizedRuleCount: Int {
        draft.normalizedRules.count
    }

    private var ruleContentSummary: String {
        draft.remoteRuleURL == nil
            ? String(localized: "\(normalizedRuleCount) 条")
            : String(localized: "远程规则集")
    }

    private var draft: LocalRuleSet {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var ruleSet = existingRuleSet else {
            return LocalRuleSet(
                name: trimmedName,
                rulesText: rulesText
            )
        }

        ruleSet.name = trimmedName
        if rulesText != ruleSet.ruleInputText {
            ruleSet.setRuleInput(rulesText)
        }
        return ruleSet
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("规则集") {
                    TextField("名称，例如 🎬 奈飞", text: $name)
                        .focused($focusedField, equals: .name)
                        .submitLabel(.next)
                        .onSubmit { focusedField = .rules }
                }

                Section {
                    ZStack(alignment: .topLeading) {
                        if rulesText.isEmpty {
                            VStack(alignment: .leading, spacing: 5) {
                                Text("规则集 URL，例如：")
                                Text(verbatim: "https://raw.githubusercontent.com/ACL4SSR/ACL4SSR/master/Clash/UnBan.list")
                                Text("或逐行输入：")
                                Text(verbatim: "DOMAIN,apple.comscoreresearch.com")
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.72)
                                Text(verbatim: "IP-CIDR,17.0.0.0/8,no-resolve")
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.72)
                            }
                            .font(.system(.footnote, design: .monospaced))
                            .lineSpacing(1)
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 8)
                            .allowsHitTesting(false)
                        }

                        TextEditor(text: $rulesText)
                            .font(.system(.footnote, design: .monospaced))
                            .scrollContentBackground(.hidden)
                            .frame(minHeight: 230)
                            .focused($focusedField, equals: .rules)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }
                } header: {
                    HStack {
                        Text("规则内容")
                        Spacer()
                        Text(ruleContentSummary)
                    }
                } footer: {
                    Text("支持 HTTPS 的 Clash / Surge .list 规则集，也支持 DOMAIN、DOMAIN-SUFFIX、DOMAIN-KEYWORD、IP-CIDR、IP-CIDR6、GEOIP 等 TYPE,VALUE 写法。保存后会出现在“我的规则集”，点击加号才会加入当前规则。")
                }
            }
            .navigationTitle(existingRuleSet == nil
                ? String(localized: "新建规则集")
                : String(localized: "编辑规则集"))
            .navigationBarTitleDisplayMode(.inline)
            .scrollDismissesKeyboard(.interactively)
            .interactiveDismissDisabled(false)
            .accessibilityIdentifier("custom-rule-flow-editor")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }
                        .disabled(
                            name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                || !draft.hasRuleContent
                                || isSaving
                        )
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("收起键盘") { focusedField = nil }
                }
            }
            .onAppear {
                if existingRuleSet == nil { focusedField = .name }
            }
            .alert("无法保存规则集", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("好") { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    private func save() {
        focusedField = nil
        let ruleSet = draft
        isSaving = true
        Task { @MainActor in
            do {
                try await model.saveLocalRuleSet(ruleSet)
                dismiss()
            } catch {
                isSaving = false
                errorMessage = error.localizedDescription
            }
        }
    }
}
