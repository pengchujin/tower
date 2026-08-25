import SwiftUI
import UIKit

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var configurationNameDraft: ConfigurationNameDraft
    let openLANSharing: () -> Void

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 22) {
                NodeAndExportSettingsCard(configurationNameDraft: $configurationNameDraft)
                LANSharingSettingsRow {
                    openLANSharing()
                    dismiss()
                }
                CloudSyncCard()
                SecurityAndSourceLink()
                ResetAllConfigurationCard(configurationNameDraft: $configurationNameDraft)
            }
            .padding(.horizontal, TowerTheme.pagePadding)
            .padding(.top, 12)
            .padding(.bottom, 28)
        }
        .background(TowerTheme.background.ignoresSafeArea())
        .navigationTitle("设置")
    }
}

/// Reset is intentionally the last setting and requires a stable alert.
///
/// A destructive confirmation dialog anchored to a scrolling row can appear
/// to drift on iPad. An alert stays centered and gives the consequences enough
/// room to remain readable on every device size.
private struct ResetAllConfigurationCard: View {
    @Environment(AppModel.self) private var model
    @Binding var configurationNameDraft: ConfigurationNameDraft
    @State private var isConfirmingReset = false
    @State private var isResetting = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeading(title: "重置", detail: String(localized: "不可撤销"))

            Button(role: .destructive) {
                isConfirmingReset = true
            } label: {
                HStack(spacing: 13) {
                    Image(systemName: "arrow.counterclockwise.circle.fill")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(.red)
                        .frame(width: 48, height: 48)
                        .background(
                            Color.red.opacity(0.1),
                            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                        )

                    VStack(alignment: .leading, spacing: 2) {
                        Text("重置所有配置")
                            .font(.headline)
                            .foregroundStyle(.red)
                        Text("删除订阅、节点和这台设备上的设置")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    if isResetting {
                        ProgressView()
                    } else {
                        Image(systemName: "chevron.right")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.tertiary)
                    }
                }
                .padding(16)
                .contentShape(Rectangle())
                .towerCard()
            }
            .buttonStyle(ResponsivePressButtonStyle())
            .disabled(model.isCloudSyncing || isResetting)
            .accessibilityIdentifier("reset-all-configuration")
        }
        .alert("重置所有配置？", isPresented: $isConfirmingReset) {
            Button("重置所有配置", role: .destructive) {
                isResetting = true
                Task { @MainActor in
                    await model.resetAllConfiguration()
                    configurationNameDraft = ConfigurationNameDraft(text: TowerBrand.localizedName)
                    isResetting = false
                }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("将清除这台设备上的订阅、自建节点、规则自定义、导出偏好和本机缓存，并关闭续费提醒、局域网共享及 iCloud 同步。此操作无法撤销；iCloud 上的副本不会被删除，系统权限也不会改变。")
        }
    }
}

/// Off by default, like everything else here that reaches the network.
///
/// iOS does not run Tower in the background, so this fetches when the app is
/// opened or comes back to the foreground, never on a schedule. The row is
/// named for that moment — "打开塔台时" — rather than promising the
/// subscription stays current on its own.
private struct AutoRefreshSection: View {
    @Environment(AppModel.self) private var model

    private var binding: Binding<Bool> {
        Binding(get: { model.autoRefreshOnOpen }, set: model.setAutoRefreshOnOpen)
    }

    var body: some View {
        Toggle(isOn: binding) {
            SettingsRowLabel(
                symbol: "arrow.clockwise",
                color: .green,
                title: "打开塔台时更新订阅",
                resolvedDetail: model.autoRefreshOnOpen
                    ? String(localized: "每次打开或切回塔台时刷新一次")
                    : String(localized: "只在您下拉刷新时更新")
            )
        }
    }
}

/// Off by default, and deliberately not phrased as a convenience.
///
/// Everything else in Tower keeps the subscription on the device. Turning this
/// on is the one action that changes that, so the card says what actually
/// happens rather than "sync your settings" — the user is agreeing to put
/// subscription URLs and node passwords in their iCloud account.
private struct CloudSyncCard: View {
    @Environment(AppModel.self) private var model
    @State private var isConfirming = false
    @State private var isConfirmingDisable = false

