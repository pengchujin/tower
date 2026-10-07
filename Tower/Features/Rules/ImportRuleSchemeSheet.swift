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
                // The same segmented control as adding a subscription: one
                // quiet track and a raised segment, not three tiles where the
                // selected one is a solid accent block.
                Section {
                    HStack(spacing: 4) {
                        ForEach(Source.allCases) { mode in
                            Button { source = mode } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: mode.symbol)
                                    Text(mode.title)
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.75)
                                }
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(source == mode ? Color.accentColor : Color.secondary)
                                .frame(maxWidth: .infinity, minHeight: 40)
                                .background {
                                    if source == mode {
                                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                                            .fill(Color(uiColor: .secondarySystemGroupedBackground))
                                            .shadow(color: .black.opacity(0.08), radius: 3, y: 1)
                                    }
                                }
                                .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            }
                            .buttonStyle(ResponsivePressButtonStyle())
                            .accessibilityAddTraits(source == mode ? .isSelected : [])
                            .accessibilityIdentifier("scheme-import-source-\(mode.rawValue)")
                        }
                    }
                    .padding(4)
                    .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
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
                        Text("支持 Clash / Mihomo、Surge 和 subconverter 配置。GitHub、Gitee 网页地址会自动转为文件地址。")
                    }
                } else if source == .text {
                    Section {
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
                    } header: {
                        Text("配置文本")
                    } footer: {
                        Text("支持 Clash / Mihomo、Surge 和 subconverter 配置。")
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
                // What an import brings in, said once at the end instead of
                // as a second paragraph repeating the formats.
                Section {
                    TextField("留空则自动命名", text: $name)
                        .accessibilityIdentifier("scheme-import-name")
                } header: {
                    Text("名称（可选）")
                } footer: {
                    Text("只导入规则和策略组，不导入节点；策略组使用塔台中已启用的节点，引用的规则列表会下载到本机。")
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
                                    .animation(TowerMotion.selection(reduceMotion: reduceMotion), value: importProgress)
                            }
                        }
                        .padding(24)
                        .transition(TowerMotion.surfaceTransition(reduceMotion: reduceMotion))
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .animation(TowerMotion.surface(reduceMotion: reduceMotion),
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
