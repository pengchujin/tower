import SwiftUI

/// Read-only feedback for authored text; remote resources are never expanded here.
struct LocalRuleCompatibilityView: View {
    let text: String
    @State private var checkedText: String?
    @State private var summary: LocalRuleCompatibilitySummary?

    var body: some View {
        Section {
            if checkedText == text, let summary {
                if summary.isRemote {
                    Text("远程规则集的兼容性以导出页提示为准。")
                } else if let error = summary.error {
                    Text(error).foregroundStyle(.red)
                } else if summary.isEmpty {
                    Text("输入规则后显示客户端兼容性。")
                } else {
                    if !summary.supported.isEmpty {
                        Text("可完整转换：\(summary.supported.map(Self.name).joined(separator: "、"))")
                    }
                    if !summary.unsupported.isEmpty {
                        Text("部分规则无法完整转换：\(summary.unsupported.map(Self.name).joined(separator: "、"))")
                            .foregroundStyle(.orange)
                    }
                    Text("按当前转换能力检查。无法完整保留的拒绝条件会阻止对应客户端导出；其他客户端以导出页提示为准。")
                }
            } else {
                Text("正在检查兼容性…")
            }
        } header: {
            Text("客户端兼容性")
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
        .accessibilityIdentifier("local-rule-compatibility")
        .task(id: text) {
            let input = text
            do { try await Task.sleep(for: .milliseconds(250)) } catch { return }
            let result = await Task.detached(priority: .userInitiated) {
                LocalRuleCompatibilitySummary(text: input)
            }.value
            guard !Task.isCancelled, input == text else { return }
            summary = result
            checkedText = input
        }
    }

    private static func name(_ target: ClientTarget) -> String {
        target == .clashMi ? "Clash / Mihomo" : target.name
    }
}
