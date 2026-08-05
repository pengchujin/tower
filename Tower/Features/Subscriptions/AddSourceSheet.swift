import SwiftUI
import UIKit

struct AddSourceSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var sourceValue = ""
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var didReadPasteboard = false
    @FocusState private var focusedField: Field?

    private let detector = SourceInputDetector()

    private enum Field {
        case name
        case source
    }

    private var detectedKind: SourceInputKind {
        detector.detect(sourceValue)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("粘贴订阅链接或节点协议", text: $sourceValue, axis: .vertical)
                        .lineLimit(3...8)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($focusedField, equals: .source)
                        .accessibilityIdentifier("source-value-field")

                    Button {
                        pasteFromClipboard()
                    } label: {
                        Label("从剪贴板粘贴", systemImage: "doc.on.clipboard")
                    }

                    detectionLabel
                } header: {
                    Text("链接")
                } footer: {
                    Text("支持 HTTPS 订阅链接，以及 SS、SSR、VMess、VLESS、Trojan、Hysteria 2、AnyTLS、SOCKS5、HTTP(S) 自有节点。")
                }

                Section("名称（可选）") {
                    TextField("留空则自动命名", text: $name)
                        .textContentType(.organizationName)
                        .focused($focusedField, equals: .name)
                }

                if let errorMessage {
                    Section {
                        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .font(.subheadline)
                            .foregroundStyle(.orange)
                    }
                }

                Section {
                    PrivacyBadge()
                        .listRowBackground(Color.clear)
                } footer: {
                    Text("订阅内容、节点凭据和转换结果都只保存在这台设备上。")
                }
            }
            .navigationTitle("添加订阅或节点")
            .navigationBarTitleDisplayMode(.inline)
            .scrollDismissesKeyboard(.interactively)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(saveButtonTitle) {
                        Task { await save() }
                    }
                    .disabled(!detectedKind.isSupported || isSaving)
                    .accessibilityIdentifier("save-source")
                }
            }
            .interactiveDismissDisabled(isSaving)
            .onAppear {
                requestClipboardContent()
            }
            .onChange(of: sourceValue) {
                errorMessage = nil
            }
        }
    }

    @ViewBuilder
    private var detectionLabel: some View {
        switch detectedKind {
        case .subscription:
            Label("已识别为订阅链接", systemImage: "link.circle.fill")
                .foregroundStyle(Color.accentColor)
        case .node(let kind):
            Label("已识别为 \(kind.title) 节点", systemImage: kind.symbol)
                .foregroundStyle(.green)
        case .unknown:
            Label("等待有效的订阅链接或节点协议", systemImage: "questionmark.circle")
                .foregroundStyle(.secondary)
        }
    }

    private var saveButtonTitle: String {
        guard isSaving else { return "添加" }
        return detectedKind == .subscription ? "正在读取…" : "正在添加…"
    }

    private func requestClipboardContent() {
        guard !didReadPasteboard else { return }
        didReadPasteboard = true

        let clipboardValue = UIPasteboard.general.string?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if detector.detect(clipboardValue).isSupported {
            sourceValue = clipboardValue
            focusedField = nil
        } else {
            focusedField = .source
        }
    }

    private func pasteFromClipboard() {
        let clipboardValue = UIPasteboard.general.string?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !clipboardValue.isEmpty else {
            errorMessage = "剪贴板里没有可粘贴的文字"
            return
        }
        sourceValue = clipboardValue
        focusedField = nil
    }

    private func save() async {
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }

        do {
            switch detectedKind {
            case .subscription:
                try await model.addSubscription(name: name, urlString: sourceValue)
            case .node:
                try model.addLocalNode(name: name, uri: sourceValue)
            case .unknown:
                throw SubscriptionError.noSupportedNodes
            }
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