    private var binding: Binding<Bool> {
        Binding(
            get: { model.iCloudSyncEnabled },
            set: { wantsOn in
                if wantsOn {
                    isConfirming = true
                } else {
                    // Switching off is also the moment to offer taking the
                    // uploaded credentials back out of iCloud, which is the
                    // only place in Tower where they ever left the device.
                    isConfirmingDisable = true
                }
            }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeading(title: "iCloud 同步", detail: String(localized: "默认关闭"))
            VStack(alignment: .leading, spacing: 13) {
                Toggle(isOn: binding) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("同步到我的 iCloud")
                            .font(.subheadline.weight(.semibold))
                        Text(statusText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .disabled(model.isCloudSyncing)

                if model.iCloudSyncEnabled {
                    Divider()
                    Button {
                        Task { await model.synchronizeWithCloud(showResult: true) }
                    } label: {
                        Label(
                            model.isCloudSyncing ? "正在同步…" : "立即同步",
                            systemImage: "arrow.triangle.2.circlepath"
                        )
                        .font(.subheadline.weight(.semibold))
                    }
                    .disabled(model.isCloudSyncing)
                }

                if !model.iCloudSyncEnabled {
                    Divider()
                    Button(role: .destructive) {
                        Task { await model.removeCloudSnapshot() }
                    } label: {
                        Label("删除 iCloud 上的副本", systemImage: "trash")
                            .font(.subheadline.weight(.semibold))
                    }
                    .accessibilityIdentifier("remove-cloud-snapshot")
                }

                Divider()
                Label(
                    "开启后，订阅地址和节点密码会存进您的 iCloud 账户。两台设备都改过时，以最后保存的那份为准。",
                    systemImage: "info.circle"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
            .padding(17)
            .towerCard()
        }
        .alert("开启 iCloud 同步？", isPresented: $isConfirming) {
            Button("开启") { Task { await model.setICloudSyncEnabled(true) } }
            Button("取消", role: .cancel) {}
        } message: {
            Text("您的订阅地址和节点密码会上传到您自己的 iCloud 账户，用于在同一 Apple 账户的设备之间同步。它们不会发给塔台或任何第三方。关闭同步后可以选择一并删除 iCloud 上的副本。")
        }
        .confirmationDialog(
            "关闭 iCloud 同步？",
            isPresented: $isConfirmingDisable,
            titleVisibility: .visible
        ) {
            Button("关闭并删除 iCloud 副本", role: .destructive) {
                Task {
                    await model.setICloudSyncEnabled(false)
                    await model.removeCloudSnapshot()
                }
            }
            Button("只关闭同步") {
                Task { await model.setICloudSyncEnabled(false) }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("只关闭同步会把已经上传的订阅地址和节点密码留在 iCloud 上。删除副本不影响这台设备上的配置。")
        }
    }

    private var statusText: LocalizedStringKey {
        if !model.isCloudAccountAvailable { return "此设备未登录 iCloud" }
        guard model.iCloudSyncEnabled else { return "配置只保存在这台设备上" }
        guard let at = model.lastCloudSyncAt else { return "已开启" }
        return "上次同步 \(at.formatted(date: .omitted, time: .shortened))"
    }
}

/// The first-launch promises, kept somewhere permanent.
///
/// That page is shown once and then never again, so the claims it makes about
/// where a subscription goes would otherwise be unreadable the moment someone
/// wants to check them. Settings carries one quiet row instead of a fifth
/// full-width card: this is reference material, not a setting anyone acts on
/// every visit, and the page behind it holds the same four rows.
private struct SecurityAndSourceLink: View {
    var body: some View {
        NavigationLink {
            SecurityAndSourceView()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "lock.shield.fill")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 26, height: 26)
                    .background(
                        Color.accentColor.opacity(0.12),
                        in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                    )

                VStack(alignment: .leading, spacing: 1) {
                    Text("安全与开源")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text("全部在这台设备上处理")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 8)

                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .contentShape(Rectangle())
            .towerCard()
        }
        .buttonStyle(ResponsivePressButtonStyle())
    }
}

struct SecurityAndSourceView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                ForEach(WelcomeView.promises) { promise in
                    if promise.id == WelcomeView.sourceRowID {
                        Link(destination: WelcomeView.repositoryURL) {
                            PromiseRow(
                                promise: promise,
                                trailing: WelcomeView.repositoryURL.absoluteString
                            )
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(ResponsivePressButtonStyle())
                        .accessibilityLabel(Text("在浏览器中打开源代码仓库"))
                    } else {
                        PromiseRow(promise: promise)
                    }
                }
            }
            .padding(18)
            .towerCard()
            .padding(.horizontal, TowerTheme.pagePadding)
            .padding(.top, 14)
            .padding(.bottom, 28)
        }
        .background(TowerTheme.background.ignoresSafeArea())
        .navigationTitle("安全与开源")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct NodeAndExportSettingsCard: View {
    @Binding var configurationNameDraft: ConfigurationNameDraft
    @Environment(AppModel.self) private var model

    private var appendNameBinding: Binding<Bool> {
        Binding(
            get: { model.appendSubscriptionNameToNodes },
            set: model.setAppendSubscriptionNameToNodes
        )
    }

    private var filterInfoBinding: Binding<Bool> {
        Binding(
            get: { model.filterSubscriptionInfoNodes },
            set: model.setFilterSubscriptionInfoNodes
        )
    }

    private var preferRuleSetsBinding: Binding<Bool> {
        Binding(
            get: { model.preferRuleSets },
            set: model.setPreferRuleSets
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionHeading(title: "节点与配置", detail: String(localized: "默认保持原始订阅"))

            RenewalReminderSection()

            Divider()

            AutoRefreshSection()

            Divider()

            Toggle(isOn: appendNameBinding) {
                SettingsRowLabel(
                    symbol: "tag.fill",
                    color: .blue,
                    title: "节点附加订阅名称",
                    detail: "节点名后显示来源，便于区分多个订阅服务。"
                )
            }
            .accessibilityIdentifier("append-subscription-name-toggle")

            Divider()

            Toggle(isOn: filterInfoBinding) {
                SettingsRowLabel(
                    symbol: "line.3.horizontal.decrease.circle.fill",
                    color: .orange,
                    title: "过滤订阅节点信息",
                    detail: "开启后隐藏流量、到期、官网和客服等信息节点。"
                )
            }
            .accessibilityIdentifier("filter-subscription-info-toggle")

            Divider()

            Toggle(isOn: preferRuleSetsBinding) {
                SettingsRowLabel(
                    symbol: "square.stack.3d.up.fill",
                    color: .purple,
                    title: "优先使用规则集",
                    detail: "兼容时引用远程规则集，不兼容的客户端会自动保留本地规则。"
                )
            }
            .accessibilityIdentifier("prefer-rule-sets-toggle")

            Divider()

            ConfigurationNameSettingsRow(configurationNameDraft: $configurationNameDraft)
        }
        .padding(17)
        .towerCard()
        .accessibilityIdentifier("node-export-settings-card")
    }
}

private struct ConfigurationNameSettingsRow: View {
    @Binding var configurationNameDraft: ConfigurationNameDraft
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 13) {
            SettingsIconTile(symbol: "doc.badge.gearshape", color: .teal)
            Text("配置名称")
                .font(.headline)
                .lineLimit(1)
            Spacer(minLength: 12)
            HStack(spacing: 8) {
                TextField("配置名称", text: $configurationNameDraft.text)
                    .focused($isFocused)
                    .multilineTextAlignment(.trailing)
                    .submitLabel(.done)
                    .onSubmit { isFocused = false }
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .lineLimit(1)
                    .frame(minWidth: 96, maxWidth: 190)
                    .accessibilityIdentifier("configuration-name-field")

                // Emptying the field cannot mean "back to 塔台": a blank value
                // is deliberately ignored, because SwiftUI publishes one while
                // tearing a focused field down. So getting back to the default
                // needs a control of its own, small enough not to crowd a row
                // whose neighbours carry only a switch.
                if configurationNameDraft.committedName != TowerBrand.localizedName {
                    Button {
                        configurationNameDraft.text = TowerBrand.localizedName
                        isFocused = false
                    } label: {
                        Image(systemName: "arrow.uturn.backward")
                            .font(.footnote.weight(.semibold))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.accentColor)
                    .accessibilityLabel(Text("恢复默认配置名称"))
                    .accessibilityIdentifier("configuration-name-reset")
                }
            }
        }
        .frame(minHeight: 44)
    }
}

