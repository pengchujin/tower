import SwiftUI

struct RulesView: View {
    @Environment(AppModel.self) private var model
    @State private var isImportPresented = false
    @State private var pendingDeletion: RuleScheme?
    @State private var pendingFlowDeletion: CustomRuleFlow?
    @State private var groupSelectionScheme: RuleScheme?
    @State private var customRuleEditor: CustomRuleEditorRequest?
    @State private var selfConfigurationError: String?

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 22) {
                RulesOverviewCard()
                builtInSection
                importedSchemesSection
                if let scheme = model.selectedScheme {
                    customizationSection(scheme)
                }

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
        .sheet(item: $groupSelectionScheme) { scheme in
            RuleGroupSelectionSheet(scheme: scheme)
        }
        .sheet(item: $customRuleEditor) { request in
            CustomRuleFlowEditor(scheme: request.scheme, flow: request.flow)
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
        .confirmationDialog(
            pendingFlowDeletion.map { String(localized: "删除“\($0.name)”？") } ?? String(localized: "确认删除"),
            isPresented: Binding(
                get: { pendingFlowDeletion != nil },
                set: { if !$0 { pendingFlowDeletion = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("删除", role: .destructive) {
                if let pendingFlowDeletion { model.deleteCustomRuleFlow(pendingFlowDeletion) }
                pendingFlowDeletion = nil
            }
            Button("取消", role: .cancel) { pendingFlowDeletion = nil }
        } message: {
            Text("这组本地自定义规则会被移除，不会修改上游规则文件。")
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
                    onSelect: { model.selectScheme(scheme) },
                    onRefresh: nil,
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
                    onSelect: { model.selectScheme(selfConfigurationScheme) },
                    onRefresh: { Task { await model.refreshScheme(selfConfigurationScheme) } },
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
                        onSelect: { model.selectScheme(scheme) },
                        onRefresh: { Task { await model.refreshScheme(scheme) } },
                        onDelete: { pendingDeletion = scheme }
                    )
                }
            }
        }
    }

    private func customizationSection(_ scheme: RuleScheme) -> some View {
        let allGroups = scheme.selectableRuleGroupNames
        let selectedGroups = model.selectedRuleGroupNames(for: scheme)
        let flows = model.customRuleFlows(for: scheme)

        return VStack(spacing: 12) {
            SectionHeading(title: "自定义", detail: scheme.name)

            VStack(spacing: 0) {
                Button {
                    groupSelectionScheme = scheme
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "checklist")
                            .font(.title3.weight(.semibold))
                            .frame(width: 30)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("自定义分组服务")
                                .font(.headline)
                            Text("已启用 \(selectedGroups.count) / \(allGroups.count)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.tertiary)
                    }
                    .padding(16)
                    .contentShape(Rectangle())
                }
                .buttonStyle(ResponsivePressButtonStyle())
                .accessibilityIdentifier("rule-group-selector")

                Divider().padding(.leading, 58)

                Button {
                    customRuleEditor = CustomRuleEditorRequest(scheme: scheme, flow: nil)
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "plus.circle")
                            .font(.title3.weight(.semibold))
                            .frame(width: 30)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("添加自定义规则流")
                                .font(.headline)
                            Text("更新上游规则后仍会保留")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.tertiary)
                    }
                    .padding(16)
                    .contentShape(Rectangle())
                }
                .buttonStyle(ResponsivePressButtonStyle())

                if !flows.isEmpty {
                    Divider().padding(.leading, 58)
                    VStack(spacing: 0) {
                        ForEach(Array(flows.enumerated()), id: \.element.id) { index, flow in
                            if index > 0 { Divider().padding(.leading, 58) }
                            CustomRuleFlowRow(
                                flow: flow,
                                onEdit: {
                                    customRuleEditor = CustomRuleEditorRequest(scheme: scheme, flow: flow)
                                },
                                onDelete: { pendingFlowDeletion = flow }
                            )
                        }
                    }
                    .accessibilityIdentifier("custom-rule-flow-list")
                }
            }
            .towerCard()

            Text("这里只筛选服务规则；最终兜底和被引用的节点策略会自动保留，避免生成无效配置。")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
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

