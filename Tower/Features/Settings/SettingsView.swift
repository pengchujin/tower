import SwiftUI
import UIKit

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var selectedClient: ClientTarget?
    @State private var isConfirmingTokenRotation = false

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 22) {
                NodeAndExportSettingsCard()
                RenewalReminderCard()
                LANSharingCard(
                    selectedClient: $selectedClient,
                    isConfirmingTokenRotation: $isConfirmingTokenRotation
                )
                LANSharingGuide()
            }
            .padding(.horizontal, TowerTheme.pagePadding)
            .padding(.top, 12)
            .padding(.bottom, 28)
        }
        .background(TowerTheme.background.ignoresSafeArea())
        .navigationTitle("设置")
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
}

private struct NodeAndExportSettingsCard: View {
    @Environment(AppModel.self) private var model
    @State private var configurationNameDraft = ConfigurationNameDraft()
    @FocusState private var isConfigurationNameFocused: Bool

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
            SectionHeading(title: "节点与配置", detail: "默认保持原始订阅")

            Toggle(isOn: appendNameBinding) {
                settingsLabel(
                    symbol: "tag.fill",
                    color: .blue,
                    title: "节点附加订阅名称",
                    detail: "节点名后显示来源，便于区分多个订阅服务。"
                )
            }
            .accessibilityIdentifier("append-subscription-name-toggle")

            Divider()

            Toggle(isOn: filterInfoBinding) {
                settingsLabel(
                    symbol: "line.3.horizontal.decrease.circle.fill",
                    color: .orange,
                    title: "过滤订阅节点信息",
                    detail: "开启后隐藏流量、到期、官网和客服等信息节点。"
                )
            }
            .accessibilityIdentifier("filter-subscription-info-toggle")

            Divider()

            Toggle(isOn: preferRuleSetsBinding) {
                settingsLabel(
                    symbol: "square.stack.3d.up.fill",
                    color: .purple,
                    title: "优先使用规则集",
                    detail: "兼容时引用远程规则集，不兼容的客户端会自动保留本地规则。"
                )
            }
            .accessibilityIdentifier("prefer-rule-sets-toggle")

            Divider()