/// The tinted square every settings row is introduced by.
///
/// Its own view because a third row now wants one — the configuration name
/// field — and hand-copying these five modifiers is precisely how the tiles
/// drifted to three different sizes the last time.
struct SettingsIconTile: View {
    let symbol: String
    let color: Color

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 20, weight: .semibold))
            .foregroundStyle(color)
            .frame(width: 44, height: 44)
            .background(color.opacity(0.1), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
    }
}

/// One row of the settings cards: an icon tile, a title, and a line of detail.
///
/// A view rather than a helper method so the sections that live in their own
/// structs can use it too. It used to be a private method on the card, which is
/// exactly how the rows drifted apart — the renewal section hand-rolled a
/// slightly larger tile and the auto-refresh section had no icon at all.
struct SettingsRowLabel: View {
    let symbol: String
    let color: Color
    let title: LocalizedStringKey
    private let detail: Text

    init(symbol: String, color: Color, title: LocalizedStringKey, detail: LocalizedStringKey) {
        self.symbol = symbol
        self.color = color
        self.title = title
        self.detail = Text(detail)
    }

    /// For a detail chosen at runtime. Such a string has already been through
    /// `String(localized:)`, and handing it back as a key would look it up a
    /// second time — against itself.
    init(symbol: String, color: Color, title: LocalizedStringKey, resolvedDetail: String) {
        self.symbol = symbol
        self.color = color
        self.title = title
        self.detail = Text(verbatim: resolvedDetail)
    }

