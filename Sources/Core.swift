import Foundation

struct IPAItem: Codable, Identifiable, Hashable {
    let path: String
    let idNumber: Int?
    let name: String?
    let publisher: String?
    let bundle: String?
    let version: String?
    let minIOS: String?
    let bytes: Int64?
    let sha256: String?
    var familyName: String? = nil
    var licenseAccount: String? = nil
    var localOnly: Bool? = nil
    var firstRelease: String? = nil
    var versionReleaseDate: String? = nil
    var build: String? = nil
    enum CodingKeys: String, CodingKey {
        case path, name, publisher, bundle, version, minIOS, bytes, sha256, firstRelease, versionReleaseDate, build, localOnly, familyName, licenseAccount
        case idNumber = "id"
    }
    var id: String { path }
    var title: String { name ?? URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent }
    var category: String { path.components(separatedBy: "/").first ?? "Другие" }
    var needsReview: Bool {
        (publisher == "Источник не подтверждён") || path.contains("Требует-проверки") || [6448470109, 6749261529, 6744680809].contains(idNumber ?? 0)
    }
    var family: String {
        if let familyName, !familyName.isEmpty { return familyName }
        let banks: [Int: String] = [1629869891: "Ozon Банк", 6739035108: "Альфа-Банк", 1633409806: "Альфа-Банк", 6444695749: "Альфа-Банк", 353127685: "Альфа-Банк", 6772217339: "Альфа-Банк · Беларусь", 472951966: "ВТБ", 6803519628: "ВТБ", 6450266264: "МТС-Банк", 6745097862: "МТС-Банк", 557857165: "Райффайзен", 6749261529: "Сбер", 6451046063: "Т-Банк", 455652438: "Т-Банк", 6748913132: "Т-Банк", 6774629936: "Т-Банк"]
        if let idNumber, let bank = banks[idNumber] { return bank }
        let parts = path.components(separatedBy: "/")
        if category == "Банки", parts.count > 2 {
            if parts[1] == "Беларусь" { return "Альфа-Банк · Беларусь" }
            if parts[1] != "Платежи" { return parts[1] }
        }
        if [6736902949, 1348775741, 1171013996].contains(idNumber ?? 0) { return "МЕДСИ · SmartMed" }
        return title
    }
    var foreignBank: Bool { path.contains("Беларусь") }
    func file(in root: URL) throws -> URL {
        let file = root.appendingPathComponent(path).resolvingSymlinksInPath().standardizedFileURL
        let prefix = root.resolvingSymlinksInPath().standardizedFileURL.path + "/"
        guard file.path.hasPrefix(prefix), file.pathExtension.lowercased() == "ipa",
              FileManager.default.fileExists(atPath: file.path) else {
            throw ShelfError.message("Файл недоступен: \(path)")
        }
        return file
    }
}

enum ShelfError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case let .message(s) = self { return s }; return nil }
}

struct Phone: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let ios: String
    var model = ""
    var serial = ""
    var battery = ""
    var storage = ""
    var modelNumber = ""
    var regulatoryModel = ""
    var marketingName = ""
    var displayModel: String { !marketingName.isEmpty ? marketingName : (DeviceModel.names[model] ?? (model.isEmpty ? "iPhone" : model)) }
}

struct CommandResult: Sendable {
    let status: Int32
    let output: String
    var data: Data = Data()
}

