import Foundation

struct RuleRepository {
    static let sourceRevision = "fb658cc85802"
    static let sourceURL = URL(string: "https://github.com/ClashConnectRules/Self-Configuration")!
    static let sourceName = "Self-Configuration"

    private let linesByPath: [String: [String]]

    init(bundle: Bundle = .main) {
        var result: [String: [String]] = [:]
        if let root = bundle.resourceURL,
           let enumerator = FileManager.default.enumerator(
               at: root,
               includingPropertiesForKeys: [.isRegularFileKey],
               options: [.skipsHiddenFiles]
           ) {
            for case let url as URL in enumerator where url.pathExtension == "list" {
                let path = url.path
                let key: String
                if let marker = path.range(of: "SelfConfiguration/") {
                    key = String(path[marker.upperBound...].dropLast(".list".count))
                } else {
                    key = url.deletingPathExtension().lastPathComponent
                }
                guard let content = try? String(contentsOf: url, encoding: .utf8) else { continue }
                let lines = content
                    .components(separatedBy: .newlines)
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty && !$0.hasPrefix("#") && !$0.hasPrefix(";") }
                result[key] = lines
                result[url.deletingPathExtension().lastPathComponent] = lines
            }
        }
        linesByPath = result
    }

    func lines(for assignment: RuleAssignment) -> [String] {
        linesByPath[assignment.resourcePath]
            ?? linesByPath[assignment.resourcePath.components(separatedBy: "/").last ?? assignment.resourcePath]
            ?? []
    }

    func count(for preset: RulePreset) -> Int {
        let localCount = preset.assignments.reduce(0) { $0 + lines(for: $1).count }
        return localCount + (preset.includeGeoIPCN ? 1 : 0) + 1
    }

    func count(for assignment: RuleAssignment) -> Int {
        lines(for: assignment).count
    }
}
