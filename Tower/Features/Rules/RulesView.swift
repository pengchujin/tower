import SwiftUI

struct RulesView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 22) {
                RulesOverviewCard()

                VStack(spacing: 12) {
                    SectionHeading(title: "默认规则", detail: "本地快照")
                    ForEach(RulePreset.builtIns) { preset in
                        RulePresetCard(
                            preset: preset,
                            isSelected: model.selectedPresetID == preset.id,
                            ruleCount: model.ruleCount(for: preset)
                        ) {
                            model.selectPreset(preset)
                        }
                    }
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
        .sensoryFeedback(.selection, trigger: model.selectedPresetID)
    }
}

private struct RulesOverviewCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(model.selectedPreset.name)
                        .font(.title2.weight(.bold))
                    Text(model.selectedPreset.summary)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 14)
                Image(systemName: model.selectedPreset.symbol)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 48, height: 48)
                    .background(
                        TowerTheme.color(named: model.selectedPreset.tintName).gradient,
                        in: RoundedRectangle(cornerRadius: 15, style: .continuous)
                    )
            }
            HStack {
                Label("\(model.currentRuleCount.formatted()) 条规则", systemImage: "list.bullet.rectangle.portrait.fill")
                Spacer()
                Label(RuleRepository.sourceName, systemImage: "shippingbox.fill")
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
        }
        .padding(20)
        .towerCard()
    }
}

private struct RulePresetCard: View {
    let preset: RulePreset
    let isSelected: Bool
    let ruleCount: Int
    let onSelect: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Button(action: onSelect) {
                HStack(alignment: .top, spacing: 14) {
                    Image(systemName: preset.symbol)
                        .font(.headline)
                        .foregroundStyle(TowerTheme.color(named: preset.tintName))
                        .frame(width: 42, height: 42)
                        .background(
                            TowerTheme.color(named: preset.tintName).opacity(0.1),
                            in: RoundedRectangle(cornerRadius: 13, style: .continuous)
                        )
                    VStack(alignment: .leading, spacing: 5) {
                        HStack(spacing: 7) {
                            Text(preset.name)
                                .font(.headline)
                            if preset.isRecommended {
                                Text("推荐")
                                    .font(.caption2.weight(.bold))
                                    .foregroundStyle(Color.accentColor)
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 3)
                                    .background(Color.accentColor.opacity(0.1), in: Capsule())
                            }
                        }
                        Text(preset.summary)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("\(ruleCount.formatted()) 条 · \(preset.assignments.count) 个规则组")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    Spacer(minLength: 6)
                    ZStack {
                        Circle()
                            .stroke(isSelected ? Color.accentColor : Color.secondary.opacity(0.3), lineWidth: 1.5)
                            .frame(width: 25, height: 25)
                        if isSelected {
                            Circle()
                                .fill(Color.accentColor)
                                .frame(width: 25, height: 25)
                            Image(systemName: "checkmark")
                                .font(.caption2.weight(.black))
                                .foregroundStyle(.white)
                        }
                    }
                    .padding(.top, 2)
                }
                .contentShape(Rectangle())
                .padding(16)
            }
            .buttonStyle(ResponsivePressButtonStyle())
            .accessibilityIdentifier("rule-\(preset.id)")

            Divider().padding(.leading, 72)

            NavigationLink {
                RuleDetailView(preset: preset)
            } label: {
                HStack {
                    Text("查看包含的规则")
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.bold))
                }
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .towerCard()
        .overlay {
            if isSelected {
                RoundedRectangle(cornerRadius: TowerTheme.cornerRadius, style: .continuous)
                    .stroke(Color.accentColor.opacity(0.65), lineWidth: 1.5)
            }
        }
    }
}

struct RuleDetailView: View {
    @Environment(AppModel.self) private var model
    let preset: RulePreset

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Label(preset.name, systemImage: preset.symbol)
                        .font(.title3.weight(.semibold))
                    Text(preset.summary)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 6)
            }

            Section("本地规则组") {
                ForEach(preset.assignments) { assignment in
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(assignment.title)
                            Text(assignment.policy.displayName)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(model.ruleCount(for: assignment).formatted())
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
                if preset.includeGeoIPCN {
                    LabeledContent("中国大陆 IP", value: "GeoIP CN")
                }
                LabeledContent("未匹配流量", value: preset.finalPolicy.displayName)
            }

            Section {
                Link(destination: RuleRepository.sourceURL) {
                    Label("打开 Self-Configuration 项目", systemImage: "arrow.up.right.square")
                }
                LabeledContent("本地快照", value: RuleRepository.sourceRevision)
            } header: {
                Text("来源与许可")
            } footer: {
                Text("规则结构来自 Self-Configuration；它引用的规则提供者已固定版本并随 App 打包，运行时读取本地快照。")
            }
        }
        .navigationTitle("规则详情")
        .navigationBarTitleDisplayMode(.inline)
    }
}
