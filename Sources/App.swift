import SwiftUI
import AppKit
import UniformTypeIdentifiers

@MainActor final class Shelf: ObservableObject {
    @Published var root: URL
    @Published var items: [IPAItem] = []
    @Published var selected: Set<String> = []
    @Published var category = "Все"
    @Published var search = ""
    @Published var phones: [Phone] = []
    @Published var phoneID = ""
    @Published var installed: [String: String] = [:]
    @Published var states: [String: String] = [:]
    @Published var busy = false { didSet { if busy && !oldValue { operationStarted = Date() } } }
    var operationStarted = Date()
    @Published var refreshing = false
    @Published var cancelRequested = false
    @Published var stopOnError = true
    @Published var headline = "Выберите приложения и подключите iPhone по USB"
    @Published var log = ""
    @Published var completed = 0
    @Published var total = 0
    @Published var errorMessage: String?
    @Published var presets: [String: [String]] = [:]
    @Published var pendingTasks: [QueuedTask] = []
    @Published var currentTask: QueuedTask?
    @Published var queuePaused = false
    @Published var queueShown = false
    @Published var book = DeviceBook()
    @Published var historyShown = false
    @Published var historyDeviceID = ""
    let accounts = AccountsModel()
    @Published var accountsShown = true
    @Published var storageMode = UserDefaults.standard.string(forKey: "storageMode") == "NAS" ? "NAS" : "Local"
    @Published var storageShown = false
    @Published var aboutShown = false
    @Published var rootAvailable = true
    @Published var networkLibrary = false
    @Published var cachedIDs: Set<String> = []
    @Published var localVersions: [IPAItem] = []
    @Published var downloadsShown = false
    @Published var downloadProgress: Double?
    @Published var downloadHistory: [IPAItem] = []
    @Published var library: [String: StorePresentation] = [:]
    private var presentationTask: Task<Void, Never>?
    private var historyWritable = true
    private var logFile: URL?
    static var support: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/IPAOrganizer")
    }
    init() {
        if UserDefaults.standard.string(forKey: "storageMode") == "Dedicated Server" { UserDefaults.standard.set("Local", forKey: "storageMode") }
        let saved = (UserDefaults.standard.dictionary(forKey: "storageRoots") as? [String: String])?[UserDefaults.standard.string(forKey: "storageMode") ?? "Local"] ?? UserDefaults.standard.string(forKey: "archiveRoot")
        root = URL(fileURLWithPath: saved ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads/IPA-Россия").path)
        if let bookmark = UserDefaults.standard.data(forKey: "archiveBookmark") {
            var stale = false
            if let url = try? URL(resolvingBookmarkData: bookmark, options: [.withSecurityScope], relativeTo: nil, bookmarkDataIsStale: &stale) {
                if saved == nil || url.path == saved { root = url; _ = root.startAccessingSecurityScopedResource() }
            }
        }
        if let data = try? Data(contentsOf: Self.support.appendingPathComponent("presets.json")),
           let value = try? JSONDecoder().decode([String: [String]].self, from: data) { presets = value }
        do { book = try DeviceBook.load(from: Self.support) }
        catch { historyWritable = false; errorMessage = "Не удалось прочитать историю устройств: \(error.localizedDescription). Файл истории не будет перезаписан автоматически." }
        if let data = try? Data(contentsOf: Self.support.appendingPathComponent("download-catalog.json")), let rows = try? JSONDecoder().decode([IPAItem].self, from: data) { downloadHistory = rows }
        if saved == nil && !FileManager.default.fileExists(atPath: root.appendingPathComponent("Документы/Манифест.json").path) {
            root = Self.localRoot
            do { try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true); try ArchiveStorage.createLibrary(root) } catch { errorMessage = error.localizedDescription }
        }
        load()
        accounts.refreshCurrent(loadPurchases: true)
    }
    static var localRoot: URL { support.appendingPathComponent("LocalLibrary") }
    func sourceRoot(_ item: IPAItem) -> URL { item.localOnly == true ? Self.localRoot : root }
    func storageLabel(_ item: IPAItem) -> String {
        let cached = cachedIDs.contains(item.id) || item.localOnly == true
        if item.localOnly == true { return "На Mac" }
        if !rootAvailable { return cached ? "На Mac · библиотека отключена" : "Библиотека недоступна" }
        return cached ? (networkLibrary ? "На NAS и Mac" : "Библиотека и кэш Mac") : (networkLibrary ? "На NAS" : "В библиотеке")
    }
    func applyStorageMode(previous: String) {
        guard !busy, pendingTasks.isEmpty else { return }
        var roots = UserDefaults.standard.dictionary(forKey: "storageRoots") as? [String: String] ?? [:]
        roots[previous] = root.path
        if let saved = roots[storageMode] { root = URL(fileURLWithPath: saved) }
        UserDefaults.standard.set(roots, forKey: "storageRoots")
        UserDefaults.standard.set(storageMode, forKey: "storageMode"); load()
    }
    func resolvedPresetPaths(_ name: String) -> [String] {
        (presets[name] ?? []).compactMap { path in
            if items.contains(where: { $0.path == path }) { return path }
            guard let prior = downloadHistory.first(where: { $0.path == path }), let bundle = prior.bundle else { return nil }
            return items.filter { $0.bundle == bundle }.sorted { ($0.version ?? "").compare($1.version ?? "", options: .numeric) == .orderedDescending }.first?.path
        }
    }
    var currentPresetName: String? { category.hasPrefix("preset:") ? String(category.dropFirst(7)) : nil }
    var catalogTitle: String { currentPresetName.map { "Набор «" + $0 + "»" } ?? (category == "Все" ? "Библиотека приложений" : category.replacingOccurrences(of: "-", with: " ")) }
    var categories: [String] { Array(Set(items.map(\.category))).sorted() }
    var visible: [IPAItem] {
        items.filter { item in (currentPresetName.map { resolvedPresetPaths($0).contains(item.path) } ?? (category == "Все" || item.category == category)) &&
            (search.isEmpty || "\(item.title) \(library[item.id]?.title ?? "") \(item.bundle ?? "") \(item.idNumber ?? 0)".localizedCaseInsensitiveContains(search)) }
    }
    var chosen: [IPAItem] { items.filter { selected.contains($0.id) } }
    var phone: Phone? { phones.first { $0.id == phoneID } }
    func load() {
        let folder = root, support = Self.support, localRoot = Self.localRoot
        Task {
            do {
                let result = try await Task.detached { () throws -> ([IPAItem], [IPAItem], Bool, Bool) in
                    var local = (try? DeviceTools.loadManifest(root: localRoot)) ?? []
                    for index in local.indices { local[index].localOnly = true }
                    do {
                        let loaded = try DeviceTools.loadManifest(root: folder)
                        try ArchiveStorage.saveSnapshot(loaded, root: folder, support: support)
                        return (loaded, local, true, ArchiveStorage.isNetwork(folder))
                    } catch {
                        if let snapshot = try? ArchiveStorage.snapshot(folder, support: support) { return (snapshot, local, false, false) }
                        if !local.isEmpty { return ([], local, false, false) }
                        throw error
                    }
                }.value
                guard root == folder else { return }
                rootAvailable = result.2
                if result.2 { networkLibrary = result.3 }
                localVersions = result.1
                let hashes = Set(result.0.compactMap(\.sha256))
                items = (result.0 + result.1.filter { !hashes.contains($0.sha256 ?? "") }).sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
                selected.formIntersection(Set(items.map(\.id)))
                refreshCachedItems()
                for item in items where !downloadHistory.contains(where: { $0.idNumber == item.idNumber && $0.bundle == item.bundle && $0.version == item.version && $0.sha256 == item.sha256 }) { downloadHistory.append(item) }
                do {
                    try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
                    try JSONEncoder().encode(downloadHistory).write(to: support.appendingPathComponent("download-catalog.json"), options: .atomic)
                } catch { errorMessage = "Не удалось сохранить каталог скачиваний: " + error.localizedDescription }
                addDefaultPresets()
                loadPresentations(items)
                if !rootAvailable { headline = "Библиотека отключена. Показан сохранённый каталог; IPA на Mac доступны для установки." }
            } catch { rootAvailable = false; errorMessage = "Не удалось прочитать библиотеку. Подключите NAS или выберите папку хранилища.\n\(error.localizedDescription)" }
        }
    }



    func prepareFile(_ item: IPAItem) async throws -> URL {
        let support = Self.support

        let source = sourceRoot(item)
        return try await Task.detached { try ArchiveStorage.prepare(item, root: source, support: support) }.value
    }
    func refreshCachedItems() {
        let loaded = items, support = Self.support
        Task {
            let cached = await Task.detached { Set(loaded.filter { $0.localOnly == true || ArchiveStorage.isCached($0, support: support) }.map(\.id)) }.value
            cachedIDs = cached
        }
    }
    func chooseFolder() {
        guard !busy, pendingTasks.isEmpty else { return }
        let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = false
        panel.message = "Выберите библиотеку на NAS (подключите SMB в Finder) или локальную папку. В новой папке будет создан пустой каталог; существующие IPA можно импортировать."
        if panel.runModal() == .OK, let url = panel.url {
            Task {
                do {
                    _ = url.startAccessingSecurityScopedResource()
                    try await Task.detached { try ArchiveStorage.createLibrary(url) }.value
                    root.stopAccessingSecurityScopedResource()
                    root = url
                    UserDefaults.standard.set(url.path, forKey: "archiveRoot")
                    var roots = UserDefaults.standard.dictionary(forKey: "storageRoots") as? [String: String] ?? [:]
                    roots[storageMode] = url.path; UserDefaults.standard.set(roots, forKey: "storageRoots")
                    if let bookmark = try? url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil) { UserDefaults.standard.set(bookmark, forKey: "archiveBookmark") }
                    load()
                } catch { errorMessage = error.localizedDescription }
            }
        }
    }
    func cache(_ apps: [IPAItem], exportDirectory: URL? = nil) {
        guard !apps.isEmpty else { return }
        pendingTasks.append(QueuedTask(kind: .cache, title: exportDirectory == nil ? "Сохранить на Mac · \(apps.count) IPA" : "Экспортировать · \(apps.count) IPA", apps: apps, exportDirectory: exportDirectory))
        startNextTask()
    }
    func chooseExport(_ apps: [IPAItem]) {
        let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = false
        panel.message = "Выберите локальную папку для IPA. Существующие файлы не будут перезаписаны."
        if panel.runModal() == .OK, let directory = panel.url { cache(apps, exportDirectory: directory) }
    }
    func performCache(_ task: QueuedTask) {
        busy = true; completed = 0; total = task.apps.count; downloadProgress = nil
        let support = Self.support, libraryRoot = root, localRoot = Self.localRoot
        Task {
            do {
                for item in task.apps {
                    headline = "Сохранение на Mac · \(completed + 1)/\(total) · \(item.title)"
                    _ = try await prepareFile(item)
                    if let directory = task.exportDirectory {
                        try await Task.detached { try ArchiveStorage.export(item, root: item.localOnly == true ? localRoot : libraryRoot, support: support, directory: directory) }.value
                    }
                    completed += 1
                }
                refreshCachedItems(); headline = "Сохранено на Mac: \(completed) IPA"
            } catch { errorMessage = error.localizedDescription; if stopOnError { queuePaused = true } }
            operationFinished()
        }
    }
    func refreshDevices() {
        guard !busy, !refreshing else { return }
        refreshing = true
        Task {
            do {
                let found = try await Task.detached { try DeviceTools.phones() }.value
                phones = found
                for device in found { book.remember(device) }
                try persistBook()
                if !found.contains(where: { $0.id == phoneID }) { phoneID = found.first?.id ?? "" }
                if let phone {
                    let snapshot = try await Task.detached { try DeviceTools.installedSnapshot(on: phone) }.value
                    installed = snapshot.versions
                    try saveSnapshot(installed, phone: phone, deviceNames: snapshot.names)
                    headline = "\(phone.name) · iOS \(phone.ios) · USB"
                } else { installed = [:]; headline = "iPhone не найден. Подключите кабель, разблокируйте и подтвердите доверие." }
            } catch { errorMessage = error.localizedDescription }
            refreshing = false
        }
    }
    func toggleVisible() {
        let ids = Set(visible.map(\.id))
        if ids.isSubset(of: selected) { selected.subtract(ids) } else { selected.formUnion(ids) }
    }
    func savePreset(_ name: String) {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        presets[name] = selected.sorted()
        do { try FileManager.default.createDirectory(at: Self.support, withIntermediateDirectories: true)
            try JSONEncoder().encode(presets).write(to: Self.support.appendingPathComponent("presets.json"), options: .atomic)
        } catch { errorMessage = error.localizedDescription }
    }
    func append(_ text: String) {
        log += text + "\n"
        if let logFile { try? log.write(to: logFile, atomically: true, encoding: .utf8) }
    }
    func install() {
        guard let target = phone, !chosen.isEmpty else { return }
        let queue = chosen
        let bundles = queue.compactMap(\.bundle)
        guard Set(bundles).count == bundles.count else { errorMessage = "Оставьте одну версию каждого приложения с одинаковым Bundle ID"; return }
        pendingTasks.append(QueuedTask(kind: .install, title: "Установить \(queue.count) приложений", apps: queue, phone: target))
        startNextTask()
    }
    func startNextTask() {
        guard !busy, !queuePaused, !pendingTasks.isEmpty else { return }
        let task = pendingTasks.removeFirst()
        currentTask = task
        switch task.kind {
        case .install:
            guard let phone = task.phone else { operationFinished(); return }
            performInstall(task.apps, target: phone)
        case .download:
            guard let id = task.appID else { operationFinished(); return }
            performDownload(id: id, category: task.category, replacing: task.replacing, localOnly: task.localOnly, expectedAccount: task.appleAccount)
        case .cache: performCache(task)
        }
    }
    func operationFinished() {
        busy = false; currentTask = nil
        startNextTask()
    }
    func performInstall(_ queue: [IPAItem], target: Phone) {
        let bundles = queue.compactMap(\.bundle)
        guard Set(bundles).count == bundles.count else {
            errorMessage = "Выбраны несколько IPA с одинаковым Bundle ID. Оставьте одну версию каждого приложения."; return
        }
        busy = true; cancelRequested = false; completed = 0; total = queue.count; log = ""
        let filename = "install-\(Int(Date().timeIntervalSince1970)).log"
        try? FileManager.default.createDirectory(at: Self.support, withIntermediateDirectories: true)
        logFile = Self.support.appendingPathComponent(filename)
        append("Устройство: \(target.name), iOS \(target.ios). Приложений в очереди: \(total).")
        Task {
            for item in queue {
                if cancelRequested { append("Очередь остановлена пользователем. Текущая установка завершена."); break }
                headline = "\(completed + 1)/\(total) · \(item.title)"
                states[item.id] = "Проверка"
                let eventID = UUID().uuidString
                var previousVersion: String?
                do {
                    states[item.id] = "Подготовка локального IPA"
                    let file = try await prepareFile(item)
                    cachedIDs.insert(item.id)
                    guard let bundle = item.bundle, let version = item.version else { throw ShelfError.message("Нет Bundle ID или версии в манифесте") }
                    if let minimum = item.minIOS, !DeviceTools.meetsMinimum(target.ios, minimum) {
                        throw ShelfError.message("Нужна iOS \(minimum)+, на устройстве \(target.ios)")
                    }
                    // Check the selected USB device again before every mutation.
                    let connected = try await Task.detached { try DeviceTools.phones() }.value
                    guard connected.contains(where: { $0.id == target.id }) else { throw ShelfError.message("Выбранный iPhone отключён") }
                    let versions = try await Task.detached { try DeviceTools.installed(on: target) }.value
                    previousVersion = versions[bundle]
                    try saveSnapshot(versions, phone: target)
                    if let current = versions[bundle], current.compare(version, options: .numeric) != .orderedAscending {
                        try record(item, phone: target, eventID: eventID, previous: previousVersion, result: current, outcome: "Пропущено", detail: "Уже установлена такая же или более новая версия")
                        states[item.id] = "Уже есть \(current)"; append("\(item.title): пропущено — на iPhone такая же или более новая версия.")
                    } else {
                        if let expected = item.sha256 {
                            states[item.id] = "Проверка SHA-256"
                            let hash = try await Task.detached { try DeviceTools.run(URL(fileURLWithPath: "/usr/bin/shasum"), ["-a", "256", file.path]) }.value
                            guard hash.status == 0, hash.output.split(separator: " ").first.map(String.init) == expected else {
                                throw ShelfError.message("SHA-256 не совпадает с манифестом. Установка остановлена.")
                            }
                        }
                        try record(item, phone: target, eventID: eventID, previous: previousVersion, result: nil, outcome: "Начато", detail: "Установка запущена")
                        states[item.id] = "Установка"
                        let result = try await Task.detached {
                            try DeviceTools.command("ideviceinstaller", ["-u", target.id, "install", file.path], timeout: 600)
                        }.value
                        append("\(item.title)\n\(result.output)")
                        guard result.status == 0 else {
                            throw ShelfError.message("Установщик завершился с кодом \(result.status). Если требуется лицензия Apple ID, продолжите в iMazing.")
                        }
                        let after = try await Task.detached { try DeviceTools.installed(on: target) }.value
                        if phoneID == target.id { installed = after }
                        try saveSnapshot(after, phone: target)
                        guard after[bundle] == version else { throw ShelfError.message("Версия \(version) не подтверждена на устройстве после установки") }
                        try record(item, phone: target, eventID: eventID, previous: previousVersion, result: after[bundle], outcome: "Установлено", detail: "Версия подтверждена на устройстве после установки")
                        states[item.id] = "Установлено \(version)"
                        append("Подтверждено на iPhone: \(bundle), версия \(version). Запуск и вход не проверены.")
                    }
                } catch {
                    do { try record(item, phone: target, eventID: eventID, previous: previousVersion, result: nil, outcome: "Ошибка", detail: error.localizedDescription) }
                    catch { append("Не удалось сохранить историю: \(error.localizedDescription)") }
                    states[item.id] = "Ошибка"; append("\(item.title): \(error.localizedDescription)")
                    if stopOnError { queuePaused = true; completed += 1; break }
                }
                completed += 1
            }
            if cancelRequested { queuePaused = true }
            headline = cancelRequested ? "Очередь остановлена" : "Обработка завершена. Результаты — в журнале."
            operationFinished()
        }
    }
    func persistBook() throws {
        guard historyWritable else { throw ShelfError.message("История повреждена. Сохраните и восстановите devices-history.json в папке поддержки приложения перед записью новой истории.") }
        try book.save(to: Self.support)
    }
    func saveSnapshot(_ versions: [String: String], phone: Phone, deviceNames: [String: String] = [:]) throws {
        var names = Dictionary(items.compactMap { item -> (String, String)? in item.bundle.map { ($0, item.title) } }, uniquingKeysWith: { old, _ in old })
        names.merge(deviceNames) { _, new in new }
        book.snapshot(versions, phone: phone, names: names)
        try persistBook()
    }
    func record(_ item: IPAItem, phone: Phone, eventID: String, previous: String?, result: String?, outcome: String, detail: String) throws {
        book.remember(phone)
        let event = InstallationEvent(id: eventID, deviceID: phone.id, appName: item.title, bundle: item.bundle ?? "", requestedVersion: item.version ?? "", previousVersion: previous, resultVersion: result, outcome: outcome, detail: detail, ipaSHA256: item.sha256)
        if let index = book.events.firstIndex(where: { $0.id == eventID }) { book.events[index] = event }
        else { book.events.append(event) }
        try persistBook()
    }
    func showHistory(_ id: String? = nil) {
        historyDeviceID = id ?? phoneID
        historyShown = true
    }
    func importDeviceReport() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.plainText]
        panel.message = "Выберите текстовый отчёт iMazing. Импортируются только сведения для карточки устройства."
        guard panel.runModal() == .OK, let file = panel.url else { return }
        do {
            let phone = try DeviceBook.parseIMazingReport(String(contentsOf: file, encoding: .utf8))
            book.remember(phone, connected: false, source: "Отчёт iMazing")
            try persistBook()
            showHistory(phone.id)
        } catch { errorMessage = error.localizedDescription }
    }
    func chooseDeviceImage(_ id: String) {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.png, .jpeg, .heic, .tiff]
        panel.message = "Выберите снимок экрана или картинку для узнаваемой карточки iPhone"
        guard panel.runModal() == .OK, let file = panel.url else { return }
        do { try storeDeviceImage(file, id: id, kind: "Выбранная картинка") }
        catch { errorMessage = error.localizedDescription }
    }
    func storeDeviceImage(_ file: URL, id: String, kind: String) throws {
        guard let index = book.devices.firstIndex(where: { $0.id == id }), NSImage(contentsOf: file) != nil else { throw ShelfError.message("Не удалось открыть изображение") }
        let folder = Self.support.appendingPathComponent("DeviceImages")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let target = folder.appendingPathComponent(UUID().uuidString + "." + file.pathExtension)
        try FileManager.default.copyItem(at: file, to: target)
        book.devices[index].imagePath = target.path
        book.devices[index].imageKind = kind
        book.devices[index].imageDate = Date()
        try persistBook()
    }
    func captureDeviceWallpaper(_ id: String) {
        guard phones.contains(where: { $0.id == id }), !busy else { return }
        busy = true; total = 0; headline = "Получение обоев iPhone…"
        Task {
            let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".png")
            defer { try? FileManager.default.removeItem(at: file); operationFinished() }
            do {
                let helper = Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/appdock-wallpaper")
                let result = try await Task.detached { try DeviceTools.run(helper, [id, file.path], timeout: 30) }.value
                guard result.status == 0 else { throw ShelfError.message(result.output.isEmpty ? "iOS не отдала обои. Разблокируйте iPhone или выберите изображение вручную." : result.output) }
                try storeDeviceImage(file, id: id, kind: "Обои устройства · USB")
                headline = "Обои iPhone сохранены"
            } catch { errorMessage = error.localizedDescription; headline = "Обои не получены" }
        }
    }
    func captureDeviceImage(_ id: String) {
        guard phones.contains(where: { $0.id == id }), !busy else { return }
        busy = true; total = 0; headline = "Получение снимка экрана…"
        Task {
            let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".png")
            defer { try? FileManager.default.removeItem(at: file); operationFinished() }
            do {
                let result = try await Task.detached { try DeviceTools.command("idevicescreenshot", ["-u", id, file.path], timeout: 30) }.value
                guard result.status == 0 else { throw ShelfError.message("Служба снимков экрана iOS недоступна. Для idevicescreenshot нужен смонтированный образ разработчика; настройки телефона автоматически не меняются. Можно выбрать уже готовый снимок с Mac.\n" + result.output) }
                try storeDeviceImage(file, id: id, kind: "Снимок экрана по USB")
                headline = "Снимок экрана сохранён для устройства"
            } catch { errorMessage = error.localizedDescription; headline = "Снимок экрана не получен" }
        }
    }
    func addDefaultPresets() {
        let definitions: [String: [String]] = [
            "Банки": ["com.aconcierge.app", "com.easycatch.sounder", "yoga.appstore", "ru.vtb24.mobilebanking.iphone", "ru.raiffeisenbank.rconnect", "ru.ozon.fintech.finance"],
            "ИИ": ["com.openai.chat", "com.anthropic.claude", "ai.x.GrokApp", "co.anysphere.sand"],
            "Связь": ["ru.mts.mymts", "ru.megafon.lk", "ru.beeline.mobile", "ru.oneme.app", "ru.mail.mail", "com.vk.vkclient"]]
        for (name, bundles) in definitions where presets[name] == nil {
            presets[name] = bundles.compactMap { bundle in items.filter { $0.bundle == bundle }.max { ($0.version ?? "").compare($1.version ?? "", options: .numeric) == .orderedAscending }?.path }
        }
        if presets["Поездки"] == nil { presets["Поездки"] = items.filter { $0.category == "Транспорт" }.map(\.path) }
    }
    func loadPresentations(_ items: [IPAItem]) {
        presentationTask?.cancel()
        let folder = Self.support, archive = root, localRoot = Self.localRoot
        presentationTask = Task {
            let cached = await Task.detached { LibraryArt.cached(items: items, folder: folder) }.value
            guard !Task.isCancelled, root == archive else { return }
            library.merge(cached) { _, new in new }
            for item in items {
                guard !Task.isCancelled, root == archive else { return }
                let presentation: StorePresentation?
                presentation = await Task.detached { LibraryArt.resolve(item, root: item.localOnly == true ? localRoot : archive, folder: folder) }.value
                if let presentation, !Task.isCancelled, root == archive { library[item.id] = presentation }
            }
        }
    }
    func showSelectionInFinder() {
        let urls = chosen.compactMap { item in (try? item.file(in: sourceRoot(item))) ?? ArchiveStorage.cacheFile(item, support: Self.support).flatMap { FileManager.default.fileExists(atPath: $0.path) ? $0 : nil } }
        NSWorkspace.shared.activateFileViewerSelecting(urls)
    }
    func edit(_ item: IPAItem, name: String, category: String) {
        guard !busy else { return }
        do {
            let path = try ArchiveTools.edit(item, root: sourceRoot(item), name: name, category: category)
            if selected.remove(item.path) != nil { selected.insert(path) }
            for key in Array(presets.keys) { presets[key] = presets[key]?.map { $0 == item.path ? path : $0 } }
            try FileManager.default.createDirectory(at: Self.support, withIntermediateDirectories: true)
            try JSONEncoder().encode(presets).write(to: Self.support.appendingPathComponent("presets.json"), options: .atomic)
            load()
        } catch { load(); errorMessage = error.localizedDescription }
    }
    func importIPA(replacing: IPAItem? = nil) {
        guard !busy else { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.init(filenameExtension: "ipa")!]
        panel.allowsMultipleSelection = replacing == nil
        panel.message = replacing.map { "Заменить «\($0.title)». Предыдущий файл сохранится в резервных копиях." } ?? "Добавьте IPA в выбранную категорию. Подпись файла останется без изменений."
        guard panel.runModal() == .OK else { return }
        let sources = panel.urls, folder = replacing.map(sourceRoot) ?? root, group = replacing?.category ?? (category == "Все" || currentPresetName != nil ? "Другие" : category)
        busy = true; total = 0; headline = "Проверка и добавление IPA…"
        Task {
            do {
                for source in sources {
                    try await Task.detached { try ArchiveTools.add(source, root: folder, category: group, replacing: replacing) }.value
                }
                load(); headline = "Добавлено файлов: \(sources.count). Категория: \(group)"
            } catch { errorMessage = error.localizedDescription }
            operationFinished()
        }
    }
    func download(id: Int, category: String, replacing: IPAItem?, localOnly: Bool = false, account: String? = nil) {
        guard !accounts.working else { errorMessage = "Дождитесь завершения входа или обновления истории аккаунта"; return }
        guard id > 0 else { return }
        guard currentTask?.appID != id, !pendingTasks.contains(where: { $0.appID == id }) else { headline = "Этот App Store ID уже в очереди"; return }
        if replacing == nil, items.contains(where: { $0.idNumber == id && ((try? $0.file(in: sourceRoot($0))) != nil || cachedIDs.contains($0.id)) }) { headline = "IPA уже есть. Для повторного скачивания выберите «Обновить через ipatool»."; return }
        pendingTasks.append(QueuedTask(kind: .download, title: replacing.map { "Обновить " + $0.title } ?? "Скачать App Store ID \(id)", appID: id, category: category, replacing: replacing, localOnly: localOnly || replacing?.localOnly == true, appleAccount: account ?? accounts.active?.email))
        startNextTask()
    }
    func performDownload(id: Int, category: String, replacing: IPAItem?, localOnly: Bool = false, expectedAccount: String? = nil) {
        let folder = localOnly ? Self.localRoot : root
        let replacement = replacing.flatMap { ($0.localOnly == true) == localOnly ? $0 : nil }
        let support = Self.support
        busy = true; total = 0; downloadProgress = nil; headline = "Получение ссылки App Store…"; log = ""

        Task {
            do {
                let result = try await Task.detached {
                    let account = try AppStoreCLI.current()
                    if let expectedAccount, account.id != expectedAccount.lowercased() { throw ShelfError.message("Аккаунт ipatool изменился. Войдите в Apple ID, закреплённый за задачей, и повторите загрузку.") }
                    if localOnly {
                        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                        try ArchiveStorage.createLibrary(folder)
                    }
                    let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".ipa")
                    defer { try? FileManager.default.removeItem(at: temporary) }
                    let result = try ArchiveTools.download(id: id, to: temporary, onOutput: { chunk in
                        Task { @MainActor in
                            let expression = try? NSRegularExpression(pattern: #"(?:100|[0-9]{1,2})(?:\.[0-9]+)?%"#)
                            if let match = expression?.matches(in: chunk, range: NSRange(chunk.startIndex..., in: chunk)).last, let range = Range(match.range, in: chunk), let value = Double(chunk[range].dropLast()) {
                                self.downloadProgress = value / 100; self.headline = "Скачивание IPA · \(Int(value))%"
                            } else { self.append(chunk) }
                        }
                    })
                    await MainActor.run { self.downloadProgress = 1; self.headline = "Проверка IPA и добавление в архив…" }
                    let metadata = try ArchiveTools.inspect(temporary)
                    if let email = metadata["licenseAccount"] as? String, email.lowercased() != account.id { throw ShelfError.message("Apple ID в IPA отличается от аккаунта загрузки. Файл не добавлен.") }
                    try ArchiveTools.add(temporary, root: folder, category: category, replacing: replacement, expectedID: id)
                    if localOnly, let saved = try DeviceTools.loadManifest(root: folder).last(where: { $0.idNumber == id }) { _ = try ArchiveStorage.prepare(saved, root: folder, support: support) }
                    return result
                }.value
                append(result.output); load(); headline = "IPA скачан, проверен и добавлен в каталог"
            } catch { errorMessage = error.localizedDescription; headline = "Скачивание не завершено"; append(error.localizedDescription); if stopOnError { queuePaused = true } }
            operationFinished()
        }
    }

}


