import Foundation
import CryptoKit
import Darwin

enum ArchiveStorage {
    static func key(_ root: URL) -> String { SHA256.hash(data: Data((root.isFileURL ? root.standardizedFileURL.path : root.absoluteString).utf8)).map { String(format: "%02x", $0) }.joined() }
    static func isNetwork(_ root: URL) -> Bool { (try? root.resourceValues(forKeys: [.volumeIsLocalKey]).volumeIsLocal) == false }
    static func destination(_ relative: String, root: URL) throws -> URL {
        let components = relative.components(separatedBy: "/")
        guard !relative.hasPrefix("/"), !components.contains(".."), !components.contains("."), !components.contains("") else { throw ShelfError.message("Недопустимый путь в библиотеке") }
        let canonical = root.resolvingSymlinksInPath().standardizedFileURL
        let candidate = canonical.appendingPathComponent(relative).standardizedFileURL
        var ancestor = candidate
        while !FileManager.default.fileExists(atPath: ancestor.path) && ancestor.path != "/" { ancestor.deleteLastPathComponent() }
        let resolved = ancestor.resolvingSymlinksInPath().standardizedFileURL.path
        guard resolved == canonical.path || resolved.hasPrefix(canonical.path + "/") else { throw ShelfError.message("Символическая ссылка выводит путь за пределы библиотеки") }
        return candidate
    }
    static func createLibrary(_ root: URL) throws {
        guard FileManager.default.fileExists(atPath: root.path) else { throw ShelfError.message("Папка библиотеки недоступна. Подключите NAS через Finder.") }
        let docs = try destination("Документы", root: root)
        try FileManager.default.createDirectory(at: docs, withIntermediateDirectories: true)
        let manifest = try destination("Документы/Манифест.json", root: root)
        if !FileManager.default.fileExists(atPath: manifest.path) { try Data("[]".utf8).write(to: manifest, options: .withoutOverwriting) }
    }
    static func withLock<T>(_ root: URL, _ operation: () throws -> T) throws -> T {
        let manifest = try destination("Документы/Манифест.json", root: root)
        guard FileManager.default.fileExists(atPath: manifest.path) else { throw ShelfError.message("Библиотека недоступна. Подключите NAS и повторите операцию.") }
        let lock = try destination("Документы/.appdock-write-lock", root: root)
        guard mkdir(lock.path, 0o700) == 0 else {
            throw ShelfError.message(errno == EEXIST ? "Библиотеку уже изменяет другой экземпляр AppDock. Повторите позже. Если приложение аварийно завершилось, проверьте отсутствие других записей перед удалением .appdock-write-lock." : "Не удалось заблокировать библиотеку для записи: \(String(cString: strerror(errno)))")
        }
        defer { try? FileManager.default.removeItem(at: lock) }
        return try operation()
    }
    static func snapshotURL(_ root: URL, support: URL) -> URL { support.appendingPathComponent("LibrarySnapshots/" + key(root) + ".json") }
    static func saveSnapshot(_ items: [IPAItem], root: URL, support: URL) throws {
        let file = snapshotURL(root, support: support)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(items).write(to: file, options: .atomic)
    }
    static func snapshot(_ root: URL, support: URL) throws -> [IPAItem] { try JSONDecoder().decode([IPAItem].self, from: Data(contentsOf: snapshotURL(root, support: support))) }
    static func cacheFile(_ item: IPAItem, support: URL) -> URL? {
        guard let hash = item.sha256, hash.count == 64, hash.allSatisfy({ $0.isHexDigit }) else { return nil }
        return support.appendingPathComponent("LocalIPA/" + hash.lowercased() + ".ipa")
    }
    static func isCached(_ item: IPAItem, support: URL) -> Bool {
        guard let file = cacheFile(item, support: support), let attributes = try? file.resourceValues(forKeys: [.fileSizeKey]), let size = attributes.fileSize else { return false }
        return item.bytes == nil || Int64(size) == item.bytes
    }
    static func verify(_ file: URL, item: IPAItem) throws {
        guard let expected = item.sha256 else { throw ShelfError.message("Нет SHA-256 в каталоге. Импортируйте IPA заново для проверки.") }
        let hash = try DeviceTools.run(URL(fileURLWithPath: "/usr/bin/shasum"), ["-a", "256", file.path])
        guard hash.status == 0, hash.output.split(separator: " ").first.map(String.init) == expected else { throw ShelfError.message("SHA-256 IPA не совпадает с каталогом. Файл не будет установлен.") }
    }
    static func prepare(_ item: IPAItem, root: URL, support: URL) throws -> URL {
        guard let destination = cacheFile(item, support: support) else { throw ShelfError.message("Некорректный SHA-256 в каталоге") }
        if isCached(item, support: support) { try verify(destination, item: item); return destination }
        let source = try item.file(in: root)
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        let stage = destination.deletingLastPathComponent().appendingPathComponent(UUID().uuidString + ".incoming")
        defer { try? FileManager.default.removeItem(at: stage) }
        try FileManager.default.copyItem(at: source, to: stage)
        try verify(stage, item: item)
        // Cache is private to this Mac; serialized operations avoid concurrent replacement.
        if FileManager.default.fileExists(atPath: destination.path) { try FileManager.default.removeItem(at: destination) }
        try FileManager.default.moveItem(at: stage, to: destination)
        return destination
    }
    static func export(_ item: IPAItem, root: URL, support: URL, directory: URL) throws {
        let source = try prepare(item, root: root, support: support)
        let filename = URL(fileURLWithPath: item.path).lastPathComponent
        let destination = directory.appendingPathComponent(filename)
        guard !FileManager.default.fileExists(atPath: destination.path) else { throw ShelfError.message("Файл уже есть: \(filename)") }
        let stage = directory.appendingPathComponent("." + UUID().uuidString + ".incoming")
        defer { try? FileManager.default.removeItem(at: stage) }
        try FileManager.default.copyItem(at: source, to: stage)
        try verify(stage, item: item)
        try FileManager.default.moveItem(at: stage, to: destination)
    }
}
