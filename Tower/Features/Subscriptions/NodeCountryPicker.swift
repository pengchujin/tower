import SwiftUI

struct NodeCountryPicker: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let node: ProxyNode
    @State private var search = ""

    private var regions: [NodeRegion] {
        NodeRegionResolver.countryTable.keys.compactMap(NodeRegionResolver.region(countryCode:))
            .filter { search.isEmpty || $0.localizedName.localizedCaseInsensitiveContains(search)
                || $0.name.localizedCaseInsensitiveContains(search) || $0.code.localizedCaseInsensitiveContains(search) }
            .sorted { $0.localizedName.localizedStandardCompare($1.localizedName) == .orderedAscending }
    }

    var body: some View {
        NavigationStack {
            List {
                Button("自动识别") {
                    model.setCountryOverride(nil, for: node)
                    dismiss()
                }
                ForEach(regions) { region in
                    Button {
                        model.setCountryOverride(region.code, for: node)
                        dismiss()
                    } label: {
                        HStack {
                            Text(verbatim: "\(region.flag) \(region.localizedName)")
                            Spacer()
                            if node.countryOverride == region.code { Image(systemName: "checkmark") }
                        }
                    }
                }
            }
            .searchable(text: $search)
            .navigationTitle("设置地区")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } } }
        }
    }
}
