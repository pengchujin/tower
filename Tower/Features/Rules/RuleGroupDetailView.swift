import SwiftUI

/// Pages pushed inside the rule customization sheet.
enum RuleCustomizationRoute: Hashable {
    case group(String)
}

/// Names a ruleset the way people think about it: the list's file name and
/// where it came from, rather than a raw URL.
enum RulesetPresentation {
    static func title(_ ruleset: RuleSchemeRuleset) -> String {
        switch ruleset.resource {
        case .remote(let url):
            return url.deletingPathExtension().lastPathComponent
        case .inline(let rule):
            if let url = ruleset.resource.domainSetURL { return url.deletingPathExtension().lastPathComponent }
            if ruleset.origin == .supplement { return SupplementRule(line: rule)?.value ?? rule }
            return rule.uppercased() == "FINAL" ? String(localized: "其余所有流量") : rule
        }
    }

    static func source(_ ruleset: RuleSchemeRuleset) -> String {
        if ruleset.origin == .supplement { return String(localized: "你添加的规则") }
        if case .added(let name) = ruleset.origin { return String(localized: "已添加：\(name)") }
        guard let url = ruleset.resource.downloadURL else { return String(localized: "单条规则") }
        let path = url.path.lowercased()
        if path.contains("/acl4ssr/") { return "ACL4SSR" }
        if path.contains("/blackmatrix7/") { return "blackmatrix7" }
        return url.host ?? url.absoluteString
    }

    static func isList(_ ruleset: RuleSchemeRuleset) -> Bool {
        ruleset.resource.downloadURL != nil
    }
}

/// Everything about one group on one page, edited in place: its name, where
/// its traffic goes, the sites added to it, and the scheme's rules that feed
/// it. Changes save as they are made, like Settings, so there is no second
/// "edit" layer to find.
struct RuleGroupDetailView: View {
    @Environment(AppModel.self) private var model
    let scheme: RuleScheme
    @State var groupName: String
    let onDelete: (RuleSchemeGroup) -> Void
    @State private var nodeFilters: [EditableNodeNameFilter] = []
    @State private var previewResult: NodeNameFilterPreviewResult?
    @State private var showsAddRule = false
    @State private var openedSource: RuleSchemeRuleset?
    @State private var lineCounts: [RuleSchemeRuleset: Int] = [:]
    @State private var loadedGroup: String?
    @State private var emoji = ""
    @State private var name = ""
    @State private var selectedKind: RuleSchemeGroup.Kind = .select
    @State private var selectedReferences: [String] = []
    @State private var nameError: String?
    @State private var pendingDeletion: RuleSchemeGroup?
    @FocusState private var isEditingName: Bool

    private var group: RuleSchemeGroup? {
        model.customizableRuleGroups(for: scheme).first { $0.name == groupName }
    }

    private var supplements: [SupplementRule] {
        model.supplementRules(forGroup: groupName, in: scheme)
    }

    private var sources: [RuleSchemeRuleset] {
        model.ruleSources(forGroup: groupName, in: scheme)
    }

