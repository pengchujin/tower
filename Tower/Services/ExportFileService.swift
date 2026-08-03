import Foundation

struct ExportFileService {
    func write(_ configuration: GeneratedConfiguration) throws -> URL {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("TowerExports", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent(configuration.fileName, isDirectory: false)
        try configuration.content.write(to: url, atomically: true, encoding: .utf8)
        return url
    }
}
