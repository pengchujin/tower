import SwiftUI
import UniformTypeIdentifiers

struct ImportRuleSchemeSheet: View {
    private enum Source: String, CaseIterable, Identifiable {
        case link, text, file
        var id: Self { self }
        var symbol: String {
            switch self {
            case .link: "link"
            case .text: "doc.on.clipboard"
            case .file: "folder"
            }
        }
        var title: String {
            switch self {
            case .link: String(localized: "链接")
            case .text: String(localized: "文本")
            case .file: String(localized: "文件")
            }
        }
    }
    private enum Field { case url, text }

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var source: Source = .link
    @State private var requestsDiscard = false
    @State private var urlString = ""
    @State private var configurationText = ""
    @State private var fileText = ""
    @State private var fileName: String?
    @State private var showsFilePicker = false
    @State private var name = ""
    @State private var errorMessage: String?
    @State private var importProgress: RuleImportProgress?
    @State private var downloadError: RuleImportDownloadError?
    @State private var isSaving = false
    @State private var saveTask: Task<Void, Never>?
    @FocusState private var focusedField: Field?

    private var inputIsEmpty: Bool {
        let input = source == .link ? urlString : source == .text ? configurationText : fileText
        return input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 8) {
                        ForEach(Source.allCases) { mode in
                            Button { source = mode } label: {
                                VStack(spacing: 6) {
                                    Image(systemName: mode.symbol)
                                        .font(.headline.weight(.semibold))
                                    Text(mode.title)
                                        .font(.caption.weight(.semibold))
                                        .lineLimit(1)
                                }
                                .foregroundStyle(source == mode ? Color.white : Color.primary)
                                .frame(maxWidth: .infinity, minHeight: 62)
                                .background(
                                    source == mode ? Color.accentColor : Color.primary.opacity(0.055),
                                    in: RoundedRectangle(cornerRadius: 15, style: .continuous)
                                )
                                .contentShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
                            }
                            .buttonStyle(ResponsivePressButtonStyle())
                            .accessibilityAddTraits(source == mode ? .isSelected : [])
                            .accessibilityIdentifier("scheme-import-source-\(mode.rawValue)")
                        }
                    }
                    .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
                    .listRowBackground(Color.clear)
                }
                if source == .link {
                    Section {
                        TextField("https://…", text: $urlString, axis: .vertical)
                            .lineLimit(2...6)
                            .keyboardType(.URL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .focused($focusedField, equals: .url)
                            .accessibilityIdentifier("scheme-url-field")
                    } header: {
                        Text("规则配置地址")
                    } footer: {
                        Text("支持 Clash YAML、subconverter（`.ini`）和 Surge 配置。塔台会下载配置及其引用的规则列表并保存在本机。粘贴 GitHub、Gitee 的网页地址也可以，会自动转成文件本身的地址。")
                    }
                } else if source == .text {
                    Section("配置文本") {
                        PasteButton(payloadType: String.self) { values in
                            if let value = values.first { configurationText = value }
                        }
                        TextEditor(text: $configurationText)
                            .font(.system(.footnote, design: .monospaced))
                            .frame(minHeight: 230)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .focused($focusedField, equals: .text)
                            .accessibilityIdentifier("scheme-text-field")
                    }
                } else {
                    Section {
                        if let fileName { Text(verbatim: fileName).textSelection(.enabled) }
                        Button {
                            focusedField = nil
                            showsFilePicker = true
                        } label: {
                            Label("选择配置文件", systemImage: "doc.badge.plus")
                        }
                        .accessibilityIdentifier("scheme-file-picker")
                    } header: {
                        Text("配置文件")
                    } footer: {
                        Text("支持 .yaml、.yml、.conf、.ini、.json 和 .txt 文本配置。")
                    }
                }
                Section {
                    Text("支持完整 Clash / Mihomo、Surge 和 subconverter 配置。仅提取规则、策略组和支持的网络设置，不导入节点。节点名称筛选会保留，实际匹配塔台已启用的节点；引用的 HTTPS 规则列表会下载并保存在本机。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section("名称（可选）") {
                    TextField("留空则自动命名", text: $name)
                        .accessibilityIdentifier("scheme-import-name")
                }
            }
            .disabled(isSaving)
            .navigationTitle("导入规则")
            .navigationBarTitleDisplayMode(.inline)
            .confirmDiscardChanges(hasChanges: !urlString.isEmpty || !configurationText.isEmpty || fileName != nil || !name.isEmpty,
                isBusy: isSaving, requested: $requestsDiscard) { cancel() }
            .onDisappear { cancel() }
            .scrollDismissesKeyboard(.interactively)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        if isSaving { cancel() }
                        else { requestsDiscard = true }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "正在导入…" : "导入") {
                        saveTask = Task { await save() }
                    }
                    .disabled(inputIsEmpty || isSaving)
                    .accessibilityIdentifier("save-scheme")
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("收起键盘") { focusedField = nil }
                }
            }
            .fileImporter(isPresented: $showsFilePicker, allowedContentTypes: [.data]) { result in
                switch result {
                case .success(let url):
                    saveTask = Task { await readFile(url) }
                case .failure(let error):
                    if (error as? CocoaError)?.code != .userCancelled { errorMessage = error.localizedDescription }
                }
            }
            .onAppear { focusedField = .url }
            .onChange(of: source) { _, value in
                clearImportError()
                focusedField = value == .link ? .url : value == .text ? .text : nil
            }
            .onChange(of: urlString) { clearImportError() }
            .onChange(of: configurationText) { clearImportError() }
        }
        .disabled(showsTaskOverlay)
        .accessibilityHidden(showsTaskOverlay)
        .overlay {
            GeometryReader { geometry in
                ZStack {
                    if showsTaskOverlay {
                        Color.black.opacity(0.18)
                            .ignoresSafeArea()
                            .accessibilityHidden(true)
                            .transition(.opacity)
                        Group {
                            if let errorMessage {
                                RuleImportFailureCard(
                                    message: errorMessage, downloadError: downloadError,
                                    maximumDetailsHeight: max(80, min(280, geometry.size.height - 330)),
                                    onConfirm: clearImportError
                                )
                            } else if let importProgress, isSaving {
                                TaskProgressCard(title: importProgress.title, sources: importProgress.sources,
                                    message: "可随时取消，已填写的内容会保留。", identifier: "scheme-import-progress", onCancel: cancel)
                            }
                        }
                        .padding(24)
                        .transition(reduceMotion ? .opacity : .scale(scale: 0.96).combined(with: .opacity))
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .animation(reduceMotion ? .easeOut(duration: 0.16) : .spring(response: 0.3, dampingFraction: 1),
                    value: showsTaskOverlay)
                .animation(.easeOut(duration: reduceMotion ? 0.12 : 0.18), value: errorMessage != nil)
            }
        }
    }

    private var showsTaskOverlay: Bool {
        errorMessage != nil || (isSaving && importProgress != nil)
    }

    private func clearImportError() {
        errorMessage = nil
        downloadError = nil
    }

    private func cancel() {
        saveTask?.cancel()
        if isSaving { model.cancelRuleImport() }
    }

    private func readFile(_ url: URL) async {
        isSaving = true
        clearImportError()
        defer { isSaving = false }
        do {
            let content = try await Task.detached(priority: .userInitiated) {
                try RuleSchemeImportService.readConfigurationFile(at: url)
            }.value
            try Task.checkCancellation()
            fileText = content
            fileName = url.lastPathComponent
        } catch {
            guard !Task.isCancelled else { return }
            errorMessage = error.localizedDescription
        }
    }

    private func save() async {
        isSaving = true
        errorMessage = nil
        focusedField = nil
        downloadError = nil
        defer { isSaving = false; importProgress = nil }
        let progress: RuleImportProgressHandler = { value in
            guard !Task.isCancelled else { return }
            importProgress = value
        }
        do {
            switch source {
            case .link: try await model.importScheme(name: name, urlString: urlString, progress: progress)
            case .text: try await model.importScheme(name: name, text: configurationText, progress: progress)
            case .file: try await model.importScheme(name: name, text: fileText, fileName: fileName, progress: progress)
            }
            dismiss()
        } catch {
            guard !Task.isCancelled, !(error is CancellationError) else { return }
            downloadError = error as? RuleImportDownloadError
            errorMessage = error.localizedDescription
        }
    }
}