enum DeviceTools {
    static func executable(_ name: String) throws -> URL {
        for prefix in ["/opt/homebrew/bin", "/usr/local/bin"] {
            let url = URL(fileURLWithPath: prefix).appendingPathComponent(name)
            if FileManager.default.isExecutableFile(atPath: url.path) { return url }
        }
        throw ShelfError.message("Нет \(name). Установите инструменты: brew install ideviceinstaller libimobiledevice")
    }
    // Direct argument vectors: paths and device identifiers never enter a shell.
    static func run(_ executable: URL, _ arguments: [String], timeout: TimeInterval = 600, onOutput: ((String) -> Void)? = nil) throws -> CommandResult {
        let p = Process(), pipe = Pipe()
        p.executableURL = executable
        p.arguments = arguments
        p.standardOutput = pipe
        p.standardError = pipe
        p.standardInput = FileHandle.nullDevice
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
        p.environment = environment
        try p.run()
        let timer = DispatchSource.makeTimerSource(queue: .global())
        timer.schedule(deadline: .now() + timeout)
        timer.setEventHandler { if p.isRunning { p.terminate() } }
        timer.resume()
        defer { timer.cancel() }
        var data = Data()
        while true {
            let chunk = pipe.fileHandleForReading.availableData
            if chunk.isEmpty { break }
            data.append(chunk)
            onOutput?(String(decoding: chunk, as: UTF8.self))
        }
        p.waitUntilExit()
        return CommandResult(status: p.terminationStatus, output: String(decoding: data, as: UTF8.self), data: data)
    }
    static func command(_ name: String, _ arguments: [String], timeout: TimeInterval = 30) throws -> CommandResult {
        try run(executable(name), arguments, timeout: timeout)
    }
    static func phones() throws -> [Phone] {
        let result = try command("idevice_id", ["-l"])
        guard result.status == 0 else { throw ShelfError.message(result.output) }
        return try result.output.split(whereSeparator: \.isNewline).map { id in
            let udid = String(id).trimmingCharacters(in: .whitespaces)
            let name = try command("ideviceinfo", ["-u", udid, "-k", "DeviceName"])
            let ios = try command("ideviceinfo", ["-u", udid, "-k", "ProductVersion"])
            guard name.status == 0, ios.status == 0 else {
                throw ShelfError.message("Разблокируйте iPhone и подтвердите «Доверять этому компьютеру». \(name.output)")
            }
            func info(_ key: String, domain: String? = nil) -> String {
                let args = ["-u", udid] + (domain.map { ["-q", $0] } ?? []) + ["-k", key]
                guard let r = try? command("ideviceinfo", args), r.status == 0 else { return "" }
                return r.output.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            let available = info("TotalDataAvailable", domain: "com.apple.disk_usage")
            let capacity = info("TotalDiskCapacity", domain: "com.apple.disk_usage")
            let storage: String
            if let free = Int64(available), let total = Int64(capacity) {
                storage = "Свободно " + ByteCountFormatter.string(fromByteCount: free, countStyle: .file) + " из " + ByteCountFormatter.string(fromByteCount: total, countStyle: .file)
            } else { storage = "" }
            return Phone(id: udid, name: name.output.trimmingCharacters(in: .whitespacesAndNewlines),
                         ios: ios.output.trimmingCharacters(in: .whitespacesAndNewlines),
                         model: info("ProductType"), serial: info("SerialNumber"),
                         battery: info("BatteryCurrentCapacity", domain: "com.apple.mobile.battery"), storage: storage,
                         modelNumber: info("ModelNumber"), regulatoryModel: info("RegulatoryModelNumber"))
        }
    }
    static func installedSnapshot(on phone: Phone) throws -> InstalledSnapshot {
        let r = try command("ideviceinstaller", ["-u", phone.id, "list", "--xml"], timeout: 60)
        guard r.status == 0, let start = r.output.range(of: "<?xml") else {
            throw ShelfError.message("Не удалось прочитать приложения iPhone. \(r.output)")
        }
        let data = Data(r.output[start.lowerBound...].utf8)
        guard let array = try PropertyListSerialization.propertyList(from: data, format: nil) as? [[String: Any]] else {
            throw ShelfError.message("Неожиданный формат списка приложений iPhone")
        }
        var versions: [String: String] = [:]
        var names: [String: String] = [:]
        for app in array {
            if let bundle = app["CFBundleIdentifier"] as? String {
                versions[bundle] = app["CFBundleShortVersionString"] as? String ?? ""
                names[bundle] = app["CFBundleDisplayName"] as? String ?? app["CFBundleName"] as? String ?? bundle
            }
        }
        return InstalledSnapshot(versions: versions, names: names)
    }
    static func installed(on phone: Phone) throws -> [String: String] { try installedSnapshot(on: phone).versions }
    static func meetsMinimum(_ current: String, _ minimum: String) -> Bool {
        current.compare(minimum, options: .numeric) != .orderedAscending
    }
    static func loadManifest(root: URL) throws -> [IPAItem] {
        let url = root.appendingPathComponent("Документы/Манифест.json")
        return try JSONDecoder().decode([IPAItem].self, from: Data(contentsOf: url))
    }
}

/// Imports archive bytes without unpacking any executable or modifying Apple's signature.
enum ArchiveTools {
    static func inspect(_ source: URL) throws -> [String: Any] {
        let test = try DeviceTools.run(URL(fileURLWithPath: "/usr/bin/unzip"), ["-t", source.path])
        guard test.status == 0 else { throw ShelfError.message("Повреждённый или неподдерживаемый IPA: проверка ZIP не пройдена.") }
        let listing = try DeviceTools.run(URL(fileURLWithPath: "/usr/bin/unzip"), ["-Z", "-1", source.path])
        let candidates = listing.output.split(whereSeparator: \.isNewline).map(String.init).filter {
            $0.hasPrefix("Payload/") && $0.hasSuffix(".app/Info.plist") && $0.components(separatedBy: "/").count == 3
        }
        guard candidates.count == 1 else { throw ShelfError.message("В IPA должно быть одно основное приложение в Payload.") }
        let plist = try DeviceTools.run(URL(fileURLWithPath: "/usr/bin/unzip"), ["-p", source.path, "Payload/*.app/Info.plist", "-x", "Payload/*/*/Info.plist"])
        guard plist.status == 0, let info = try PropertyListSerialization.propertyList(from: plist.data, format: nil) as? [String: Any],
              let bundle = info["CFBundleIdentifier"] as? String, !bundle.isEmpty else { throw ShelfError.message("Не найден корректный Info.plist приложения.") }
        let metadata = try DeviceTools.run(URL(fileURLWithPath: "/usr/bin/unzip"), ["-p", source.path, "iTunesMetadata.plist"])
        let store = (try? PropertyListSerialization.propertyList(from: metadata.data, format: nil)) as? [String: Any] ?? [:]
        let hash = try DeviceTools.run(URL(fileURLWithPath: "/usr/bin/shasum"), ["-a", "256", source.path])
        guard hash.status == 0, let sha = hash.output.split(separator: " ").first else { throw ShelfError.message("Не удалось проверить SHA-256") }
        var row: [String: Any] = ["bundle": bundle, "version": info["CFBundleShortVersionString"] as? String ?? "", "minIOS": info["MinimumOSVersion"] as? String ?? "", "sha256": String(sha), "bytes": try source.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0, "crc_error": NSNull()]
        row["name"] = store["itemName"] as? String ?? info["CFBundleDisplayName"] as? String ?? info["CFBundleName"] as? String ?? bundle
        row["publisher"] = store["artistName"] as? String ?? "Источник не подтверждён"
        row["licenseAccount"] = store["appleId"] as? String ?? store["userName"] as? String
        row["firstRelease"] = store["releaseDate"] as? String
        row["build"] = info["CFBundleVersion"] as? String
        row["savedAt"] = ISO8601DateFormatter().string(from: Date())
        row["id"] = store["itemId"] as? NSNumber ?? NSNull()
        return row
    }
    static func add(_ source: URL, root: URL, category: String, replacing: IPAItem? = nil, expectedID: Int? = nil, title: String? = nil) throws {
        try ArchiveStorage.withLock(root) { try addUnlocked(source, root: root, category: category, replacing: replacing, expectedID: expectedID, title: title) }
    }
    private static func addUnlocked(_ source: URL, root: URL, category: String, replacing: IPAItem?, expectedID: Int?, title: String?) throws {
        var row = try inspect(source)
        if let expectedID, (row["id"] as? NSNumber)?.intValue != expectedID { throw ShelfError.message("App Store ID внутри IPA не совпадает с запрошенным. Файл не добавлен.") }
        if let replacing, row["bundle"] as? String != replacing.bundle { throw ShelfError.message("Bundle ID отличается: этот IPA нельзя использовать для замены выбранного приложения.") }
        let fm = FileManager.default
        let manifest = root.appendingPathComponent("Документы/Манифест.json")
        guard var rows = try JSONSerialization.jsonObject(with: Data(contentsOf: manifest)) as? [[String: Any]] else { throw ShelfError.message("Некорректный манифест") }
        let cleanCategory = category.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: "..", with: "-")
        guard !cleanCategory.isEmpty else { throw ShelfError.message("Выберите категорию") }
        if let title, !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { row["name"] = title }
        let name = (row["name"] as? String ?? "App").components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }.joined(separator: "-")
        let relative = replacing?.path ?? cleanCategory + "/" + String(name.prefix(70)) + "-" + UUID().uuidString.prefix(8) + ".ipa"
        let destination = try ArchiveStorage.destination(relative, root: root)
        guard destination.resolvingSymlinksInPath().path.hasPrefix(root.resolvingSymlinksInPath().path + "/") else { throw ShelfError.message("Недопустимый путь") }
        let staging = root.appendingPathComponent("Документы/" + UUID().uuidString + ".incoming")
        try fm.createDirectory(at: staging.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fm.copyItem(at: source, to: staging)
        let stagingHash = try DeviceTools.run(URL(fileURLWithPath: "/usr/bin/shasum"), ["-a", "256", staging.path])
        guard stagingHash.status == 0, stagingHash.output.split(separator: " ").first.map(String.init) == row["sha256"] as? String else {
            try? fm.removeItem(at: staging)
            throw ShelfError.message("Копия IPA в библиотеке повреждена. Проверьте подключение NAS; каталог не изменён.")
        }
        defer { try? fm.removeItem(at: staging) }
        var backup: URL?
        if let replacing {
            let old = try replacing.file(in: root)
            let archive = root.appendingPathComponent("Документы/Резервные-копии")
            try fm.createDirectory(at: archive, withIntermediateDirectories: true)
            let saved = archive.appendingPathComponent(UUID().uuidString + ".ipa.backup")
            try fm.moveItem(at: old, to: saved); backup = saved
            if let oldRow = rows.first(where: { $0["path"] as? String == replacing.path }) {
                for (key, value) in oldRow where row[key] == nil {
                    if key == "versionReleaseDate", oldRow["version"] as? String != row["version"] as? String { continue }
                    row[key] = value
                }
            }
            rows.removeAll { $0["path"] as? String == replacing.path }
        }
        row["path"] = relative; rows.append(row)
        do {
            try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            try fm.moveItem(at: staging, to: destination)
            try JSONSerialization.data(withJSONObject: rows, options: [.prettyPrinted, .sortedKeys]).write(to: manifest, options: .atomic)
        } catch {
            try? fm.removeItem(at: destination)
            if let backup { try? fm.moveItem(at: backup, to: destination) }
            throw error
        }
    }
    static func edit(_ item: IPAItem, root: URL, name: String, category: String) throws -> String {
        try ArchiveStorage.withLock(root) { try editUnlocked(item, root: root, name: name, category: category) }
    }
    private static func editUnlocked(_ item: IPAItem, root: URL, name: String, category: String) throws -> String {
        let title = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, !category.isEmpty, !category.contains("/"), !category.contains("..") else { throw ShelfError.message("Введите название и выберите категорию") }
        let manifest = root.appendingPathComponent("Документы/Манифест.json")
        guard var rows = try JSONSerialization.jsonObject(with: Data(contentsOf: manifest)) as? [[String: Any]],
              let index = rows.firstIndex(where: { $0["path"] as? String == item.path }) else { throw ShelfError.message("Запись не найдена") }
        let source = try item.file(in: root)
        let path = category == item.category ? item.path : category + "/" + source.lastPathComponent
        let destination = try ArchiveStorage.destination(path, root: root)
        guard destination.resolvingSymlinksInPath().path.hasPrefix(root.resolvingSymlinksInPath().path + "/") else { throw ShelfError.message("Недопустимый путь") }
        let moved = source != destination
        if moved {
            guard !FileManager.default.fileExists(atPath: destination.path) else { throw ShelfError.message("В этой категории уже есть файл с таким именем") }
            try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            try FileManager.default.moveItem(at: source, to: destination)
        }
        rows[index]["name"] = title; rows[index]["path"] = path
        do { try JSONSerialization.data(withJSONObject: rows, options: [.prettyPrinted, .sortedKeys]).write(to: manifest, options: .atomic) }
        catch { if moved { try? FileManager.default.moveItem(at: destination, to: source) }; throw error }
        return path
    }
    static func download(id: Int, to destination: URL, onOutput: ((String) -> Void)? = nil) throws -> CommandResult {
        let r = try DeviceTools.run(DeviceTools.executable("ipatool"), ["download", "-i", String(id), "-o", destination.path], timeout: 1800, onOutput: onOutput)
        guard r.status == 0 else { throw ShelfError.message("ipatool:\n" + r.output + "\nИспользуется текущий аккаунт ipatool. Если нужна лицензия, получите приложение этим Apple ID в App Store. Удалённое приложение может быть недоступно даже с лицензией.") }
        return r
    }
}

