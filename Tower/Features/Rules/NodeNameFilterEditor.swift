import SwiftUI

/// Creation shares the candidate editor's navigation stack, including on Mac.
struct CustomNodeFilterCreator: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let scheme: RuleScheme
    let onCreated: (String) -> Void
    @State private var name = ""
    @State private var pattern = ""
    @State private var kind: RuleSchemeGroup.Kind = .urlTest
    @State private var previewResult: NodeNameFilterPreviewResult?
    @State private var saveError: String?

    private var previewInput: NodeNameFilterPreviewInput {
        .init(patterns: [pattern], candidates: model.enabledNodes.map {
            let node = model.nodeForPresentation($0)
            return [NodeRegionResolver.displayName(for: node), node.name]
        }, insensitive: true)
    }

    var body: some View {
        Form {
            Section {
                TextField("节点组名称", text: $name)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                    .accessibilityIdentifier("custom-node-filter-name")
                Picker("策略类型", selection: $kind) {
                    ForEach([RuleSchemeGroup.Kind.select, .urlTest, .fallback], id: \.self) {
                        Text($0.displayTitle).tag($0)
                    }
                }
            }
            Section("节点名称匹配") {
                NodeNameFilterFields(pattern: $pattern, caseInsensitiveDefault: true)
            }
            NodeNameFilterPreview(input: previewInput, result: previewResult)
            if let saveError {
                Section { Text(saveError).foregroundStyle(.red) }
            }
        }
        .navigationTitle("自定义节点筛选")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("保存") {
                    do {
                        let group = try model.createNodeFilterGroup(name: name, pattern: pattern, kind: kind, for: scheme)
                        onCreated(group.name)
                        dismiss()
                    } catch { saveError = error.localizedDescription }
                }
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || pattern.isEmpty
                          || previewResult?.input != previewInput || previewResult?.error != nil)
                .accessibilityIdentifier("custom-node-filter-save")
            }
        }
        .onAppear {
            if name.isEmpty { name = uniqueName(String(localized: "自定义节点")) }
        }
        .task(id: previewInput) {
            let input = previewInput
            do { try await Task.sleep(for: .milliseconds(300)) } catch { return }
            let result = await input.evaluate()
            guard !Task.isCancelled, input == previewInput else { return }
            previewResult = result
        }
    }

    private func uniqueName(_ base: String) -> String {
        let names = model.customizableRuleGroups(for: scheme).map(\.name)
            + scheme.routingTargetGroupNames()
        var candidate = base
        var suffix = 2
        while names.contains(where: { $0.caseInsensitiveCompare(candidate) == .orderedSame }) {
            candidate = "\(base) \(suffix)"
            suffix += 1
        }
        return candidate
    }
}

/// Inline fields in the group draft. The group owns the only Save action.
struct NodeNameFilterFields: View {
    @Binding var pattern: String
    let caseInsensitiveDefault: Bool
    private let originalPattern: String
    private let initialDraft: NodeNameFilterDraft
    @State private var draft: NodeNameFilterDraft
    @State private var keywords: [Keyword]
    @FocusState private var focusedKeyword: UUID?
    @Environment(\.layoutDirection) private var layoutDirection

    private struct Keyword: Identifiable, Equatable {
        let id = UUID()
        var value: String
    }

    init(pattern: Binding<String>, caseInsensitiveDefault: Bool) {
        _pattern = pattern
        self.caseInsensitiveDefault = caseInsensitiveDefault
        originalPattern = pattern.wrappedValue
        let initial = NodeNameFilterDraft(pattern: pattern.wrappedValue, caseInsensitiveDefault: caseInsensitiveDefault)
        initialDraft = initial
        _draft = State(initialValue: initial)
        _keywords = State(initialValue: Self.tokens(initial.keywords))
    }