    var body: some View {
        List {
            if let group {
                identitySection(group)
                if scheme.groupEditorMode(for: group) == .routingTargets {
                    kindSection(group)
                    OrderedPolicyCandidateSections(
                        selected: $selectedReferences,
                        options: scheme.routingTargetGroupNames(
                            from: model.customizableRuleGroups(for: scheme),
                            excluding: group.name
                        ),
                        scheme: scheme
                    )
                } else {
                    // Regional and helper groups are edited right here too:
                    // type, node-name filter and its live preview.
                    kindSection(group)
                    nodeFilterSections(group)
                }
                // Node groups (自动选择, regional groups) only pick nodes for the
                // routing groups; sites belong in those. Their rule sections
                // show only if the scheme or an older edit routes rules here.
                if showsRuleSections(group) {
                    supplementSection
                    sourcesSection
                }
                Section {
                    Button(role: .destructive) { pendingDeletion = group } label: {
                        Text("删除策略组")
                    }
                    .accessibilityIdentifier("rule-group-delete")
                }
            } else {
                ContentUnavailableView("策略组已删除", systemImage: "trash")
                    .listRowBackground(Color.clear)
            }
        }
        // Drag handles on the candidates are always visible, as in any
        // reorderable iOS list; the old separate Edit button hid them. Node
        // groups have nothing to drag, and edit mode keeps the filter's
        // match-style menu from opening, so they stay out of it.
        .environment(\.editMode, .constant(isRoutingGroup ? .active : .inactive))
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle(RulePolicyPresentation.nameWithoutLeadingEmoji(groupName))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { loadDrafts() }
        .onChange(of: group) { _, _ in loadDrafts() }
        .onChange(of: selectedReferences) { _, _ in saveRouting() }
        .onChange(of: selectedKind) { _, _ in
            if isRoutingGroup { saveRouting() } else { saveNodeFilters() }
        }
        .onChange(of: isEditingName) { _, editing in if !editing { commitName() } }
        .onDisappear { commitName() }
        .task(id: sources) {
            var counts: [RuleSchemeRuleset: Int] = [:]
            for source in sources where RulesetPresentation.isList(source) {
                counts[source] = model.ruleLines(for: source).count
            }
            lineCounts = counts
        }
        .navigationDestination(item: $openedSource) { source in
            RulesetContentView(ruleset: source)
        }
        .task(id: nodeFilterPreviewInput) {
            guard let input = nodeFilterPreviewInput else { return }
            do { try await Task.sleep(for: .milliseconds(300)) } catch { return }
            let result = await input.evaluate()
            guard !Task.isCancelled, nodeFilterPreviewInput == input else { return }
            previewResult = result
            saveNodeFilters()
        }
        .sheet(isPresented: $showsAddRule) {
            AddSupplementRuleSheet(model: model, scheme: scheme, groupName: groupName)
        }
        .alert("无法修改名称", isPresented: Binding(
            get: { nameError != nil },
            set: { if !$0 { nameError = nil } }
        )) {
            Button("好") { nameError = nil }
        } message: {
            Text(nameError ?? "")
        }
        .alert(
            pendingDeletion.map { String(localized: "删除“\($0.name)”？") } ?? String(localized: "确认删除"),
            isPresented: Binding(
                get: { pendingDeletion != nil },
                set: { if !$0 { pendingDeletion = nil } }
            ),
            presenting: pendingDeletion
        ) { group in
            Button(String(localized: "删除"), role: .destructive) {
                pendingDeletion = nil
                onDelete(group)
            }
            Button("取消", role: .cancel) { pendingDeletion = nil }
        } message: { group in
            Text(deletionMessage(for: group))
        }
        .accessibilityIdentifier("rule-group-detail")
    }

    /// Same wording as the list's swipe-to-delete confirmation.
    private func deletionMessage(for group: RuleSchemeGroup) -> String {
        let references = model.ruleGroupReferences(to: group.name, for: scheme)
        if references.isEmpty {
            return String(localized: "这会移除该分组以及指向它的规则，不会修改上游仓库。")
        }
        return String(
            localized: "以下分组正在引用它：\(references.joined(separator: "、"))。继续删除后会同时移除这些引用；没有候选项的分组会回退到 DIRECT。"
        )
    }

    private func showsRuleSections(_ group: RuleSchemeGroup) -> Bool {
        scheme.groupEditorMode(for: group) == .routingTargets || !sources.isEmpty || !supplements.isEmpty
    }

    private func identitySection(_ group: RuleSchemeGroup) -> some View {
        Section {
            HStack(spacing: 12) {
                TextField("Emoji", text: $emoji)
                    .font(.title2)
                    .multilineTextAlignment(.center)
                    .frame(width: 44)
                    .focused($isEditingName)
                    .accessibilityLabel("规则 Emoji")
                    .accessibilityIdentifier("rule-group-emoji-field")
                Divider()
                TextField("规则名称", text: $name)
                    .textInputAutocapitalization(.never)
                    .focused($isEditingName)
                    .submitLabel(.done)
                    .onSubmit { isEditingName = false }
                    .accessibilityIdentifier("rule-group-name-field")
            }
        } header: {
            Text("名称")
        } footer: {
            Text("改名会同步更新规则绑定和其他策略组里的引用。")
        }
    }