func categorySymbol(_ category: String) -> String {
    if category.contains("Банки") { return "building.columns.fill" }
    if category.contains("Страх") { return "shield.lefthalf.filled" }
    if category.contains("Транспорт") { return "airplane" }
    if category.contains("Связь") { return "antenna.radiowaves.left.and.right" }
    if category.contains("Покуп") { return "bag.fill" }
    if category.contains("Государ") { return "building.2.fill" }
    if category.contains("провер") { return "exclamationmark.shield.fill" }
    return "square.stack.3d.up.fill"
}

struct AppFamilyRow: View {
    @ObservedObject var shelf: Shelf
    let title: String
    let variants: [IPAItem]
    let update: (IPAItem) -> Void
    let edit: (IPAItem) -> Void
    @State private var expanded = false
    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            VStack(spacing: 9) {
                ForEach(variants) { item in
                    VStack(alignment: .leading, spacing: 7) {
                        AppRow(shelf: shelf, item: item, update: { update(item) }, edit: { edit(item) })
                        HStack {
                            Text("App Store ID: \(item.idNumber.map(String.init) ?? "—") · build \(shelf.library[item.id]?.build ?? item.build ?? "—")")
                            Spacer()
                            Text((shelf.library[item.id]?.firstRelease ?? item.firstRelease).map { "Первый выпуск: " + String($0.prefix(10)) } ?? "Первый выпуск: не подтверждён")
                        }.font(.caption2).foregroundStyle(.secondary).padding(.horizontal, 14)
                        Text("Apple ID для активации: " + (item.licenseAccount ?? "не указан в IPA")).font(.caption).textSelection(.enabled).padding(.horizontal, 14)
                        Text("Bundle ID: \(item.bundle ?? "—") · " + (item.versionReleaseDate.map { "Версия выпущена: " + String($0.prefix(10)) } ?? "Дата выпуска этой версии не подтверждена"))
                            .font(.caption2).foregroundStyle(.secondary).textSelection(.enabled).padding(.horizontal, 14)
                    }
                }
            }.padding(.top, 12)
        } label: {
            HStack(spacing: 12) {
                if let path = variants.first.flatMap({ shelf.library[$0.id]?.iconPath }), let icon = NSImage(contentsOfFile: path) { Image(nsImage: icon).resizable().scaledToFit().frame(width: 36, height: 36).clipShape(RoundedRectangle(cornerRadius: 9)) }
                VStack(alignment: .leading, spacing: 4) { Text(title + (variants.contains(where: \.needsReview) ? " · требует проверки" : "")).font(.headline); Text("Вариантов IPA: \(variants.count) · выбранных: \(variants.filter { shelf.selected.contains($0.id) }.count)").font(.caption).foregroundStyle(.secondary) }
                Spacer()
            }.contentShape(Rectangle()).onTapGesture { withAnimation(.easeInOut(duration: 0.18)) { expanded.toggle() } }
        }.padding(14).background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 14))
    }
}
struct AppRow: View {
    @ObservedObject var shelf: Shelf
    let item: IPAItem
    let update: () -> Void
    let edit: () -> Void
    var selected: Bool { shelf.selected.contains(item.id) }
    var body: some View {
        HStack(spacing: 14) {
            Button {
                if selected { shelf.selected.remove(item.id) } else { shelf.selected.insert(item.id) }
            } label: {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.title2).foregroundStyle(selected ? Color.accentColor : Color.secondary.opacity(0.45))
            }.buttonStyle(.plain).accessibilityLabel("Выбрать \(item.title)")
            Group {
                if let path = shelf.library[item.id]?.iconPath, let image = NSImage(contentsOfFile: path) {
                    Image(nsImage: image).resizable().interpolation(.high).scaledToFit()
                } else {
                    Image(systemName: categorySymbol(item.category)).font(.title2).foregroundStyle(.indigo).frame(maxWidth: .infinity, maxHeight: .infinity).background(Color.indigo.opacity(0.1))
                }
            }.frame(width: 46, height: 46).clipShape(RoundedRectangle(cornerRadius: 11))
                .help(shelf.library[item.id]?.source ?? "Официальная иконка пока недоступна")
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Text(shelf.library[item.id]?.title ?? item.title).font(.headline).lineLimit(1)
                    if item.needsReview { Image(systemName: "exclamationmark.shield").foregroundStyle(.orange).help("Происхождение требует проверки") }
                    if item.foreignBank { Text("Беларусь").font(.caption).foregroundStyle(.secondary) }
                }
                Text(item.bundle.flatMap { shelf.installed[$0] }.map { "На iPhone: v" + $0 } ?? (item.publisher ?? item.category)).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 5) {
                Text("v\(item.version ?? "—")").font(.callout.weight(.medium))
                Text("iOS \(item.minIOS ?? "—")+ · \((item.bytes ?? 0) / 1_048_576) МБ").font(.caption).foregroundStyle(.secondary)
                Text(shelf.storageLabel(item)).font(.caption2).foregroundStyle(.secondary)
            }
            Menu {
                Button("Обновить через ipatool", action: update).disabled(item.idNumber == nil)
                Button("Заменить IPA…") { shelf.importIPA(replacing: item) }.disabled(shelf.busy)
                Button("Название и категория…", action: edit).disabled(shelf.busy)
                Button("Сохранить на этом Mac") { shelf.cache([item]) }
                Button("Сохранить в папку…") { shelf.chooseExport([item]) }
                Button("Показать в Finder") {
                    if let file = try? item.file(in: shelf.sourceRoot(item)) { NSWorkspace.shared.activateFileViewerSelecting([file]) }
                }
                Divider()
                Text("Apple ID для активации: " + (item.licenseAccount ?? "не указан в IPA")).font(.caption).textSelection(.enabled).padding(.horizontal, 14)
                        Text("Bundle ID: \(item.bundle ?? "—")")
                Text("App Store ID: \(item.idNumber.map(String.init) ?? "—")")
            } label: { Image(systemName: "ellipsis").frame(width: 24, height: 24) }
                .menuStyle(.borderlessButton).fixedSize()
        }
        .padding(14)
        .background(selected ? Color.accentColor.opacity(0.07) : Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(selected ? Color.accentColor.opacity(0.35) : Color.primary.opacity(0.05)))
        .overlay(alignment: .bottomLeading) {
            if let status = shelf.states[item.id] {
                Text(status).font(.caption2).foregroundStyle(status == "Ошибка" ? .red : .secondary).padding(.leading, 88).offset(y: 5)
            }
        }
        .help("\(item.bundle ?? "")\n\(item.bundle.flatMap { shelf.installed[$0] }.map { "На устройстве: \($0)" } ?? "")")
    }
}

