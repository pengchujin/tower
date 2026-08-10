import SwiftUI
import UIKit

struct AddSourceSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    private let editingNode: ProxyNode?
    @State private var name = ""
    @State private var sourceValue = ""
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var didReadPasteboard = false
    @State private var entryMode: EntryMode = .paste
    @State private var manualDraft = ManualNodeDraft()
    @State private var customUserAgent = ""
    @State private var dnsOverHTTPSURL = ""
    @FocusState private var focusedField: Field?

    private let detector = SourceInputDetector()

    private enum Field {
        case name
        case source
    }

    private enum EntryMode: String, CaseIterable, Identifiable {
        case paste
        case scan
        case manual

        var id: String { rawValue }
        var title: String {
            switch self {
            case .paste: String(localized: "粘贴识别")
            case .scan: String(localized: "扫码")
            case .manual: String(localized: "手动添加")
            }
        }


        var symbol: String {
            switch self {
            case .paste: "doc.on.clipboard"
            case .scan: "qrcode.viewfinder"
            case .manual: "slider.horizontal.3"
            }
        }
    }

    init(editingNode: ProxyNode? = nil) {
        self.editingNode = editingNode
        _entryMode = State(initialValue: editingNode == nil ? .paste : .manual)
        _manualDraft = State(initialValue: editingNode.map { ManualNodeDraft(node: $0) } ?? ManualNodeDraft())
    }

    private var detectedKind: SourceInputKind {
        detector.detect(sourceValue)
    }

    var body: some View {
        NavigationStack {
            Form {
                if editingNode == nil {
                    sourceModePicker
                }

                switch entryMode {
                case .paste:
                    pasteSections
                case .scan:
                    scanSections
                case .manual:
                    manualSections
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
            .navigationTitle(editingNode == nil ? String(localized: "添加订阅或节点") : String(localized: "编辑"))
            .navigationBarTitleDisplayMode(.inline)
            .scrollDismissesKeyboard(.interactively)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(saveButtonTitle) {
                        focusedField = nil
                        Task { await save() }
                    }
                    .disabled(isSaveDisabled)
                    .accessibilityIdentifier("save-source")
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("完成") { focusedField = nil }
                }
            }
            .interactiveDismissDisabled(isSaving)
            .onAppear {
                if editingNode == nil { requestClipboardContent() }
            }
            .onChange(of: sourceValue) {
                errorMessage = nil
            }
            .onChange(of: entryMode) {
                focusedField = nil
                errorMessage = nil
            }
        }
    }

    private var sourceModePicker: some View {
        HStack(spacing: 8) {
            ForEach(EntryMode.allCases) { mode in
                Button {
                    entryMode = mode
                } label: {
                    VStack(spacing: 6) {
                        Image(systemName: mode.symbol)
                            .font(.headline.weight(.semibold))
                        Text(mode.title)
                            .font(.caption.weight(.semibold))
                            .lineLimit(1)
                    }
                    .foregroundStyle(entryMode == mode ? Color.white : Color.primary)
                    .frame(maxWidth: .infinity, minHeight: 62)
                    .background(
                        entryMode == mode ? Color.accentColor : Color.primary.opacity(0.055),
                        in: RoundedRectangle(cornerRadius: 15, style: .continuous)
                    )
                    .contentShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
                }
                .buttonStyle(ResponsivePressButtonStyle())
                .accessibilityAddTraits(entryMode == mode ? .isSelected : [])
            }
        }
        .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
        .listRowBackground(Color.clear)
    }

    @ViewBuilder
    private var pasteSections: some View {
        Section {
            TextField("粘贴订阅链接或节点协议", text: $sourceValue, axis: .vertical)
                .lineLimit(3...10)
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused($focusedField, equals: .source)
                .accessibilityIdentifier("source-value-field")

            Button {
                pasteFromClipboard()
            } label: {
                Label("从剪贴板重新粘贴", systemImage: "doc.on.clipboard")
            }

            detectionLabel
        } header: {
            Text("订阅或节点")
        } footer: {
            Text("可一次粘贴多条链接，每行一条。支持 HTTP 和 HTTPS 订阅，以及 SS、SSR、VMess、VLESS、Trojan、Hysteria 2、AnyTLS、SOCKS5、HTTP(S) 节点。HTTP 订阅会明文传输订阅地址和节点内容。")
        }

        Section("名称（可选）") {
            TextField("单条内容留空则自动命名", text: $name)
                .textContentType(.organizationName)
                .focused($focusedField, equals: .name)
        }

        Section {
            DisclosureGroup("高级请求设置") {
                TextField("自定义 User-Agent（可选）", text: $customUserAgent)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                TextField("DNS-over-HTTPS 地址（可选）", text: $dnsOverHTTPSURL)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
        } footer: {
            Text("只对这个订阅生效。DNS 请填写 https://…/dns-query 形式的加密解析地址。")
        }
    }

    @ViewBuilder
    private var scanSections: some View {
        Section {
            QRCodeScannerPreview { value in
                focusedField = nil
                sourceValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
                errorMessage = nil
            }
            .accessibilityIdentifier("scan-node-qr")

            if !sourceValue.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Label("已识别", systemImage: "checkmark.circle.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.green)
                    Text(sourceValue)
                        .font(.caption.monospaced())
                        .lineLimit(3)
                        .textSelection(.enabled)
                    detectionLabel
                }
            }
        } footer: {
            Text("支持订阅二维码，以及 SS、SSR、VMess、VLESS、Trojan、Hysteria 2、AnyTLS、SOCKS5、HTTP(S) 节点二维码。")
        }
    }

    @ViewBuilder
    private var manualSections: some View {
        Section("协议") {
            Picker("节点协议", selection: $manualDraft.kind) {
                ForEach(ManualNodeDraft.supportedKinds) { kind in
                    Text(kind.title).tag(kind)
                }
            }
            .onChange(of: manualDraft.kind) { _, selectedKind in
                manualDraft.applyDefaults(for: selectedKind)
            }
        }

        Section("节点") {
            TextField("名称（可选）", text: $manualDraft.name)
            TextField("服务器，例如 hk.example.com", text: $manualDraft.server)
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            TextField("端口", text: $manualDraft.port)
                .keyboardType(.numberPad)
        }

        Section("认证") {
            if [.shadowsocks, .shadowsocksR].contains(manualDraft.kind) {
                Picker("加密方式", selection: $manualDraft.cipher) {
                    ForEach(cipherOptions, id: \.self) { cipher in
                        Text(cipher).tag(cipher)
                    }
                }
            } else if manualDraft.kind == .vmess {
                Picker("数据加密", selection: $manualDraft.cipher) {
                    Text("自动").tag("auto")
                    Text("AES-128-GCM").tag("aes-128-gcm")
                    Text("ChaCha20-Poly1305").tag("chacha20-poly1305")
                }
            }
            if [.socks5, .http].contains(manualDraft.kind) {
                TextField("用户名（可选）", text: $manualDraft.username)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
            if [.vmess, .vless, .tuic].contains(manualDraft.kind) {
                TextField("UUID", text: $manualDraft.secret)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
            // TUIC authenticates with a UUID and a password, so it is the one
            // protocol that needs both fields rather than either one.
            if manualDraft.kind == .tuic {
                SecureField("密码", text: $manualDraft.password)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
            if ![.vmess, .vless, .tuic].contains(manualDraft.kind) {
                SecureField(secretPrompt, text: $manualDraft.secret)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
            if manualDraft.kind == .vmess {
                TextField("Alter ID", text: $manualDraft.alterID)
                    .keyboardType(.numberPad)
            }
            if manualDraft.kind == .snell {
                Picker("协议版本", selection: $manualDraft.version) {
                    ForEach((1 ... 6).map(String.init), id: \.self) { version in
                        Text("v\(version)").tag(version)
                    }
                }
            }
        }

        if manualDraft.kind == .shadowsocksR {
            Section("ShadowsocksR 参数") {
                Picker("协议", selection: $manualDraft.protocolName) {
                    ForEach(["origin", "auth_sha1_v4", "auth_aes128_md5", "auth_aes128_sha1", "auth_chain_a"], id: \.self) {
                        Text($0).tag($0)
                    }
                }
                TextField("协议参数（可选）", text: $manualDraft.protocolParam)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Picker("混淆", selection: $manualDraft.obfs) {
                    ForEach(["plain", "http_simple", "tls1.2_ticket_auth"], id: \.self) {
                        Text($0).tag($0)
                    }
                }
                TextField("混淆参数（可选）", text: $manualDraft.obfsParam)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
        }

        if [.shadowsocks, .snell].contains(manualDraft.kind) {
            Section("混淆（可选）") {
                Picker("模式", selection: $manualDraft.obfs) {
                    Text("关闭").tag("none")
                    Text("HTTP").tag("http")
                    Text("TLS").tag("tls")
                }
                if manualDraft.obfs != "none" {
                    TextField("混淆 Host", text: $manualDraft.obfsParam)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
            }
        }

        if manualDraft.kind == .hysteria2 {
            Section {
                Picker("混淆方式", selection: $manualDraft.obfs) {
                    Text("关闭").tag("none")
                    Text("Salamander").tag("salamander")
                }
                if manualDraft.obfs != "none" {
                    SecureField("混淆密码", text: $manualDraft.obfsParam)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
            } header: {
                Text("QUIC 混淆")
            } footer: {
                Text("混淆方式和密码必须与 Hysteria 2 服务端一致。")
            }
        }

        if manualDraft.kind == .hysteria {
            Section {
                TextField("上行带宽（Mbps）", text: $manualDraft.upMbps)
                    .keyboardType(.numberPad)
                TextField("下行带宽（Mbps）", text: $manualDraft.downMbps)
                    .keyboardType(.numberPad)
                Picker("传输协议", selection: $manualDraft.protocolName) {
                    Text("UDP").tag("udp")
                    Text("wechat-video").tag("wechat-video")
                    Text("faketcp").tag("faketcp")
                }
                TextField("混淆字符串（可选）", text: $manualDraft.obfs)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            } header: {
                Text("带宽与混淆")
            } footer: {
                Text("Hysteria 按带宽控制发送速率，上下行必须填写，按你的实际线路填。填错会明显变慢。")
            }
        }

        if manualDraft.kind == .tuic {
            Section {
                Picker("拥塞控制", selection: $manualDraft.congestionControl) {
                    Text("默认").tag("")
                    Text("BBR").tag("bbr")
                    Text("Cubic").tag("cubic")
                    Text("New Reno").tag("new_reno")
                }
                Picker("UDP 中继", selection: $manualDraft.udpRelayMode) {
                    Text("默认").tag("")
                    Text("native").tag("native")
                    Text("quic").tag("quic")
                }
            } header: {
                Text("QUIC 参数")
            } footer: {
                Text("不确定就保持默认，由客户端决定。")
            }
        }

        if manualDraft.kind == .anytls {
            Section {
                TextField("检查间隔（秒）", text: $manualDraft.idleSessionCheckInterval)
                    .keyboardType(.numberPad)
                TextField("空闲超时（秒）", text: $manualDraft.idleSessionTimeout)
                    .keyboardType(.numberPad)
                TextField("保留空闲会话数", text: $manualDraft.minIdleSession)
                    .keyboardType(.numberPad)
            } header: {
                Text("会话维护")
            } footer: {
                Text("默认 30 秒检查、30 秒超时、保留 0 个；不确定时保持默认。")
            }
        }

        if usesStreamTransport {
            Section("传输") {
                Picker("传输方式", selection: $manualDraft.transport) {
                    Text("TCP").tag("tcp")
                    Text("WebSocket").tag("ws")
                    Text("gRPC").tag("grpc")
                    Text("HTTP/2").tag("h2")
                }
                if ["ws", "h2"].contains(manualDraft.transport) {
                    TextField("Host（可选）", text: $manualDraft.hostHeader)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                if ["ws", "h2", "grpc"].contains(manualDraft.transport) {
                    TextField(manualDraft.transport == "grpc" ? "Service Name" : "路径，例如 /proxy", text: $manualDraft.path)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
            }
        }

        if offersSecurityPicker || usesMandatoryTLS {
            Section {
                if offersSecurityPicker {
                    Picker("安全方式", selection: $manualDraft.security) {
                        Text("无").tag("none")
                        Text("TLS").tag("tls")
                        if manualDraft.kind == .vless {
                            Text("REALITY").tag("reality")
                        }
                    }
                } else {
                    LabeledContent("安全方式", value: "TLS")
                }

                if usesTLSSettings {
                    TextField("SNI（可选）", text: $manualDraft.sni)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("ALPN（可选，如 h2,http/1.1）", text: $manualDraft.alpn)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Toggle("允许不安全证书", isOn: $manualDraft.skipCertificateVerification)
                }

                if manualDraft.kind == .vless && manualDraft.security == "reality" {
                    TextField("REALITY 服务器公钥", text: $manualDraft.realityPublicKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("Short ID（可选）", text: $manualDraft.realityShortID)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Picker("客户端指纹", selection: $manualDraft.fingerprint) {
                        ForEach(["chrome", "safari", "firefox", "edge", "random"], id: \.self) {
                            Text($0.capitalized).tag($0)
                        }
                    }
                    Picker("流控", selection: $manualDraft.flow) {
                        Text("无").tag("")
                        Text("XTLS Vision").tag("xtls-rprx-vision")
                    }
                }
            } header: {
                Text("传输安全")
            } footer: {
                if manualDraft.security == "reality" {
                    Text("REALITY 公钥必须与服务器一致；当前仅支持 TCP 或 gRPC 传输。")
                }
            }
        }
    }

    private var cipherOptions: [String] {
        if manualDraft.kind == .shadowsocksR {
            return ["aes-256-cfb", "aes-192-cfb", "aes-128-cfb", "chacha20-ietf", "none"]
        }
        return [
            "aes-256-gcm", "aes-128-gcm", "chacha20-ietf-poly1305",
            "2022-blake3-aes-128-gcm", "2022-blake3-aes-256-gcm"
        ]
    }

    private var usesStreamTransport: Bool {
        [.vmess, .vless, .trojan].contains(manualDraft.kind)
    }

    private var offersSecurityPicker: Bool {
        [.vmess, .vless, .socks5, .http].contains(manualDraft.kind)
    }

    private var usesMandatoryTLS: Bool {
        [.trojan, .hysteria, .hysteria2, .tuic, .anytls].contains(manualDraft.kind)
    }

    private var usesTLSSettings: Bool {
        usesMandatoryTLS || ["tls", "reality"].contains(manualDraft.security)
    }

    @ViewBuilder
    private var detectionLabel: some View {
        switch detectedKind {
        case .subscription:
            Label("已识别为订阅链接", systemImage: "link.circle.fill")
                .foregroundStyle(Color.accentColor)
        case .subscriptionBatch(let count):
            Label("已识别 \(count) 个订阅链接", systemImage: "link.badge.plus")
                .foregroundStyle(Color.accentColor)
        case .node(let kind):
            Label("已识别为 \(kind.title) 节点", systemImage: kind.symbol)
                .foregroundStyle(.green)
        case .nodeBatch(let count):
            Label("已识别 \(count) 个节点", systemImage: "square.stack.3d.up.fill")
                .foregroundStyle(.green)
        case .unknown:
            Label("等待有效的订阅链接或节点协议", systemImage: "questionmark.circle")
                .foregroundStyle(.secondary)
        }
    }

    private var saveButtonTitle: String {
        if editingNode != nil { return String(localized: "保存") }
        guard isSaving else { return String(localized: "添加") }
        switch detectedKind {
        case .subscription, .subscriptionBatch: return String(localized: "正在读取…")
        default: return String(localized: "正在添加…")
        }
    }

    private var isSaveDisabled: Bool {
        if isSaving { return true }
        if entryMode == .paste { return !detectedKind.isSupported }
        if entryMode == .scan { return !detectedKind.isSupported }
        return manualDraft.server.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || (Int(manualDraft.port).map { !(1 ... 65535).contains($0) } ?? true)
            || isMissingRequiredCredential
    }

    /// Whether the protocol's own required fields are still blank.
    ///
    /// The form used to enable 添加 as soon as a server and port were typed and
    /// then throw the real requirement back as an error afterwards. Validating
    /// inline is the same check, made before the tap instead of after it.
    private var isMissingRequiredCredential: Bool {
        func blank(_ value: String) -> Bool {
            value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        let needsSecret: [ProxyKind] = [
            .shadowsocks, .shadowsocksR, .vmess, .vless, .trojan,
            .hysteria, .hysteria2, .tuic, .anytls, .snell
        ]
        if needsSecret.contains(manualDraft.kind), blank(manualDraft.secret) { return true }
        if manualDraft.kind == .tuic, blank(manualDraft.password) { return true }
        if [.shadowsocks, .shadowsocksR].contains(manualDraft.kind), blank(manualDraft.cipher) {
            return true
        }
        if manualDraft.security == "reality", blank(manualDraft.realityPublicKey) { return true }
        if manualDraft.kind == .hysteria {
            let up = Int(manualDraft.upMbps) ?? 0
            let down = Int(manualDraft.downMbps) ?? 0
            if up <= 0 || down <= 0 { return true }
        }
        return false
    }

    private var secretPrompt: String {
        switch manualDraft.kind {
        case .shadowsocks, .shadowsocksR: String(localized: "密码")
        case .trojan, .hysteria2, .anytls, .snell: String(localized: "密码或 PSK")
        case .hysteria: String(localized: "认证密码")
        case .socks5, .http: String(localized: "密码（可选）")
        default: String(localized: "认证信息")
        }
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
            errorMessage = String(localized: "等待有效的订阅链接或节点协议")
            return
        }
        sourceValue = clipboardValue
        focusedField = nil
    }

    private func save() async {
        focusedField = nil
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }

        do {
            if entryMode == .manual {
                if let editingNode {
                    try model.updateLocalNode(editingNode, with: manualDraft)
                } else {
                    try model.addManualNode(manualDraft)
                }
            } else {
                switch detectedKind {
                case .subscription:
                    try await model.addSubscription(
                        name: name,
                        urlString: sourceValue,
                        userAgent: customUserAgent,
                        dnsOverHTTPSURL: dnsOverHTTPSURL
                    )
                case .subscriptionBatch:
                    try await model.addSubscriptions(
                        name: name,
                        urlStrings: detector.subscriptionURLs(sourceValue),
                        userAgent: customUserAgent,
                        dnsOverHTTPSURL: dnsOverHTTPSURL
                    )
                case .node:
                    try model.addLocalNode(name: name, uri: sourceValue)
                case .nodeBatch:
                    try model.addLocalNodes(name: name, content: sourceValue)
                case .unknown:
                    throw SubscriptionError.noSupportedNodes
                }
            }
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