    private func kindSection(_ group: RuleSchemeGroup) -> some View {
        Section {
            Picker("策略类型", selection: $selectedKind) {
                ForEach([RuleSchemeGroup.Kind.select, .urlTest, .fallback, .loadBalance, .smart, .conditional, .relay, .unsupported], id: \.self) { kind in
                    if kind == group.kind || [.select, .urlTest, .fallback].contains(kind) {
                        Text(kind.displayTitle).tag(kind)
                    }
                }
            }
            .accessibilityIdentifier("rule-group-kind-" + group.name)
        } header: {
            Text("流量去向")
        } footer: {
            if isRoutingGroup && selectedReferences.isEmpty {
                Text("至少保留一个候选策略，修改才会生效。")
                    .foregroundStyle(.orange)
            }
        }
    }

    private var isRoutingGroup: Bool {
        group.map { scheme.groupEditorMode(for: $0) == .routingTargets } ?? true
    }

    @ViewBuilder
    private func nodeFilterSections(_ group: RuleSchemeGroup) -> some View {
        Section {
            ForEach($nodeFilters) { $filter in
                NodeNameFilterFields(pattern: $filter.pattern, caseInsensitiveDefault: caseInsensitiveDefault(group))
            }
        } header: {
            Text("节点名称匹配")
        } footer: {
            Text("修改会自动保存；表达式无效或没有关键词时不会保存。")
        }
        if let input = nodeFilterPreviewInput {
            NodeNameFilterPreview(input: input, result: previewResult)
        }
        if let source = sourceGroup(of: group),
           EditableNodeNameFilter.rows(for: source).map(\.pattern) != nodeFilters.map(\.pattern) {
            Section {
                Button("恢复方案默认筛选") {
                    nodeFilters = EditableNodeNameFilter.rows(for: source)
                }
            }
        }
    }

    private func caseInsensitiveDefault(_ group: RuleSchemeGroup) -> Bool {
        group.sourceFormat == nil || group.sourceFormat == "subconverter"
    }

    private func sourceGroup(of group: RuleSchemeGroup) -> RuleSchemeGroup? {
        let name = model.sourceRuleGroupName(group.name, for: scheme)
        return scheme.groups.first { $0.name == name }
    }

    private var enabledNodePatterns: [String] { nodeFilters.filter(\.isEnabled).map(\.pattern) }

    private var nodeFilterPreviewInput: NodeNameFilterPreviewInput? {
        guard let group, scheme.groupEditorMode(for: group) == .nodePatternsOnly, !nodeFilters.isEmpty else { return nil }
        let candidates = model.enabledNodes.map { node -> [String] in
            let presented = model.nodeForPresentation(node)
            return [NodeRegionResolver.displayName(for: presented), presented.name]
        }
        let scope: NodeNameFilterPreviewInput.SourceScope? = selectedKind == group.kind ? .init(
            group: group, nodes: model.enabledNodes.map { model.nodeForPresentation($0) },
            sourceURLHashes: Dictionary(model.subscriptions.filter(\.isEnabled).map {
                ($0.id, RuleSchemeParser.sourceURLHash($0.urlString))
            }, uniquingKeysWith: { first, _ in first }),
            boundPatterns: Set(nodeFilters.filter { $0.isEnabled && $0.isSourceBound }.map(\.pattern))) : nil
        return .init(patterns: enabledNodePatterns, candidates: candidates,
                     insensitive: caseInsensitiveDefault(group), sourceScope: scope)
    }