struct DownloadSheet: View {
    @ObservedObject var shelf: Shelf
    let replacing: IPAItem?
    @Environment(\.dismiss) private var dismiss
    @State private var appID = ""
    @State private var category = "Другие"
    @State private var localOnly = false
    var parsedID: Int? {
        let text = appID.trimmingCharacters(in: .whitespacesAndNewlines)
        if let id = Int(text), id > 0 { return id }
        guard let range = text.range(of: "id[0-9]+", options: .regularExpression) else { return nil }
        return Int(text[range].dropFirst(2))
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Label(replacing == nil ? "Скачать приложение" : "Обновить IPA", systemImage: "arrow.down.app.fill").font(.title2.bold())
            Text(replacing.map { "Будет скачана доступная версия «\($0.title)». Текущий IPA сохранится в резервных копиях." } ?? "Добавьте App Store ID или ссылку на приложение. После скачивания оно появится в вашем каталоге.").foregroundStyle(.secondary)
            TextField("App Store ID или https://apps.apple.com/…", text: $appID).textFieldStyle(.roundedBorder)
            Picker("Категория", selection: $category) {
                ForEach(Array(Set(shelf.categories + ["Другие"])).sorted(), id: \.self) { Text($0).tag($0) }
            }.disabled(replacing != nil)
            Picker("Сохранить", selection: $localOnly) {
                Text("Основная библиотека / NAS").tag(false)
                Text("Только на этом Mac").tag(true)
            }.pickerStyle(.segmented)
            if !shelf.rootAvailable && !localOnly { Text("Библиотека недоступна. Подключите NAS или выберите сохранение на Mac.").font(.caption).foregroundStyle(.orange) }
            VStack(alignment: .leading, spacing: 8) {
                Label("Текущий аккаунт ipatool", systemImage: "person.crop.circle")
                Text(shelf.accounts.active.map { "Apple ID: " + $0.email } ?? "Войдите через «Мои приложения App Store». Приложение должно иметь лицензию на этом аккаунте.").font(.caption).foregroundStyle(.secondary)
            }.padding(14).frame(maxWidth: .infinity, alignment: .leading).background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
            HStack {
                Button("Отмена") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("Скачать и добавить") {
                    if let id = parsedID { shelf.download(id: id, category: category, replacing: replacing, localOnly: localOnly); dismiss() }
                }.buttonStyle(.borderedProminent).disabled(parsedID == nil || (!localOnly && !shelf.rootAvailable)).keyboardShortcut(.defaultAction)
            }
        }.padding(28).frame(width: 520)
        .onAppear { appID = replacing?.idNumber.map(String.init) ?? ""; localOnly = replacing?.localOnly == true || !shelf.rootAvailable; category = replacing?.category ?? (shelf.category == "Все" || shelf.currentPresetName != nil ? "Другие" : shelf.category) }
    }
}