    var body: some View {
        HStack(spacing: 13) {
            SettingsIconTile(symbol: symbol, color: color)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.headline)
                detail
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// A section of the node-and-export card rather than a card of its own.
///
/// Renewal reminders and automatic refresh both answer "what should Tower do
/// with my subscriptions", which is the question that card is already about.
/// As separate cards they read as three unrelated topics stacked up.
private struct RenewalReminderSection: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isExpanded = false

    private var reminderBinding: Binding<Bool> {
        Binding(
            get: { model.renewalRemindersEnabled },
            set: { enabled in
                Task { await model.setRenewalRemindersEnabled(enabled) }
            }
        )
    }

    var body: some View {
        let reminders = model.renewalReminderEntries

        VStack(alignment: .leading, spacing: 14) {
            Toggle(isOn: reminderBinding) {
                SettingsRowLabel(
                    symbol: "bell.badge.fill",
                    color: .orange,
                    title: "到期前一天通知",
                    detail: "按机场返回的到期时间自动更新"
                )
            }
            .tint(.orange)
            .disabled(model.isUpdatingRenewalReminders)
            .accessibilityIdentifier("renewal-reminder-toggle")

            if model.renewalRemindersEnabled && reminders.isEmpty {
                Label("当前机场没有提供可提前一天安排的到期时间；下次更新订阅后会自动检测。", systemImage: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if model.renewalRemindersEnabled && !reminders.isEmpty {
                Divider()

                Button {
                    withAnimation(TowerMotion.disclosure(reduceMotion: reduceMotion)) {
                        isExpanded.toggle()
                    }
                } label: {
                    HStack(spacing: 10) {
                        Label(
                            isExpanded ? String(localized: "收起具体提醒") : String(localized: "查看具体提醒"),
                            systemImage: "calendar.badge.clock"
                        )
                        .font(.subheadline.weight(.semibold))
                        Spacer()
                        Text("\(reminders.count) 个")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Image(systemName: "chevron.down")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.tertiary)
                            .rotationEffect(.degrees(isExpanded ? 180 : 0))
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("renewal-reminder-disclosure")

                if isExpanded {
                    VStack(spacing: 0) {
                        ForEach(Array(reminders.enumerated()), id: \.element.identifier) { index, reminder in
                            if index > 0 { Divider() }
                            RenewalReminderDetailRow(reminder: reminder)
                        }
                    }
                    .transition(.opacity)
                    .accessibilityIdentifier("renewal-reminder-list")
                }
            }
        }
        .accessibilityIdentifier("renewal-reminder-card")
        .sensoryFeedback(.selection, trigger: isExpanded)
        .onChange(of: model.renewalRemindersEnabled) { _, isEnabled in
            if !isEnabled { isExpanded = false }
        }
    }

}

private struct RenewalReminderDetailRow: View {
    let reminder: SubscriptionExpiryEntry

    private var status: SubscriptionExpiryStatus {
        reminder.status()
    }

    private var isExpired: Bool {
        if case .expired = status { return true }
        return false
    }

    private var color: Color { isExpired ? .red : .orange }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: isExpired ? "exclamationmark.circle.fill" : "bell.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(color)
                .frame(width: 30, height: 30)
                .background(color.opacity(0.1), in: Circle())

            VStack(alignment: .leading, spacing: 4) {
                Text(statusTitle)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(isExpired ? .red : .primary)
                Text("到期日期：\(reminder.expiryDate.formatted(date: .abbreviated, time: .omitted))")
                    .font(.caption)
                    .foregroundStyle(isExpired ? .red : .secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 11)
        .accessibilityElement(children: .combine)
    }

    private var statusTitle: String {
        switch status {
        case .upcoming(let days):
            String(localized: "\(reminder.sourceName) 到期还剩 \(days) 天")
        case .expired(let days):
            String(localized: "\(reminder.sourceName) 已过期 \(days) 天")
        }
    }
}

private struct LANSharingSettingsRow: View {
    @Environment(AppModel.self) private var model
    let open: () -> Void

    var body: some View {
        Button(action: open) {
            HStack(spacing: 13) {
                Image(systemName: model.isLANSharingActive ? "wifi.circle.fill" : "wifi.slash")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(model.isLANSharingActive ? .green : Color.accentColor)
                    .frame(width: 48, height: 48)
                    .background(
                        (model.isLANSharingActive ? Color.green : Color.accentColor).opacity(0.11),
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text("局域网共享")
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text(model.isLANSharingActive
                        ? String(localized: "支持安卓、Windows、Mac、路由器等。")
                        : String(localized: "没有对外提供服务"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 8)

                HStack(spacing: 6) {
                    Text(model.isLANSharingActive
                        ? String(localized: "正在共享")
                        : String(localized: "默认关闭"))
                        .font(.caption.weight(.medium))
                        .foregroundStyle(model.isLANSharingActive ? .green : .secondary)
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(16)
            .contentShape(Rectangle())
            .towerCard()
        }
        .buttonStyle(ResponsivePressButtonStyle())
        .accessibilityIdentifier("open-lan-export-destination")
    }
}

struct LANSharingDestinationCard: View {
    @Environment(AppModel.self) private var model
    @State private var selectedClient: LANSubscriptionFormat?
    @State private var isConfirmingTokenRotation = false

    private var selectedURL: URL? {
        model.lanSubscriptionURL(format: selectedClient)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeading(
                title: "局域网共享",
                detail: model.isLANSharingActive
                    ? String(localized: "正在共享")
                    : String(localized: "默认关闭")
            )

            HStack(spacing: 13) {
                Image(systemName: model.isLANSharingActive ? "wifi.circle.fill" : "wifi.slash")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(model.isLANSharingActive ? .green : .secondary)
                    .frame(width: 52, height: 52)
                    .background(
                        (model.isLANSharingActive ? Color.green : Color.secondary).opacity(0.11),
                        in: RoundedRectangle(cornerRadius: 15, style: .continuous)
                    )

                VStack(alignment: .leading, spacing: 3) {
                    Text(model.isLANSharingActive
                        ? String(localized: "支持安卓、Windows、Mac、路由器等。")
                        : String(localized: "没有对外提供服务"))
                        .font(.headline)
                    Text(model.isLANSharingActive
                        ? String(localized: "自动识别客户端")
                        : String(localized: "只有您主动开启后才会监听局域网"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if model.isLANSharingActive {
                Divider()
                clientPicker
                if let selectedURL {
                    URLPanel(url: selectedURL)
                }
            }

            Button {
                if model.isLANSharingActive {
                    model.stopLANSharing()
                } else {
                    Task { await model.startLANSharing() }
                }
            } label: {
                HStack(spacing: 9) {
                    if model.isLANSharingStarting {
                        ProgressView().tint(.white)
                    } else {
                        Image(systemName: model.isLANSharingActive ? "stop.fill" : "play.fill")
                    }
                    Text(model.isLANSharingActive
                        ? String(localized: "停止共享")
                        : String(localized: "开启局域网订阅"))
                        .font(.headline)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .foregroundStyle(.white)
                .background(
                    model.isLANSharingActive ? Color.red : Color.accentColor,
                    in: RoundedRectangle(cornerRadius: 15, style: .continuous)
                )
            }
            .buttonStyle(ResponsivePressButtonStyle())
            .disabled(model.isLANSharingStarting)
            .accessibilityIdentifier("lan-sharing-toggle")

            Button {
                isConfirmingTokenRotation = true
            } label: {
                Label("更换访问密钥", systemImage: "key.horizontal")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
            }
            .buttonStyle(ResponsivePressButtonStyle())
        }
        .padding(17)
        .towerCard()
        .accessibilityIdentifier("lan-subscription-card")
        .confirmationDialog(
            "更换访问密钥？",
            isPresented: $isConfirmingTokenRotation,
            titleVisibility: .visible
        ) {
            Button("更换密钥并停用旧链接", role: .destructive) {
                model.rotateLANSharingToken()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("所有已经添加到电脑或路由器的塔台订阅链接都会失效。")
        }
    }

    /// Label on the left, the current value as a button on the right.
    ///
    /// Rendered as a tinted chip rather than plain trailing text: as grey text
    /// it read as a caption and gave no sign it could be tapped at all. The
    /// menu opens in place instead of pushing a screen, because picking a
    /// format is one tap of context, not a destination.
    private var clientPicker: some View {
        HStack(spacing: 12) {
            Text("链接格式")
                .font(.subheadline.weight(.semibold))

            Spacer(minLength: 8)

            Menu {
                Picker("链接格式", selection: $selectedClient) {
                    Label("自动识别客户端", systemImage: "wand.and.stars")
                        .tag(LANSubscriptionFormat?.none)
                    ForEach(LANSubscriptionFormat.allCases) { format in
                        Label {
                            Text(format.displayName)
                        } icon: {
                            LANClientIcon(format: format, size: 20)
                        }
                            .tag(Optional(format))
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    if let selectedClient {
                        LANClientIcon(format: selectedClient, size: 20)
                    } else {
                        Image(systemName: "wand.and.stars")
                            .font(.caption.weight(.semibold))
                    }
                    Text(selectedClient?.displayName ?? String(localized: "自动识别客户端"))
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption2.weight(.bold))
                }
                .foregroundStyle(Color.accentColor)
                .padding(.horizontal, 13)
                .padding(.vertical, 8)
                .background(
                    Color.accentColor.opacity(0.12),
                    in: RoundedRectangle(cornerRadius: 11, style: .continuous)
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(ResponsivePressButtonStyle())
            .accessibilityLabel(Text("链接格式"))
            .accessibilityValue(Text(selectedClient?.displayName ?? String(localized: "自动识别客户端")))
            .accessibilityIdentifier("lan-client-picker")
        }
    }

}

private struct LANClientIcon: View {
    let format: LANSubscriptionFormat
    let size: CGFloat

    var body: some View {
        Image(format.appIconAssetName)
            .resizable()
            .renderingMode(.original)
            .scaledToFill()
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                    .strokeBorder(.primary.opacity(0.08), lineWidth: 0.5)
            }
            .accessibilityHidden(true)
    }
}

private struct URLPanel: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let url: URL

    @State private var isShowingQRCode = false
    @State private var qrImage: UIImage?
    /// Which address the image on screen encodes. Without it there is no way
    /// to tell a current code from one left over by a format change.
    @State private var qrRenderedURL: URL?
    @State private var qrFailed = false
    @State private var didCopy = false

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            Text(url.absoluteString)
                .font(.caption.monospaced())
                .foregroundStyle(.primary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("lan-subscription-url")

            // Three equal columns rather than a wide primary beside a narrow
            // secondary: none of these is the one right answer — which one you
            // want depends on whether the other machine is in front of you.
            HStack(spacing: 9) {
                action("复制", symbol: "doc.on.doc", isOn: false) {
                    UIPasteboard.general.string = url.absoluteString
                    didCopy.toggle()
                    model.showToast(String(localized: "局域网订阅链接已复制"), symbol: "doc.on.doc.fill")
                }
                action("二维码", symbol: "qrcode", isOn: isShowingQRCode) {
                    withAnimation(
                        reduceMotion
                            ? .easeOut(duration: 0.18)
                            // Nothing here was thrown by a gesture, so the
                            // panel settles without overshoot.
                            : .spring(response: 0.34, dampingFraction: 1)
                    ) {
                        isShowingQRCode.toggle()
                    }
                }
                ShareLink(item: url) {
                    actionLabel("分享", symbol: "square.and.arrow.up", isOn: false)
                }
                .buttonStyle(ResponsivePressButtonStyle())
            }
            .sensoryFeedback(.success, trigger: didCopy)

            if isShowingQRCode {
                qrCode
                    .frame(maxWidth: .infinity)
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.96)))
            }
        }
        .padding(13)
        .background(Color.accentColor.opacity(0.075), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
        // One place owns the whole lifecycle. Splitting it between this task
        // and an `onChange` that cleared the image raced: whichever ran first
        // decided the outcome, and when the task won it saw the previous
        // image, skipped rendering, and was then cleared — leaving the panel
        // permanently blank after switching client format.
        .task(id: qrTaskID) {
            guard isShowingQRCode, qrRenderedURL != url else { return }
            // A code for the previous address is worse than no code: it looks
            // right and sends the other machine somewhere else.
            qrImage = nil
            qrFailed = false
            await renderQRCode()
        }
    }

    private var qrTaskID: String { "\(url.absoluteString)-\(isShowingQRCode)" }

    @ViewBuilder
    private var qrCode: some View {
        if let qrImage {
            VStack(spacing: 8) {
                Image(uiImage: qrImage)
                    .resizable()
                    .interpolation(.none)
                    .scaledToFit()
                    .frame(width: 190, height: 190)
                    .padding(13)
                    .background(.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .shadow(color: .black.opacity(0.08), radius: 12, y: 5)
                Text("用客户端扫这个码")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("局域网订阅地址的二维码")
        } else if qrFailed {
            Label("无法生成二维码", systemImage: "exclamationmark.triangle")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: 120)
        } else {
            ProgressView()
                .frame(maxWidth: .infinity, minHeight: 120)
        }
    }

    private func action(
        _ title: LocalizedStringKey,
        symbol: String,
        isOn: Bool,
        perform: @escaping () -> Void
    ) -> some View {
        Button(action: perform) { actionLabel(title, symbol: symbol, isOn: isOn) }
            .buttonStyle(ResponsivePressButtonStyle())
    }

    private func actionLabel(
        _ title: LocalizedStringKey,
        symbol: String,
        isOn: Bool
    ) -> some View {
        VStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.subheadline.weight(.semibold))
            Text(title)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 11)
        .foregroundStyle(isOn ? Color.white : Color.accentColor)
        .background(
            isOn ? Color.accentColor : Color.accentColor.opacity(0.12),
            in: RoundedRectangle(cornerRadius: 13, style: .continuous)
        )
        .contentShape(Rectangle())
    }

    @MainActor
    private func renderQRCode() async {
        qrFailed = false
        // The address carries the access key, so the PNG is as sensitive as the
        // link. The shared builder writes it with complete protection into a
        // folder it purges before each render.
        guard let artifact = await QRCodeShareArtifactBuilder.make(value: url.absoluteString, id: UUID()) else {
            guard !Task.isCancelled else { return }
            qrFailed = true
            return
        }
        guard !Task.isCancelled else { return }
        qrRenderedURL = url
        if reduceMotion {
            qrImage = artifact.image
        } else {
            withAnimation(.easeOut(duration: 0.16)) { qrImage = artifact.image }
        }
    }
}

struct LANSharingGuide: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeading(title: "怎么使用", detail: "OpenClash · Windows · Mac")
            VStack(alignment: .leading, spacing: 13) {
                GuideRow(number: "1", text: "让手机和电脑或路由器连接同一个 Wi-Fi。")
                GuideRow(number: "2", text: "开启服务，优先复制“自动识别客户端”链接。")
                GuideRow(number: "3", text: "把链接作为订阅地址添加到客户端，刷新时保持塔台在前台打开。")
                Divider()
                Label("高级机场仍由塔台使用您设置的 UA 和 DNS 获取；桌面端只读取塔台生成的结果，不会拿到机场订阅密钥。", systemImage: "lock.shield.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(17)
            .towerCard()
        }
    }
}

private struct GuideRow: View {
    let number: String
    let text: LocalizedStringKey

    var body: some View {
        HStack(alignment: .top, spacing: 11) {
            Text(number)
                .font(.caption.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 24, height: 24)
                .background(Color.accentColor, in: Circle())
            Text(text)
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