    /// Saves once the debounced preview has validated exactly what is on
    /// screen, so a half-typed or invalid expression never reaches an export.
    private func saveNodeFilters() {
        guard let group, scheme.groupEditorMode(for: group) == .nodePatternsOnly,
              let input = nodeFilterPreviewInput, previewResult?.input == input, previewResult?.error == nil,
              !enabledNodePatterns.isEmpty else { return }
        let saved = group.members.compactMap { member -> String? in
            guard case .nodePattern(let pattern) = member else { return nil }
            return pattern
        }
        guard enabledNodePatterns != saved || selectedKind != group.kind else { return }
        let members = enabledNodePatterns.map(RuleSchemeGroupMember.nodePattern)
            + (group.kind == .smart ? [] : group.members.filter {
                if case .reference = $0 { return true }
                return false
            })
        model.updateRuleGroup(
            RuleSchemeGroup(
                name: group.name,
                kind: selectedKind,
                members: members,
                testURLString: group.testURLString,
                interval: group.interval,
                tolerance: group.tolerance,
                algorithm: group.algorithm,
                sourceType: group.sourceType,
                sourceFormat: group.sourceFormat,
                parameters: group.parameters
            ),
            for: scheme,
            sourceNodePatterns: group.parameters?["tower-source-patterns"] != nil
                ? nodeFilters.filter { $0.isEnabled && $0.isSourceBound }.map(\.pattern) : nil
        )
    }

    /// Drafts follow the saved group until the user starts typing, and
    /// reload when it changes underneath (rename, reset, iCloud).
    private func loadDrafts() {
        guard let group else { return }
        if !isEditingName || loadedGroup != group.name {
            emoji = RulePolicyPresentation.emoji(for: group.name, kind: group.kind, inferFromName: false)
            name = RulePolicyPresentation.nameWithoutLeadingEmoji(group.name)
        }
        selectedKind = group.kind
        // Filters load once per group: reloading them after each save would
        // rebuild the fields under the user's cursor.
        if loadedGroup != group.name || nodeFilters.isEmpty {
            let rows = EditableNodeNameFilter.rows(for: group)
            nodeFilters = rows.isEmpty
                ? [EditableNodeNameFilter(pattern: "", isSourceBound: group.parameters?["tower-source-patterns"] != nil)]
                : rows
        }
        var seen = Set<String>()
        selectedReferences = group.members.compactMap { member -> String? in
            guard case .reference(let name) = member else { return nil }
            return name
        }.filter { seen.insert($0).inserted }
        loadedGroup = group.name
    }

    private func saveRouting() {
        guard let group, scheme.groupEditorMode(for: group) == .routingTargets,
              !selectedReferences.isEmpty else { return }
        let current = group.members.compactMap { member -> String? in
            guard case .reference(let name) = member else { return nil }
            return name
        }
        guard selectedReferences != current || selectedKind != group.kind else { return }
        let members = selectedReferences.map(RuleSchemeGroupMember.reference)
            + (group.kind == .select ? [] : group.members.filter {
                if case .nodePattern = $0 { return true }
                return false
            })
        model.updateRuleGroup(
            RuleSchemeGroup(
                name: group.name,
                kind: selectedKind,
                members: members,
                testURLString: group.testURLString,
                interval: group.interval,
                tolerance: group.tolerance,
                algorithm: group.algorithm,
                sourceType: group.sourceType,
                sourceFormat: group.sourceFormat,
                parameters: group.parameters
            ),
            for: scheme
        )
    }

    private func commitName() {
        guard let group else { return }
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedEmoji = emoji.trimmingCharacters(in: .whitespacesAndNewlines)
        let isEmoji = trimmedEmoji.isEmpty || (trimmedEmoji.count == 1
            && trimmedEmoji.unicodeScalars.contains { $0.properties.isEmoji })
        let newName = trimmedEmoji.isEmpty ? trimmedName : "\(trimmedEmoji) \(trimmedName)"
        guard newName != group.name else { return }
        guard !trimmedName.isEmpty, isEmoji else {
            nameError = trimmedName.isEmpty
                ? String(localized: "名称不能为空。")
                : String(localized: "Emoji 只能填一个表情符号。")
            loadedGroup = nil
            loadDrafts()
            return
        }
        do {
            try model.renameRuleGroup(named: group.name, to: newName, for: scheme)
            groupName = newName
        } catch {
            nameError = error.localizedDescription
            loadedGroup = nil
            loadDrafts()
        }
    }