// ProductType/name facts cross-checked against DeviceKit Device.generated.swift.
enum DeviceModel {
    static let names = ["iPhone14,7": "iPhone 14", "iPhone14,8": "iPhone 14 Plus", "iPhone15,2": "iPhone 14 Pro", "iPhone15,3": "iPhone 14 Pro Max", "iPhone15,4": "iPhone 15", "iPhone15,5": "iPhone 15 Plus", "iPhone16,1": "iPhone 15 Pro", "iPhone16,2": "iPhone 15 Pro Max", "iPhone17,3": "iPhone 16", "iPhone17,4": "iPhone 16 Plus", "iPhone17,1": "iPhone 16 Pro", "iPhone17,2": "iPhone 16 Pro Max", "iPhone17,5": "iPhone 16e", "iPhone18,3": "iPhone 17", "iPhone18,1": "iPhone 17 Pro", "iPhone18,2": "iPhone 17 Pro Max", "iPhone18,4": "iPhone Air", "iPhone18,5": "iPhone 17e", "iPhone19,2": "iPhone 18 Pro", "iPhone19,3": "iPhone 18 Pro Max", "iPhone19,7": "iPhone 18 Pro Max"]
}
struct InstallationEvent: Codable, Identifiable {
    var id = UUID().uuidString
    var date = Date()
    let deviceID: String
    let appName: String
    let bundle: String
    let requestedVersion: String
    let previousVersion: String?
    let resultVersion: String?
    let outcome: String
    let detail: String
    let ipaSHA256: String?
}
struct RememberedDevice: Codable, Identifiable {
    var phone: Phone
    var lastConnected: Date?
    var inventoryChecked: Date?
    var versions: [String: String] = [:]
    var appNames: [String: String] = [:]
    var imagePath: String?
    var imageKind: String?
    var imageDate: Date?
    var source: String = "USB"
    var id: String { phone.id }
}
struct DeviceBook: Codable {
    var devices: [RememberedDevice] = []
    var events: [InstallationEvent] = []
    mutating func remember(_ phone: Phone, connected: Bool = true, source: String = "USB") {
        if let index = devices.firstIndex(where: { $0.id == phone.id }) {
            var merged = phone
            let old = devices[index].phone
            if merged.marketingName.isEmpty && merged.model == old.model { merged.marketingName = old.marketingName }
            if merged.regulatoryModel.isEmpty { merged.regulatoryModel = old.regulatoryModel }
            if merged.modelNumber.isEmpty { merged.modelNumber = old.modelNumber }
            devices[index].phone = merged
            if connected { devices[index].lastConnected = Date(); devices[index].source = "USB" }
        } else {
            devices.append(RememberedDevice(phone: phone, lastConnected: connected ? Date() : nil, source: source))
        }
    }
    mutating func snapshot(_ versions: [String: String], phone: Phone, names: [String: String] = [:]) {
        remember(phone)
        let index = devices.firstIndex { $0.id == phone.id }!
        devices[index].versions = versions
        devices[index].inventoryChecked = Date()
        devices[index].appNames.merge(names) { _, new in new }
    }
    func save(to folder: URL) throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try JSONEncoder().encode(self).write(to: folder.appendingPathComponent("devices-history.json"), options: .atomic)
    }
    static func load(from folder: URL) throws -> DeviceBook {
        let file = folder.appendingPathComponent("devices-history.json")
        guard FileManager.default.fileExists(atPath: file.path) else { return DeviceBook() }
        return try JSONDecoder().decode(DeviceBook.self, from: Data(contentsOf: file))
    }
    /// Only device identification/display fields are imported. The report is data, never instructions.
    static func parseIMazingReport(_ text: String) throws -> Phone {
        var values: [String: String] = [:]
        for line in text.split(whereSeparator: \.isNewline) {
            guard let separator = line.firstIndex(of: ":") else { continue }
            let key = String(line[..<separator]).trimmingCharacters(in: .whitespaces)
            if values[key] == nil { values[key] = String(line[line.index(after: separator)...]).trimmingCharacters(in: .whitespaces) }
        }
        guard let id = values["Unique Device ID"], id.count >= 20, id.count <= 50,
              id.allSatisfy({ $0.isHexDigit || $0 == "-" }), let name = values["Имя"] ?? values["Name"] else {
            throw ShelfError.message("В отчёте iMazing нет корректного UDID и имени устройства")
        }
        let ios = (values["Операционная система"] ?? values["Operating System"] ?? "").replacingOccurrences(of: "iOS ", with: "")
        return Phone(id: id, name: name, ios: ios, model: values["Model Product Type"] ?? "", serial: values["Serial Number"] ?? "", storage: values["Storage - Total"].map { "Объём: " + $0 } ?? "", modelNumber: values["Model Number"] ?? "", regulatoryModel: values["Regulatory Model Number"] ?? "", marketingName: values["Модель"] ?? values["Model"] ?? "")
    }
}

struct InstalledSnapshot: Sendable { let versions: [String: String]; let names: [String: String] }