struct EditSheet: View {
    @ObservedObject var shelf: Shelf
    let item: IPAItem
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var category = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Название и категория").font(.title2.bold())
            TextField("Название", text: $name).textFieldStyle(.roundedBorder)
            Picker("Категория", selection: $category) {
                ForEach(Array(Set(shelf.categories + ["Другие"])).sorted(), id: \.self) { Text($0).tag($0) }
            }
            Text("Меняется только запись каталога и папка хранения. Содержимое и подпись IPA сохраняются.").font(.caption).foregroundStyle(.secondary)
            HStack {
                Button("Отмена") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("Сохранить") { shelf.edit(item, name: name, category: category); dismiss() }.buttonStyle(.borderedProminent).disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }.padding(28).frame(width: 460).onAppear { name = item.title; category = item.category }
    }
}

struct DevicePanel: View {
    @ObservedObject var shelf: Shelf
    @State private var showIdentifiers = false
    var device: RememberedDevice? {
        if let phone = shelf.phone { return shelf.book.devices.first { $0.id == phone.id } }
        return shelf.book.devices.first
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 15) {
                HStack {
                    Text("Устройство").font(.headline)
                    Spacer()
                    Button { shelf.refreshDevices() } label: { if shelf.refreshing { ProgressView().controlSize(.small) } else { Image(systemName: "arrow.clockwise") } }.buttonStyle(.plain).disabled(shelf.busy || shelf.refreshing).help("Обновить устройства")
                }
                PhonePreview(device: device)
                if let phone = shelf.phone {
                    Picker("Подключённое устройство", selection: $shelf.phoneID) { ForEach(shelf.phones) { Text($0.name).tag($0.id) } }.labelsHidden()
                    Text(phone.name).font(.title3.bold())
                    Text(device?.phone.displayModel ?? phone.displayModel).font(.callout)
                    Label("iOS \(phone.ios) · USB", systemImage: "cable.connector").font(.caption).foregroundStyle(.secondary)
                    if !phone.modelNumber.isEmpty { Text("Номер модели: \(phone.modelNumber)").font(.caption).foregroundStyle(.secondary) }
                    if !phone.battery.isEmpty { Label("Заряд \(phone.battery)%", systemImage: "battery.75percent").font(.caption) }
                    if !phone.storage.isEmpty { Text(phone.storage).font(.caption).foregroundStyle(.secondary) }
                    DisclosureGroup("Идентификаторы", isExpanded: $showIdentifiers) {
                        Text("Серийный номер: \(phone.serial)\nМодель: \(device?.phone.regulatoryModel ?? phone.regulatoryModel)\nUDID: \(phone.id)").font(.caption2).textSelection(.enabled)
                    }.font(.caption)
                } else if let device {
                    Text(device.phone.name).font(.title3.bold())
                    Text(device.phone.displayModel).font(.callout)
                    Label("Не подключено", systemImage: "cable.connector.slash").font(.caption).foregroundStyle(.secondary)
                    Text("Подключите iPhone по USB, чтобы установить приложения.").font(.caption).foregroundStyle(.secondary)
                } else {
                    Text("Подключите iPhone").font(.title3.bold())
                    Text("Используйте USB-кабель. Разблокируйте iPhone и подтвердите доверие.").font(.caption).foregroundStyle(.secondary)
                }
                HStack {
                    Button("История") { shelf.showHistory(device?.id) }
                    if let device {
                        Menu { Button("Получить обои по USB") { shelf.captureDeviceWallpaper(device.id) }.disabled(shelf.phone == nil || shelf.busy); Button("Выбрать картинку…") { shelf.chooseDeviceImage(device.id) }; Button("Снимок по USB") { shelf.captureDeviceImage(device.id) }.disabled(shelf.phone == nil || shelf.busy) } label: { Image(systemName: "photo") }.fixedSize().disabled(shelf.busy)
                    }
                }
                Divider()
                HStack { Text("Выбрано"); Spacer(); Text("\(shelf.chosen.count)").fontWeight(.semibold) }
                Text(shelf.chosen.isEmpty ? "0 МБ" : ByteCountFormatter.string(fromByteCount: shelf.chosen.reduce(0) { $0 + ($1.bytes ?? 0) }, countStyle: .file)).font(.caption).foregroundStyle(.secondary)
                if shelf.busy {
                    if let progress = shelf.downloadProgress, shelf.currentTask?.kind == .download { ProgressView(value: progress); Text("\(Int(progress * 100))%").font(.caption.monospacedDigit()) } else { ProgressView().controlSize(.small) }
                    Text(shelf.headline).font(.caption).foregroundStyle(.secondary)
                    if shelf.currentTask?.kind == .install { ProgressView(value: Double(shelf.completed), total: Double(max(shelf.total, 1))) }
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        let fraction = shelf.total > 0 ? Double(shelf.completed) / Double(shelf.total) : (shelf.downloadProgress ?? 0)
                        let elapsed = context.date.timeIntervalSince(shelf.operationStarted)
                        let remaining = fraction > 0 && fraction < 1 ? elapsed * (1 - fraction) / fraction : 0
                        Text(shelf.total > 0 ? "Готово \(shelf.completed) из \(shelf.total) · осталось \(max(0, shelf.total - shelf.completed)) приложений" : "Загрузка \(Int(fraction * 100))%")
                        Text(remaining > 0 ? "Примерно осталось \(Int(remaining) / 60) мин \(Int(remaining) % 60) с" : (fraction >= 1 ? "Завершение и проверка…" : "Оценка времени появится после начала передачи"))
                            .font(.caption2).foregroundStyle(.secondary)
                    }

                }
                Button { shelf.install() } label: {
                    Label(shelf.busy || shelf.queuePaused ? "Добавить в очередь" : "Установить на iPhone", systemImage: shelf.busy ? "plus" : "arrow.down.to.line").frame(maxWidth: .infinity).padding(.vertical, 5)
                }.buttonStyle(.borderedProminent).controlSize(.large).disabled(shelf.phone == nil || shelf.chosen.isEmpty || shelf.refreshing)
                Button("Очередь · \(shelf.pendingTasks.count)") { shelf.queueShown = true }.frame(maxWidth: .infinity)
                Toggle("Остановить при ошибке", isOn: $shelf.stopOnError).font(.caption).disabled(shelf.busy)
                ForEach(Array(Set(shelf.chosen.map { $0.licenseAccount ?? "не указан в IPA" })).sorted(), id: \.self) { account in Text("Apple ID: " + account).font(.caption2).textSelection(.enabled) }
                Text("Более новые версии пропускаются. Лицензии Apple ID сохраняются.").font(.caption2).foregroundStyle(.secondary)
            }.padding(22)
        }.frame(width: 275).frame(maxHeight: .infinity).background(Color(nsColor: .controlBackgroundColor))
    }
}