    private var supplementSection: some View {
        Section {
            ForEach(supplements) { rule in
                VStack(alignment: .leading, spacing: 2) {
                    Text(rule.value)
                        .font(.system(.body, design: .monospaced))
                    Text(rule.kind.title)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .moveDisabled(true)
            }
            .onDelete { offsets in
                for rule in offsets.map({ supplements[$0] }) {
                    model.removeSupplementRule(rule, fromGroup: groupName, in: scheme)
                }
            }
            Button {
                showsAddRule = true
            } label: {
                Label("添加网站或 IP", systemImage: "plus.circle.fill")
            }
            .accessibilityIdentifier("rule-group-add-supplement")
        } header: {
            HStack {
                Text("我添加的规则")
                Spacer()
                if !supplements.isEmpty { Text("\(supplements.count) 条") }
            }
        } footer: {
            Text("你添加的规则最先匹配，优先于方案里的所有规则。刷新或更新规则方案不会丢失。")
        }
    }

    private var sourcesSection: some View {
        Section {
            if sources.isEmpty {
                Text("方案里没有直接指向这个组的规则；它通常被其他策略组当作候选使用。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            ForEach(Array(sources.enumerated()), id: \.offset) { _, source in
                if RulesetPresentation.isList(source) {
                    Button { openedSource = source } label: {
                        HStack(spacing: 8) {
                            RulesetRow(ruleset: source, count: lineCounts[source])
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(SelectionIndicatorButtonStyle())
                    .moveDisabled(true)
                } else {
                    RulesetRow(ruleset: source, count: nil)
                        .moveDisabled(true)
                }
            }
        } header: {
            HStack {
                Text("方案里的规则")
                Spacer()
                if !sources.isEmpty { Text("\(sources.count) 项") }
            }
        } footer: {
            if !sources.isEmpty {
                Text("来自规则方案，只读。点开可查看和搜索其中每一条规则。")
            }
        }
    }
}

struct RulesetRow: View {
    let ruleset: RuleSchemeRuleset
    let count: Int?

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: RulesetPresentation.isList(ruleset) ? "list.bullet.rectangle" : "text.alignleft")
                .foregroundStyle(.secondary)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(RulesetPresentation.title(ruleset))
                    .font(RulesetPresentation.isList(ruleset) ? .body : .system(.body, design: .monospaced))
                    .lineLimit(1)
                Text(RulesetPresentation.source(ruleset))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            if let count {
                Text("\(count) 条")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// Read-only, searchable contents of one rule list.
/// The kinds a rule list is split into, matching the choices offered when
/// adding a site to a group.
enum RuleLineKind: CaseIterable, Hashable {
    case domainSuffix, domain, keyword, ipRange, other

    init(line: String) {
        let type = line.split(separator: ",", maxSplits: 1).first.map { $0.uppercased() } ?? ""
        switch type {
        case "DOMAIN-SUFFIX": self = .domainSuffix
        case "DOMAIN": self = .domain
        case "DOMAIN-KEYWORD": self = .keyword
        case "IP-CIDR", "IP-CIDR6": self = .ipRange
        default: self = .other
        }
    }

    var title: String {
        switch self {
        case .domainSuffix: String(localized: "含子域名")
        case .domain: String(localized: "仅此域名")
        case .keyword: String(localized: "关键词")
        case .ipRange: String(localized: "IP 段")
        case .other: String(localized: "其他")
        }
    }
}

struct RulesetContentView: View {
    @Environment(AppModel.self) private var model
    let ruleset: RuleSchemeRuleset
    @State private var lines: [String]?
    @State private var searchText = ""
    @State private var kind: RuleLineKind?

    private var counts: [RuleLineKind: Int] {
        (lines ?? []).reduce(into: [:]) { $0[RuleLineKind(line: $1), default: 0] += 1 }
    }

    private var visibleLines: [String] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let lines else { return [] }
        return lines.filter { line in
            (kind == nil || RuleLineKind(line: line) == kind)
                && (query.isEmpty || line.localizedCaseInsensitiveContains(query))
        }
    }

    private var kindPicker: some View {
        let counts = counts
        let kinds = RuleLineKind.allCases.filter { counts[$0, default: 0] > 0 }
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                kindButton(nil, title: String(localized: "全部"), count: lines?.count ?? 0)
                ForEach(kinds, id: \.self) { kind in
                    kindButton(kind, title: kind.title, count: counts[kind, default: 0])
                }
            }
            .padding(.horizontal, 16)
        }
    }

    private func kindButton(_ value: RuleLineKind?, title: String, count: Int) -> some View {
        Button {
            kind = value
        } label: {
            Text(verbatim: "\(title) \(count)")
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(kind == value ? Color.white : Color.primary)
                .padding(.horizontal, 13)
                .padding(.vertical, 8)
                .background(kind == value ? Color.accentColor : Color.secondary.opacity(0.1), in: Capsule())
        }
        .buttonStyle(SelectionIndicatorButtonStyle())
        .accessibilityAddTraits(kind == value ? .isSelected : [])
    }

    var body: some View {
        List {
            Section {
                if let url = ruleset.resource.downloadURL {
                    Text(verbatim: url.absoluteString)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            } header: {
                Text("来源")
            }
            if let lines {
                if ruleset.isBinaryRuleSet {
                    ContentUnavailableView("无法预览", systemImage: "doc.zipper", description: Text("这是 mihomo 的二进制规则集，只有对应客户端能读取。"))
                        .listRowBackground(Color.clear)
                } else if lines.isEmpty {
                    ContentUnavailableView("规则列表还没下载到本机", systemImage: "icloud.and.arrow.down", description: Text("回到规则页刷新这个方案后即可查看。"))
                        .listRowBackground(Color.clear)
                } else {
                    Section {
                        kindPicker
                            .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
                            .listRowBackground(Color.clear)
                    }
                    if visibleLines.isEmpty {
                        ContentUnavailableView.search(text: searchText)
                            .listRowBackground(Color.clear)
                    } else {
                        Section {
                            ForEach(Array(visibleLines.enumerated()), id: \.offset) { _, line in
                                RuleLineRow(line: line, showsKind: kind == nil)
                                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                            }
                        } header: {
                            Text("\(visibleLines.count) 条规则")
                        }
                    }
                }
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
            }
        }
        .navigationTitle(RulesetPresentation.title(ruleset))
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, prompt: "搜索这个列表")
        .task { lines = model.ruleLines(for: ruleset) }
        .accessibilityIdentifier("ruleset-content")
    }
}

private struct RuleLineRow: View {
    let line: String
    var showsKind = true

    var body: some View {
        let fields = line.split(separator: ",", maxSplits: 1).map(String.init)
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(verbatim: fields.count > 1 ? fields[1] : line)
                .font(.system(.subheadline, design: .monospaced))
                .textSelection(.enabled)
            Spacer(minLength: 8)
            if showsKind, fields.count > 1 {
                Text(Self.typeTitle(fields[0]))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize()
            }
        }
    }

    static func typeTitle(_ type: String) -> String {
        switch type.uppercased() {
        case "DOMAIN": String(localized: "仅此域名")
        case "DOMAIN-SUFFIX": String(localized: "含子域名")
        case "DOMAIN-KEYWORD": String(localized: "关键词")
        case "IP-CIDR", "IP-CIDR6": String(localized: "IP 段")
        default: type
        }
    }
}

/// Adds one domain or IP range to a group, showing what it covers and where
/// that traffic goes today before anything is saved.
struct AddSupplementRuleSheet: View {
    private let model: AppModel
    @Environment(\.dismiss) private var dismiss
    let scheme: RuleScheme
    let groupName: String
    @State private var kind: SupplementRule.Kind = .domainSuffix
    @State private var text: String
    @FocusState private var isFocused: Bool