private struct CustomRuleEditorRequest: Identifiable {
    let scheme: RuleScheme
    let flow: CustomRuleFlow?

    var id: String {
        "\(scheme.id)-\(flow?.id.uuidString ?? "new")"
    }
}

private struct CustomRuleFlowRow: View {
    @Environment(AppModel.self) private var model
    let flow: CustomRuleFlow
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Button(action: onEdit) {
                HStack(spacing: 12) {
                    Image(systemName: "point.3.connected.trianglepath.dotted")
                        .font(.title3)
                        .frame(width: 30)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(flow.name)
                            .font(.subheadline.weight(.semibold))
                        Text("\(policyTitle) · \(flow.normalizedRules.count) 条")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Toggle(
                "启用 \(flow.name)",
                isOn: Binding(
                    get: { flow.isEnabled },
                    set: { model.setCustomRuleFlow(flow, enabled: $0) }
                )
            )
            .labelsHidden()

            Menu {
                Button(action: onEdit) {
                    Label("编辑", systemImage: "pencil")
                }
                Button(role: .destructive, action: onDelete) {
                    Label("删除", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .frame(width: 34, height: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("\(flow.name) 更多操作")
        }
        .padding(.leading, 16)
        .padding(.trailing, 8)
        .padding(.vertical, 10)
    }

    private var policyTitle: String {
        switch flow.policyName.uppercased() {
        case "DIRECT": return String(localized: "直连")
        case "REJECT": return String(localized: "拒绝")
        default: return flow.policyName
        }
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
    let onSelect: () -> Void
    let onRefresh: (() -> Void)?
    let onDelete: (() -> Void)?
    @State private var isExpanded = false

    var body: some View {
        VStack(spacing: 0) {
            Button(action: onSelect) {
                HStack(alignment: .top, spacing: 12) {
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
                    Spacer(minLength: 6)
                    SelectionIndicator(isSelected: isSelected)
                }
                .contentShape(Rectangle())
                .padding(16)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("scheme-\(scheme.id)")
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
                    Button(isSaving ? "正在下载…" : "导出") {
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

private struct RuleGroupSelectionSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let scheme: RuleScheme
    @State private var searchText = ""

    private var visibleGroups: [String] {
        let groups = scheme.selectableRuleGroupNames
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return groups }
        return groups.filter { $0.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Toggle(
                        "显示 Emoji",
                        isOn: Binding(
                            get: { model.ruleGroupEmojisAreEnabled(for: scheme) },
                            set: { model.setRuleGroupEmojisEnabled($0, for: scheme) }
                        )
                    )
                } footer: {
                    Text("关闭后，导出配置里的策略组会同步移除开头的 Emoji。")
                }

                if visibleGroups.isEmpty {
                    ContentUnavailableView.search(text: searchText)
                        .listRowBackground(Color.clear)
                } else {
                    Section {
                        ForEach(visibleGroups, id: \.self) { name in
                            let isEnabled = model.selectedRuleGroupNames(for: scheme).contains(name)
                            Button {
                                model.setRuleGroup(name, enabled: !isEnabled, for: scheme)
                            } label: {
                                HStack(spacing: 12) {
                                    Text(name)
                                        .foregroundStyle(.primary)
                                    Spacer()
                                    Image(systemName: isEnabled ? "checkmark.circle.fill" : "circle")
                                        .font(.title3)
                                        .foregroundStyle(isEnabled ? Color.accentColor : Color.secondary)
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityValue(isEnabled ? "已启用" : "未启用")
                        }
                    } header: {
                        Text("本地服务分组")
                    } footer: {
                        Text("取消勾选后，该分组对应的规则不会导出；它依赖的底层策略会按需自动保留。")
                    }
                }
            }
            .navigationTitle("选择规则分组")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(
                text: $searchText,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: "搜索海外媒体、AI 等"
            )
            .scrollDismissesKeyboard(.interactively)
            .accessibilityIdentifier("rule-group-selection-list")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }
}

private struct CustomRuleFlowEditor: View {
    private enum Field: Hashable {
        case name
        case rules
    }

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let scheme: RuleScheme
    let existingFlow: CustomRuleFlow?
    @State private var name: String
    @State private var policyName: String
    @State private var rulesText: String
    @State private var isEnabled: Bool
    @FocusState private var focusedField: Field?

    init(scheme: RuleScheme, flow: CustomRuleFlow?) {
        self.scheme = scheme
        existingFlow = flow
        _name = State(initialValue: flow?.name ?? "")
        _policyName = State(initialValue: flow?.policyName ?? scheme.groups.first?.name ?? "DIRECT")
        _rulesText = State(initialValue: flow?.rulesText ?? "")
        _isEnabled = State(initialValue: flow?.isEnabled ?? true)
    }

    private var policyOptions: [String] {
        var seen = Set<String>()
        return (scheme.groups.map(\.name) + ["DIRECT", "REJECT"]).filter {
            seen.insert($0).inserted
        }
    }

    private var normalizedRuleCount: Int {
        draft.normalizedRules.count
    }

    private var draft: CustomRuleFlow {
        CustomRuleFlow(
            id: existingFlow?.id ?? UUID(),
            schemeID: scheme.id,
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            policyName: policyName,
            rulesText: rulesText,
            isEnabled: isEnabled
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("规则流") {
                    TextField("名称，例如 Tailscale", text: $name)
                        .focused($focusedField, equals: .name)
                        .submitLabel(.next)
                        .onSubmit { focusedField = .rules }

                    Picker("匹配后使用", selection: $policyName) {
                        ForEach(policyOptions, id: \.self) { policy in
                            Text(policyTitle(policy)).tag(policy)
                        }
                    }

                    Toggle("启用这组规则", isOn: $isEnabled)
                }

                Section {
                    TextEditor(text: $rulesText)
                        .font(.system(.body, design: .monospaced))
                        .frame(minHeight: 190)
                        .focused($focusedField, equals: .rules)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    Button("填入 Tailscale 示例") {
                        insertTailscaleExample()
                        focusedField = .rules
                    }
                } header: {
                    HStack {
                        Text("规则内容")
                        Spacer()
                        Text("\(normalizedRuleCount) 条")
                    }
                } footer: {
                    Text("每行填写 TYPE,VALUE，例如 DOMAIN-SUFFIX,tailscale.com。粘贴带旧策略的规则也可以，塔台会改用上方选择的流向，并保留 no-resolve。")
                }
            }
            .navigationTitle(existingFlow == nil
                ? String(localized: "新增规则流")
                : String(localized: "编辑规则流"))
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
                                || policyName.isEmpty
                                || normalizedRuleCount == 0
                        )
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("收起键盘") { focusedField = nil }
                }
            }
            .onAppear {
                if existingFlow == nil { focusedField = .name }
            }
        }
    }

    private func policyTitle(_ policy: String) -> String {
        switch policy.uppercased() {
        case "DIRECT": return String(localized: "直连")
        case "REJECT": return String(localized: "拒绝")
        default: return policy
        }
    }

    private func insertTailscaleExample() {
        let sample = """
        DOMAIN-SUFFIX,tailscale.com
        DOMAIN-SUFFIX,ts.net
        IP-CIDR,100.64.0.0/10,no-resolve
        """
        let trimmed = rulesText.trimmingCharacters(in: .whitespacesAndNewlines)
        rulesText = trimmed.isEmpty ? sample : "\(trimmed)\n\(sample)"
    }

    private func save() {
        focusedField = nil
        model.upsertCustomRuleFlow(draft)
        dismiss()
    }
}