struct MainView: View {
    @StateObject private var shelf = Shelf()
    @State private var presetName = ""
    @State private var downloadRequest: DownloadRequest?
    @State private var logShown = false
    @State private var editItem: IPAItem?
    var body: some View {
        NavigationSplitView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 10) {
                    Image(systemName: "square.stack.3d.up.fill").font(.title2).foregroundStyle(.indigo)
                    Text("AppDock").font(.title2.bold())
                }.padding(.top, 18)
                Text("Ваш набор для iPhone").font(.caption).foregroundStyle(.secondary)
                List(selection: $shelf.category) {
                    HStack { Label("Все", systemImage: "square.grid.2x2.fill"); Spacer(); Text("\(shelf.items.count)").foregroundStyle(.secondary) }.tag("Все")
                    Section("Категории") {
                        ForEach(shelf.categories, id: \.self) { group in
                            HStack {
                                Label(group == "Требует-проверки" ? "Проверить" : group.replacingOccurrences(of: "-", with: " "), systemImage: categorySymbol(group))
                                Spacer()
                                Text("\(shelf.items.filter { $0.category == group }.count)").font(.caption).foregroundStyle(.secondary)
                            }.tag(group)
                        }
                    }
                    if !shelf.presets.isEmpty {
                        Section("Наборы") {
                            ForEach(shelf.presets.keys.sorted(), id: \.self) { name in
                                HStack { Label(name, systemImage: "tray.full"); Spacer(); Text("\(shelf.resolvedPresetPaths(name).count)").font(.caption).foregroundStyle(.secondary) }.tag("preset:" + name)
                            }
                        }
                    }
                }.listStyle(.sidebar)
                Button("Устройства и история", systemImage: "iphone.gen3") { shelf.showHistory() }.buttonStyle(.plain)
                Button("Мои приложения App Store", systemImage: "person.crop.rectangle.stack") { shelf.accountsShown = true }.buttonStyle(.plain)
                Button("Каталог скачиваний", systemImage: "arrow.down.circle") { shelf.downloadsShown = true }.buttonStyle(.plain)
                Button("Очередь задач", systemImage: "list.bullet.clipboard") { shelf.queueShown = true }.buttonStyle(.plain)
                Button("Хранилище", systemImage: "externaldrive.connected.to.line.below") { shelf.storageShown = true }.buttonStyle(.plain)
                Button("О приложении и лицензии", systemImage: "info.circle") { shelf.aboutShown = true }.buttonStyle(.plain)
                Button("Папка библиотеки", systemImage: "folder") { shelf.chooseFolder() }.buttonStyle(.plain).disabled(shelf.busy || !shelf.pendingTasks.isEmpty)
                Text(shelf.root.path).font(.caption2).foregroundStyle(.tertiary).lineLimit(2)
            }.padding(16).navigationSplitViewColumnWidth(min: 220, ideal: 245, max: 280)
        } detail: {
            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(shelf.catalogTitle).font(.system(size: 28, weight: .bold))
                            Text("IPA: \(shelf.visible.count) · " + (shelf.rootAvailable ? (shelf.networkLibrary ? "NAS подключён" : "Локальная библиотека") : "Библиотека отключена")).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Menu {
                            Button("Добавить IPA…") { shelf.importIPA() }.disabled(shelf.busy)
                            Button("Мои приложения App Store…") { shelf.accountsShown = true }
                            Button("Скачать через ipatool…") { downloadRequest = DownloadRequest(replacing: nil) }
                            Divider()
                            Button("Перечитать каталог") { shelf.load() }.disabled(shelf.busy)
                        } label: { Label("Добавить", systemImage: "plus") }.menuStyle(.borderlessButton).fixedSize()
                    }.padding(24)
                    HStack(spacing: 10) {
                        Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                        TextField("Поиск приложений", text: $shelf.search).textFieldStyle(.plain)
                        if !shelf.search.isEmpty { Button { shelf.search = "" } label: { Image(systemName: "xmark.circle.fill") }.buttonStyle(.plain).foregroundStyle(.secondary) }
                    }.padding(12).background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12)).padding(.horizontal, 24)
                    HStack {
                        Button("Выбрать все") { shelf.toggleVisible() }
                        Button("Снять выбор") { shelf.selected.removeAll() }.disabled(shelf.selected.isEmpty)
                        Spacer()
                        Text("Выбрано \(shelf.selected.count)").foregroundStyle(.secondary)
                    }.font(.caption).buttonStyle(.plain).padding(.horizontal, 26).padding(.vertical, 16)
                    ScrollView {
                        LazyVStack(spacing: 9) {
                            ForEach(Array(Set(shelf.visible.map(\.family))).sorted(), id: \.self) { family in
                                AppFamilyRow(shelf: shelf, title: family, variants: shelf.visible.filter { $0.family == family }, update: { downloadRequest = DownloadRequest(replacing: $0) }, edit: { editItem = $0 })
                            }
                            if shelf.visible.isEmpty {
                                ContentUnavailableView("Приложений нет", systemImage: "square.stack", description: Text("Измените поиск или добавьте IPA в эту категорию."))
                            }
                        }.padding(.horizontal, 24).padding(.bottom, 20)
                    }
                    Divider()
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            TextField("Название набора", text: $presetName).textFieldStyle(.roundedBorder).frame(maxWidth: 180)
                            Button("Сохранить") { shelf.savePreset(presetName) }.disabled(shelf.selected.isEmpty || presetName.isEmpty)
                            Spacer()
                            Button { shelf.showSelectionInFinder() } label: { Image(systemName: "folder") }.help("Выбранные IPA в Finder").disabled(shelf.selected.isEmpty)
                            Button { logShown.toggle() } label: { Image(systemName: "text.alignleft") }.help("Журнал")
                        }
                        Text(shelf.headline).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                        if logShown {
                            ScrollView { Text(shelf.log.isEmpty ? "Здесь появятся результаты скачивания и установки." : shelf.log).font(.system(.caption, design: .monospaced)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }.frame(height: 110)
                        }
                    }.padding(20)
                }.frame(maxWidth: .infinity).background(Color(nsColor: .windowBackgroundColor))
                Divider()
                DevicePanel(shelf: shelf)
            }
        }
        .tint(.indigo)
        .frame(minWidth: 1160, minHeight: 760)
        .task {
            shelf.refreshDevices()
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(15))
                if Task.isCancelled { break }
                shelf.refreshDevices()
            }
        }
        .onChange(of: shelf.category) { _, _ in
            if let name = shelf.currentPresetName { shelf.selected = Set(shelf.resolvedPresetPaths(name)).intersection(Set(shelf.items.map(\.id))); presetName = name }
        }
        .onChange(of: shelf.phoneID) { _, _ in shelf.installed = [:]; if !shelf.refreshing { shelf.refreshDevices() } }
        .sheet(isPresented: $shelf.historyShown) { DeviceHistoryView(shelf: shelf) }
        .sheet(isPresented: $shelf.accountsShown) { AccountCatalogView(shelf: shelf, model: shelf.accounts) }
        .sheet(isPresented: $shelf.storageShown) { StorageView(shelf: shelf) }
        .sheet(isPresented: $shelf.aboutShown) { AboutAppDockView() }
        .sheet(isPresented: $shelf.downloadsShown) { DownloadsCatalogView(shelf: shelf) }
        .sheet(isPresented: $shelf.queueShown) { QueueView(shelf: shelf) }
        .sheet(item: $editItem) { EditSheet(shelf: shelf, item: $0) }
        .sheet(item: $downloadRequest) { request in DownloadSheet(shelf: shelf, replacing: request.replacing) }
        .alert("Не удалось выполнить действие", isPresented: Binding(get: { shelf.errorMessage != nil }, set: { if !$0 { shelf.errorMessage = nil } })) {
            Button("Понятно") { shelf.errorMessage = nil }
        } message: { Text(shelf.errorMessage ?? "") }
    }
}

@main struct IPAOrganizerApp: App {
    var body: some Scene {
        WindowGroup("AppDock") { MainView() }
        .windowStyle(.titleBar)
        .commands { CommandGroup(replacing: .newItem) {} }
    }
}