    private static func tokens(_ text: String) -> [Keyword] {
        text.split(whereSeparator: \.isNewline).map { Keyword(value: String($0)) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if draft.usesRegex {
                TextEditor(text: $draft.regex)
                    .font(.system(.footnote, design: .monospaced))
                    .frame(minHeight: 100)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                    .accessibilityIdentifier("node-filter-regex")
                Button("切换到关键词编辑") {
                    if let simple = NodeNameFilterDraft.decode(draft.regex, caseInsensitiveDefault: caseInsensitiveDefault) {
                        keywords = Self.tokens(simple.keywords)
                        draft = simple
                    }
                }
                .disabled(NodeNameFilterDraft.decode(draft.regex, caseInsensitiveDefault: caseInsensitiveDefault) == nil)
                Text("| 表示任一项，^ 表示名称开头，$ 表示结尾，(?i) 表示忽略大小写。复杂表达式保持原文，不会自动拆成关键词。")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                HStack {
                    Text("匹配方式")
                    Spacer()
                    Picker("匹配方式", selection: $draft.style) {
                        ForEach(NodeNameFilterDraft.MatchStyle.allCases) { style in
                            Text(style.title).tag(style)
                        }
                    }
                    .labelsHidden().pickerStyle(.menu)
                    .accessibilityIdentifier("node-filter-match-style")
                    .fixedSize(horizontal: true, vertical: false)
                }
                KeywordFlowLayout(rightToLeft: layoutDirection == .rightToLeft) {
                    ForEach(keywords) { keyword in
                        keywordChip(keyword)
                    }
                }
                .accessibilityHint("点击标签直接修改，点击 × 删除；关键词之间是“任意匹配”，空格属于关键词的一部分。")
                Button {
                    let keyword = Keyword(value: "")
                    keywords.append(keyword)
                    focusedKeyword = keyword.id
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "plus")
                        Text("添加关键词")
                    }
                    .font(.subheadline)
                    .fixedSize(horizontal: true, vertical: false)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.accentColor)
                .accessibilityIdentifier("node-keyword-add")
                Text("例如 jp、hk，可筛选名称中包含这些文字的节点；多个关键词满足任意一个即可。")
                    .font(.footnote).foregroundStyle(.secondary)
                    .accessibilityIdentifier("node-keyword-help")
                Divider().padding(.vertical, 6)
                Toggle("忽略大小写", isOn: $draft.ignoresCase)
                    .font(.subheadline)
                    .frame(minHeight: 44)
                Button("切换到正则表达式") {
                    draft.regex = draft.pattern
                    draft.usesRegex = true
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.accentColor)
                .font(.subheadline)
                .frame(minHeight: 44)
            }
        }
        .padding(.vertical, 4)
        // Keep synchronization on the visible field container, never a separate
        // lazy list row that might not exist when the user taps Save.
        .onChange(of: keywords) { _, values in
            draft.keywords = values.map(\.value).joined(separator: "\n")
        }
        .onChange(of: draft) { _, value in
            pattern = value == initialDraft ? originalPattern : value.pattern
        }
        .onChange(of: draft.style) { _, _ in
            focusedKeyword = nil
        }
    }

    private func keywordChip(_ keyword: Keyword) -> some View {
        HStack(spacing: 4) {
            Text(verbatim: keyword.value.isEmpty ? String(localized: "关键词") : keyword.value)
                .lineLimit(1).hidden()
                .frame(minWidth: 20, minHeight: 44)
                .overlay(alignment: .leading) {
                    TextField("关键词", text: Binding(
                        get: { keywords.first { $0.id == keyword.id }?.value ?? "" },
                        set: { value in
                            guard let index = keywords.firstIndex(where: { $0.id == keyword.id }) else { return }
                            keywords[index].value = value
                        }
                    ))
                    .textFieldStyle(.plain)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                    .focused($focusedKeyword, equals: keyword.id)
                    .submitLabel(.done)
                    .onSubmit { focusedKeyword = nil }
                    .accessibilityIdentifier("node-keyword-input")
                }

            Button {
                keywords.removeAll { $0.id == keyword.id }
            } label: {
                Image(systemName: "xmark").font(.caption.weight(.semibold))
                    .frame(width: 28, height: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("删除关键词 \(keyword.value)")
        }
        .font(.subheadline)
        .padding(.leading, 10).padding(.trailing, 2)
        .foregroundStyle(Color.accentColor)
        .background {
            Capsule().fill(Color.accentColor.opacity(0.09)).padding(.vertical, 5)
        }
        .overlay {
            Capsule().strokeBorder(Color.accentColor.opacity(0.15), lineWidth: 1)
                .padding(.vertical, 5).allowsHitTesting(false)
        }
        .accessibilityElement(children: .contain)
    }
}

/// Wrapping chips retain their intrinsic widths up to the available row width.
/// Bounded proposals also keep long keywords and large accessibility text inside
/// the form, while the text field can scroll its own text during editing.
private struct KeywordFlowLayout: Layout {
    var rightToLeft = false
    let spacing: CGFloat = 6

    private func frames(_ subviews: Subviews, width: CGFloat) -> (frames: [CGRect], size: CGSize) {
        var frames: [CGRect] = []
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, usedWidth: CGFloat = 0
        for view in subviews {
            let ideal = view.sizeThatFits(.unspecified)
            let size = view.sizeThatFits(ProposedViewSize(width: min(ideal.width, width), height: nil))
            let itemWidth = min(size.width, width)
            if x > 0 && x + itemWidth > width {
                x = 0; y += rowHeight + spacing; rowHeight = 0
            }
            frames.append(CGRect(x: x, y: y, width: itemWidth, height: size.height))
            usedWidth = max(usedWidth, x + itemWidth)
            x += itemWidth + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return (frames, CGSize(width: usedWidth, height: y + rowHeight))
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = max(1, proposal.width ?? 320)
        return CGSize(width: width, height: frames(subviews, width: width).size.height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for (view, frame) in zip(subviews, frames(subviews, width: bounds.width).frames) {
            let x = rightToLeft ? bounds.maxX - frame.maxX : bounds.minX + frame.minX
            view.place(at: CGPoint(x: x, y: bounds.minY + frame.minY), anchor: .topLeading,
                       proposal: ProposedViewSize(frame.size))
        }
    }
}

struct NodeNameFilterPreviewInput: Hashable, Sendable {
    let patterns: [String]
    let candidates: [[String]]
    let insensitive: Bool

    func evaluate() async -> NodeNameFilterPreviewResult {
        await Task.detached(priority: .userInitiated) {
            do {
                var selected = Set<Int>()
                let deadline = ProcessInfo.processInfo.systemUptime + 1
                for pattern in patterns {
                    let remaining = deadline - ProcessInfo.processInfo.systemUptime
                    guard remaining > 0 else { throw NodeNameFilterMatcher.Failure.timedOut }
                    selected.formUnion(try NodeNameFilterMatcher.preview(pattern, candidates: candidates,
                        caseInsensitive: insensitive, timeLimit: remaining))
                }
                return NodeNameFilterPreviewResult(input: self, matches: selected.sorted(), error: nil)
            } catch {
                return NodeNameFilterPreviewResult(input: self, matches: [], error: error.localizedDescription)
            }
        }.value
    }
}

struct NodeNameFilterPreviewResult: Sendable {
    let input: NodeNameFilterPreviewInput
    let matches: [Int]
    let error: String?
}

struct NodeNameFilterPreview: View {
    let input: NodeNameFilterPreviewInput
    let result: NodeNameFilterPreviewResult?

    var body: some View {
        Section {
            if input.patterns.allSatisfy({ $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
                Text("请添加关键词")
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("node-filter-empty-prompt")
            } else if let result, result.input == input {
                if let error = result.error {
                    Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.red)
                } else {
                    Text("匹配 \(result.matches.count) / \(input.candidates.count) 个节点")
                        .accessibilityIdentifier("node-filter-match-count")
                    if result.matches.isEmpty {
                        Text("暂无匹配节点。可以保存以匹配以后新增的节点，也可以调整关键词。")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(Array(result.matches.prefix(30)), id: \.self) { index in
                        Text(input.candidates[index].first ?? "").textSelection(.enabled)
                    }
                    if result.matches.count > 30 { Text("仅展示前 30 个匹配名称。").foregroundStyle(.secondary) }
                }
            } else {
                ProgressView("正在匹配…")
            }
        } header: {
            Text("名称匹配预览")
        } footer: {
            Text("基于已启用且勾选的本地节点。来源限制、其他排除条件与客户端支持的协议仍会影响最终候选；未下载的节点无法预览。")
        }
    }
}