/// Errors stay in the same task layer; details scroll without moving the form.
private struct RuleImportFailureCard: View {
    let message: String
    let downloadError: RuleImportDownloadError?
    let maximumDetailsHeight: CGFloat
    let onConfirm: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.largeTitle)
                .foregroundStyle(.orange)
                .accessibilityHidden(true)
            Text("导入失败")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let downloadError {
                        Text("下载未完成，尚未导入。")
                            .foregroundStyle(.secondary)
                        ForEach(downloadError.failures.indices, id: \.self) { index in
                            let failure = downloadError.failures[index]
                            VStack(alignment: .leading, spacing: 4) {
                                Text(verbatim: RuleImportDownloadFailure.sourceName(failure.url))
                                    .fontWeight(.medium)
                                Text(verbatim: failure.reason)
                                    .foregroundStyle(.secondary)
                            }
                            .accessibilityElement(children: .combine)
                        }
                    } else {
                        Text(verbatim: message)
                    }

                }
                .font(.footnote)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
            }
            .frame(maxHeight: maximumDetailsHeight)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier("scheme-import-error-details")
            Button(action: onConfirm) {
                Text("确定")
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .padding(.vertical, 2)
                    .foregroundStyle(.white)
                    .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 14))
                    .contentShape(RoundedRectangle(cornerRadius: 14))
            }
            .buttonStyle(ResponsivePressButtonStyle())
            .accessibilityIdentifier("scheme-import-error-confirm")
        }
        .padding(24)
        .frame(maxWidth: 340)
        .modifier(TaskModalSurface())
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
        .accessibilityIdentifier("scheme-import-error")
    }

}