    init(model: AppModel, scheme: RuleScheme, groupName: String, initialValue: String = "") {
        self.model = model
        self.scheme = scheme
        self.groupName = groupName
        _text = State(initialValue: initialValue)
    }

    private var parsed: Result<SupplementRule, Error> {
        Result { try SupplementRule.parse(text, kind: kind) }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("匹配方式", selection: $kind) {
                        ForEach(SupplementRule.Kind.allCases) { kind in
                            Text(kind.title).tag(kind)
                        }
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                }
                Section {
                    TextField(kind.placeholder, text: $text)
                        .font(.system(.body, design: .monospaced))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(kind == .ipRange ? .numbersAndPunctuation : .URL)
                        .focused($isFocused)
                        .submitLabel(.done)
                        .onSubmit(save)
                        .accessibilityIdentifier("supplement-rule-input")
                } footer: {
                    Text("可以直接粘贴网址，塔台会取出其中的域名。")
                }
                if !text.trimmingCharacters(in: .whitespaces).isEmpty {
                    preview
                }
            }
            .navigationTitle("添加到 \(RulePolicyPresentation.nameWithoutLeadingEmoji(groupName))")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("添加", action: save)
                        .disabled((try? parsed.get()) == nil)
                        .accessibilityIdentifier("supplement-rule-save")
                }
            }
            .onAppear { isFocused = true }
        }
        .presentationDetents([.medium, .large])
    }

    @ViewBuilder
    private var preview: some View {
        switch parsed {
        case .success(let rule):
            Section {
                Label(coverage(of: rule), systemImage: "scope")
                if let current = currentDestination(of: rule) {
                    Label(current, systemImage: "arrow.triangle.branch")
                        .foregroundStyle(.secondary)
                }
                if let owner = existingOwner(of: rule) {
                    Label("已添加到「\(owner)」，添加后会移到这里。", systemImage: "arrow.right.arrow.left")
                        .foregroundStyle(.orange)
                }
            } footer: {
                Text("添加后它会排在所有规则最前面，所以一定会走这个策略组。")
            }
            .font(.subheadline)
        case .failure(let error):
            Section {
                Label(error.localizedDescription, systemImage: "exclamationmark.triangle.fill")
                    .font(.subheadline)
                    .foregroundStyle(.orange)
            }
        }
    }

    private func coverage(of rule: SupplementRule) -> String {
        switch rule.kind {
        case .domainSuffix: String(localized: "匹配 \(rule.value) 及其所有子域名")
        case .domain: String(localized: "只匹配 \(rule.value)，不含子域名")
        case .keyword: String(localized: "匹配域名里含有「\(rule.value)」的网站")
        case .ipRange: String(localized: "匹配连接到 \(rule.value) 的流量")
        }
    }

    private func currentDestination(of rule: SupplementRule) -> String? {
        let host: String
        switch rule.kind {
        case .domain, .domainSuffix: host = rule.value
        case .ipRange: host = String(rule.value.split(separator: "/").first ?? "")
        case .keyword: return nil
        }
        guard let hit = model.probeRule(host: host, in: scheme).result.hit else { return nil }
        if hit.groupName == groupName { return String(localized: "目前已经走这个策略组") }
        return String(localized: "目前会走「\(RulePolicyPresentation.nameWithoutLeadingEmoji(hit.groupName))」")
    }

    private func existingOwner(of rule: SupplementRule) -> String? {
        model.customizableRuleGroups(for: scheme).map(\.name).first { name in
            name != groupName && model.supplementRules(forGroup: name, in: scheme).contains(rule)
        }
    }

    private func save() {
        guard let rule = try? parsed.get() else { return }
        model.addSupplementRule(rule, toGroup: groupName, in: scheme)
        model.showToast(
            String(localized: "已添加 \(rule.value)"),
            symbol: "checkmark.circle.fill",
            tone: .success
        )
        dismiss()
    }
}