            VStack(alignment: .leading, spacing: 9) {
                HStack {
                    Label("配置名称", systemImage: "doc.badge.gearshape")
                        .font(.headline)
                    Spacer()
                    if model.configurationName != TowerBrand.localizedName {
                        Button("恢复默认") {
                            configurationNameDraft.text = TowerBrand.localizedName
                            model.setConfigurationName(TowerBrand.localizedName)
                        }
                        .font(.caption.weight(.semibold))
                    }
                }
                TextField("配置名称", text: $configurationNameDraft.text)
                    .focused($isConfigurationNameFocused)
                    .submitLabel(.done)
                    .onSubmit(commitConfigurationName)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .padding(.horizontal, 13)
                    .frame(height: 46)
                    .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                    .accessibilityIdentifier("configuration-name-field")
                Text("导出的文件、本机导入和客户端订阅会使用同一个名称。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(17)
        .towerCard()
        .accessibilityIdentifier("node-export-settings-card")
        .onAppear {
            configurationNameDraft.text = model.configurationName
        }
        .onChange(of: isConfigurationNameFocused) { _, isFocused in
            if !isFocused { commitConfigurationName() }
        }
        .onChange(of: model.configurationName) { _, name in
            if !isConfigurationNameFocused { configurationNameDraft.text = name }
        }
        .onDisappear(perform: commitConfigurationName)
    }

    private func commitConfigurationName() {
        model.setConfigurationName(configurationNameDraft.committedName)
        configurationNameDraft.text = model.configurationName
    }

    private func settingsLabel(
        symbol: String,
        color: Color,
        title: LocalizedStringKey,
        detail: LocalizedStringKey
    ) -> some View {
        HStack(spacing: 13) {
            Image(systemName: symbol)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 44, height: 44)
                .background(color.opacity(0.1), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.headline)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct RenewalReminderCard: View {
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
            SectionHeading(
                title: "续费提醒",
                detail: model.renewalRemindersEnabled
                    ? String(localized: "\(model.scheduledRenewalReminderCount) 个已安排")
                    : String(localized: "默认关闭")
            )

            Toggle(isOn: reminderBinding) {
                HStack(spacing: 13) {
                    Image(systemName: "bell.badge.fill")
                        .font(.system(size: 23, weight: .semibold))
                        .foregroundStyle(.orange)
                        .frame(width: 48, height: 48)
                        .background(.orange.opacity(0.11), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    VStack(alignment: .leading, spacing: 3) {
                        Text("到期前一天通知")
                            .font(.headline)
                        Text("按机场返回的到期时间自动更新")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
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
                    withAnimation(expansionAnimation) {
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
                .buttonStyle(ResponsivePressButtonStyle())
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
        .padding(17)
        .towerCard()
        .accessibilityIdentifier("renewal-reminder-card")
        .sensoryFeedback(.selection, trigger: isExpanded)
        .onChange(of: model.renewalRemindersEnabled) { _, isEnabled in
            if !isEnabled { isExpanded = false }
        }
    }

    private var expansionAnimation: Animation {
        reduceMotion ? .easeOut(duration: 0.14) : .interactiveSpring(response: 0.34, dampingFraction: 1)
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
                if !isExpired {
                    Label("将在到期前一天通知", systemImage: "clock")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.orange)
                } else {
                    Label("需要续费或删除该订阅", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.red)
                }
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

private struct LANSharingCard: View {
    @Environment(AppModel.self) private var model
    @Binding var selectedClient: ClientTarget?
    @Binding var isConfirmingTokenRotation: Bool

    private var selectedURL: URL? {
        model.lanSubscriptionURL(target: selectedClient)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeading(
                title: "局域网订阅",
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
                        ? String(localized: "同一 Wi-Fi 可访问")
                        : String(localized: "没有对外提供服务"))
                        .font(.headline)
                    Text(model.isLANSharingActive
                        ? String(localized: "共享的是转换结果，不含机场原始链接")
                        : String(localized: "只有你主动开启后才会监听局域网"))
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
    }

    private var clientPicker: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("链接格式")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Picker("链接格式", selection: $selectedClient) {
                Text("自动识别客户端").tag(ClientTarget?.none)
                ForEach(ClientTarget.allCases) { target in
                    Text(lanDisplayName(target)).tag(Optional(target))
                }
            }
            .pickerStyle(.menu)
            .tint(.primary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
            .accessibilityIdentifier("lan-client-picker")
        }
    }

    private func lanDisplayName(_ target: ClientTarget) -> String {
        switch target {
        case .clash: "OpenClash / Clash / Stash"
        case .quanx: "Quantumult X"
        default: target.name
        }
    }
}

private struct URLPanel: View {
    @Environment(AppModel.self) private var model
    let url: URL

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(url.absoluteString)
                .font(.caption.monospaced())
                .foregroundStyle(.primary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("lan-subscription-url")

            HStack(spacing: 10) {
                Button {
                    UIPasteboard.general.string = url.absoluteString
                    model.showToast(String(localized: "局域网订阅链接已复制"), symbol: "doc.on.doc.fill")
                } label: {
                    Label("复制", systemImage: "doc.on.doc")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                ShareLink(item: url) {
                    Label("分享", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }
            .font(.subheadline.weight(.semibold))
        }
        .padding(13)
        .background(Color.accentColor.opacity(0.075), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
    }
}

private struct LANSharingGuide: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeading(title: "怎么使用", detail: "OpenClash · Windows · Mac")
            VStack(alignment: .leading, spacing: 13) {
                GuideRow(number: "1", text: "让手机和电脑或路由器连接同一个 Wi-Fi。")
                GuideRow(number: "2", text: "开启服务，优先复制“自动识别客户端”链接。")
                GuideRow(number: "3", text: "把链接作为订阅地址添加到客户端，刷新时保持塔台在前台打开。")
                Divider()
                Label("高级机场仍由塔台使用你设置的 UA 和 DNS 获取；桌面端只读取塔台生成的结果，不会拿到机场订阅密钥。", systemImage: "lock.shield.fill")
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
