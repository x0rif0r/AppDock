import Foundation
import SwiftUI
import AppKit
import CryptoKit

struct StoreAccount: Codable, Identifiable, Sendable {
    let email: String
    var name: String
    var id: String { email.lowercased() }
}
struct PurchasedApp: Codable, Identifiable, Sendable {
    let id: Int
    let name: String
    var bundleID: String?
    var version: String?
    var price: Double?
    var purchaseDate: String?
    var platforms: [String]?
    var source: String? = nil
    var mobile: Bool { platforms == nil || platforms?.isEmpty == true || platforms?.contains("iphone") == true || platforms?.contains("ipad") == true }
}
struct PurchaseSnapshot: Codable, Sendable {
    let account: StoreAccount
    let date: Date
    let apps: [PurchasedApp]
}
enum AppStoreCLI {
    static func json(_ args: [String]) throws -> [String: Any] {
        let result = try DeviceTools.command("ipatool", ["--format", "json", "--non-interactive"] + args, timeout: 120)
        guard result.status == 0 else { throw ShelfError.message("ipatool не выполнил запрос. Проверьте вход Apple ID, сеть и установленную версию ipatool.") }
        for line in result.output.split(separator: "\n").reversed() {
            if let object = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any], object["success"] as? Bool == true || object["apps"] != nil { return object }
        }
        throw ShelfError.message("ipatool вернул неизвестный формат ответа. Обновите ipatool.")
    }
    static func current() throws -> StoreAccount {
        let object = try json(["auth", "info"])
        guard let email = object["email"] as? String, !email.isEmpty else { throw ShelfError.message("Войдите в аккаунт App Store") }
        return StoreAccount(email: email, name: object["name"] as? String ?? email)
    }
    static func purchases(account: StoreAccount, progress: @escaping @Sendable (Int, Int) -> Void) throws -> [PurchasedApp] {
        guard try current().id == account.id else { throw ShelfError.message("Аккаунт ipatool изменился. Обновите список аккаунтов.") }
        var rows: [PurchasedApp] = [], seen: Set<Int> = []
        for page in 1...1000 {
            if Task<Never, Never>.isCancelled { throw CancellationError() }
            let response = try json(["list-purchases", "--max-results", "100", "--page", String(page)])
            guard let raw = response["apps"] as? [[String: Any]] else { throw ShelfError.message("Нет списка покупок в ответе ipatool") }
            let items = try JSONDecoder().decode([PurchasedApp].self, from: JSONSerialization.data(withJSONObject: raw))
            let total = (response["totalCount"] as? NSNumber)?.intValue ?? rows.count + items.count
            if items.isEmpty { break }
            let fresh = items.filter { seen.insert($0.id).inserted }
            guard !fresh.isEmpty else { throw ShelfError.message("Apple повторила страницу покупок. Список не будет записан как полный.") }
            rows += fresh; progress(rows.count, total)
            if rows.count >= total { break }
            if page == 1000 { throw ShelfError.message("История слишком большая; список не сохранён как полный") }
        }
        guard try current().id == account.id else { throw ShelfError.message("Во время запроса изменился Apple ID. Повторите обновление.") }
        return rows
    }
}

@MainActor final class AccountsModel: ObservableObject {
    @Published var accounts: [StoreAccount] = []
    @Published var active: StoreAccount?
    @Published var selectedEmail = ""
    @Published var apps: [PurchasedApp] = []
    @Published var snapshotDate: Date?
    @Published var working = false
    @Published var status = ""
    @Published var error = ""
    @Published var authState = "idle"
    @Published var loaded = 0
    @Published var expected = 0
    private var process: Process?
    private var input: FileHandle?
    private var generation = UUID()
    private var catalogTask: Task<Void, Never>?
    static var folder: URL { Shelf.support.appendingPathComponent("Accounts", isDirectory: true) }
    static func snapshotURL(_ email: String) -> URL {
        let hash = SHA256.hash(data: Data(email.lowercased().utf8)).map { String(format: "%02x", $0) }.joined()
        return folder.appendingPathComponent(hash + ".json")
    }
    init() {
        if let data = try? Data(contentsOf: Self.folder.appendingPathComponent("accounts.json")), let saved = try? JSONDecoder().decode([StoreAccount].self, from: data) { accounts = saved }
    }
    var selectedAccount: StoreAccount? { accounts.first { $0.id == selectedEmail.lowercased() } }
    var selectedIsActive: Bool { active?.id == selectedEmail.lowercased() && active != nil }
    func select(_ email: String) {
        selectedEmail = email; apps = []; snapshotDate = nil
        if let data = try? Data(contentsOf: Self.snapshotURL(email)), let snapshot = try? JSONDecoder().decode(PurchaseSnapshot.self, from: data), snapshot.account.id == email.lowercased() {
            apps = snapshot.apps; snapshotDate = snapshot.date
        }
    }
    private func remember(_ account: StoreAccount) throws {
        if let index = accounts.firstIndex(where: { $0.id == account.id }) { accounts[index] = account } else { accounts.append(account) }
        try FileManager.default.createDirectory(at: Self.folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try JSONEncoder().encode(accounts).write(to: Self.folder.appendingPathComponent("accounts.json"), options: .atomic)
    }
    func refreshCurrent(loadPurchases: Bool = false) {
        guard !working else { return }
        working = true; error = ""; status = "Проверка аккаунта…"
        Task {
            do {
                let account = try await Task.detached { try AppStoreCLI.current() }.value
                active = account; try remember(account); select(account.email); status = "Аккаунт подключён"; working = false
                if loadPurchases { refreshPurchases() }
            } catch { active = nil; working = false; status = "Войдите в App Store"; self.error = error.localizedDescription }
        }
    }
    func refreshPurchases() {
        guard !working, let account = active, selectedIsActive else { return }
        working = true; error = ""; loaded = 0; expected = 0; status = "Получение истории приложений…"
        let request = UUID(); generation = request
        catalogTask = Task {
            do {
                let rows = try await Task.detached {
                    try AppStoreCLI.purchases(account: account, progress: { count, total in
                        Task { @MainActor in if self.generation == request { self.loaded = count; self.expected = total; self.status = "Получено \(count) из \(total)" } }
                    })
                }.value
                guard generation == request else { return }
                let snapshot = PurchaseSnapshot(account: account, date: Date(), apps: rows)
                try JSONEncoder().encode(snapshot).write(to: Self.snapshotURL(account.email), options: .atomic)
                apps = rows; snapshotDate = snapshot.date; working = false; status = "История обновлена · \(rows.count) приложений"
            } catch { guard generation == request else { return }; working = false; self.error = error.localizedDescription; status = "Список не обновлён · показана сохранённая история" }
        }
    }
    func logout() {
        guard !working, active != nil else { return }
        working = true; error = ""; status = "Выход из App Store…"
        Task {
            do {
                _ = try await Task.detached { try AppStoreCLI.json(["auth", "revoke"]) }.value
                active = nil; selectedEmail = ""; apps = []; snapshotDate = nil
                loaded = 0; expected = 0; authState = "idle"; working = false
                status = "Вы вышли из аккаунта. Скачанные IPA и сохранённая история остались на Mac."
            } catch {
                working = false; self.error = "Не удалось выйти из аккаунта: " + error.localizedDescription
            }
        }
    }
    func login(email: String, password: String) {
        guard !working else { return }
        guard !email.isEmpty, !password.isEmpty, !email.contains(where: { "\r\n\0".contains($0) }), !password.contains(where: { "\r\n\0".contains($0) }), email.utf8.count < 4096, password.utf8.count < 4096 else { error = "Проверьте формат логина и пароля"; return }
        let request = UUID(); generation = request
        do {
            let cli = try DeviceTools.executable("ipatool")
            let helper = Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/appdock-auth")
            let task = Process(), stdinPipe = Pipe(), output = Pipe()
            task.executableURL = helper; task.arguments = [cli.path]
            task.standardInput = stdinPipe; task.standardOutput = output; task.standardError = FileHandle.nullDevice
            try task.run(); process = task; input = stdinPipe.fileHandleForWriting
            working = true; authState = "running"; error = ""; status = "Вход в App Store…"
            try input?.write(contentsOf: Data((email + "\n" + password + "\n").utf8))
            let reader = output.fileHandleForReading
            Task.detached {
                var pending = Data()
                while true {
                    let chunk = reader.availableData; if chunk.isEmpty { break }; pending.append(chunk)
                    while let end = pending.firstIndex(of: 10) {
                        let line = pending.prefix(upTo: end); pending.removeSubrange(...end)
                        if let json = try? JSONSerialization.jsonObject(with: line) as? [String: String], let state = json["status"] {
                            await MainActor.run { if self.generation == request { self.authState = state; self.status = state == "awaiting2fa" ? "Apple запросила код 2FA" : "Выполняется вход…" } }
                        }
                    }
                }
                task.waitUntilExit()
                await MainActor.run {
                    guard self.generation == request else { return }
                    self.input?.closeFile(); self.input = nil; self.process = nil; self.working = false
                    if task.terminationStatus == 0 && self.authState == "done" { self.refreshCurrent(loadPurchases: true) }
                    else { self.authState = "failed"; self.error = "Вход не выполнен. Проверьте данные и 2FA. Если ipatool запросил доступ к Связке ключей, разрешите его обычным способом."; self.status = "Вход не выполнен" }
                }
            }
        } catch { working = false; authState = "failed"; self.error = "Не удалось запустить локальный вход: " + error.localizedDescription }
    }
    func submitCode(_ code: String) {
        guard authState == "awaiting2fa", code.count == 6, code.allSatisfy(\.isNumber) else { return }
        do { try input?.write(contentsOf: Data((code + "\n").utf8)); authState = "running" }
        catch { cancelLogin() }
    }
    func cancelLogin() {
        guard process != nil else { return }
        generation = UUID(); input?.closeFile(); input = nil; process?.terminate(); process = nil; working = false; authState = "idle"; status = "Вход отменён"
    }
}

struct AccountLoginView: View {
    @ObservedObject var model: AccountsModel
    @Environment(\.dismiss) private var dismiss
    let suggestedEmail: String
    @State private var email = ""
    @State private var password = ""
    @State private var code = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack { Label("Вход в App Store", systemImage: "person.crop.circle.badge.checkmark").font(.title2.bold()); Spacer(); Button(model.working ? "Отменить вход" : "Готово") { model.cancelLogin(); password = ""; code = ""; dismiss() } }
            Text("Используйте Apple ID из раздела «Медиаматериалы и покупки» на iPhone. Он может отличаться от аккаунта iCloud. Вход выполняется локальным ipatool; пароль не сохраняется AppDock и не передаётся в аргументах процесса. Сессию хранит ipatool в Связке ключей.").font(.caption).foregroundStyle(.secondary)
            TextField("Apple ID: email или телефон", text: $email).textFieldStyle(.roundedBorder).disabled(model.working)
            SecureField("Пароль Apple ID", text: $password).textFieldStyle(.roundedBorder).disabled(model.working)
            if model.authState == "awaiting2fa" {
                SecureField("Код подтверждения Apple · 6 цифр", text: $code).textFieldStyle(.roundedBorder)
                Button("Подтвердить 2FA") { let value = code; code = ""; model.submitCode(value) }.buttonStyle(.borderedProminent).disabled(code.count != 6)
            } else {
                Button("Войти и показать мои приложения") { let secret = password; password = ""; model.login(email: email.trimmingCharacters(in: .whitespacesAndNewlines), password: secret) }.buttonStyle(.borderedProminent).disabled(model.working || email.isEmpty || password.isEmpty)
            }
            if model.working { HStack { ProgressView().controlSize(.small); Text(model.status).font(.caption) } }
            if !model.error.isEmpty { Text(model.error).font(.caption).foregroundStyle(.red) }
        }.padding(28).frame(width: 610)
            .onAppear { email = suggestedEmail }
            .onChange(of: model.active?.email) { _, _ in if model.authState == "done" { dismiss() } }
            .onChange(of: model.authState) { _, state in if state == "done" { password = ""; code = ""; dismiss() } }
    }
}

struct PurchasedIcon: View {
    let app: PurchasedApp
    let embedded: String?
    @State private var icon: NSImage?
    var body: some View {
        Group {
            if let icon { Image(nsImage: icon).resizable().scaledToFit() }
            else { Image(systemName: "app.dashed").font(.system(size: 30)).foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity).background(.quaternary) }
        }.frame(width: 52, height: 52).clipShape(RoundedRectangle(cornerRadius: 12))
            .task(id: app.id) {
                let folder = Shelf.support.appendingPathComponent("PurchaseIcons")
                let target = folder.appendingPathComponent("\(app.id).image")
                if let embedded, let image = NSImage(contentsOfFile: embedded) { icon = image; return }
                if let image = NSImage(contentsOf: target) { icon = image; return }
                for country in ["ru", "us"] {
                    guard !Task.isCancelled else { return }
                    var request = URLRequest(url: URL(string: "https://itunes.apple.com/lookup?id=\(app.id)&country=\(country)")!); request.timeoutInterval = 15
                    guard let (data, _) = try? await URLSession.shared.data(for: request),
                          let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                          let row = (json["results"] as? [[String: Any]])?.first,
                          (row["trackId"] as? NSNumber)?.intValue == app.id,
                          app.bundleID == nil || row["bundleId"] as? String == app.bundleID,
                          let value = row["artworkUrl512"] as? String ?? row["artworkUrl100"] as? String,
                          let url = URL(string: value), url.scheme == "https", url.host?.hasSuffix("mzstatic.com") == true else { continue }
                    request = URLRequest(url: url); request.timeoutInterval = 15
                    if let (bytes, _) = try? await URLSession.shared.data(for: request), bytes.count < 8_000_000, let image = NSImage(data: bytes) {
                        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                        try? bytes.write(to: target, options: .atomic); icon = image; return
                    }
                }
            }
    }
}

struct AccountCatalogView: View {
    @ObservedObject var shelf: Shelf
    @ObservedObject var model: AccountsModel
    @Environment(\.dismiss) private var dismiss
    @State private var loginShown = false
    @State private var loginEmail = ""
    @State private var search = ""
    @State private var selected: Set<Int> = []
    @State private var category = "Другие"
    @State private var mobileOnly = true
    var catalogApps: [PurchasedApp] {
        var apps = model.apps
        var seen = Set(apps.map(\.id))
        for item in shelf.items.sorted(by: { ($0.version ?? "").compare($1.version ?? "", options: .numeric) == .orderedDescending }) {
            guard !model.selectedEmail.isEmpty, item.licenseAccount?.lowercased() == model.selectedEmail.lowercased(), let id = item.idNumber, seen.insert(id).inserted else { continue }
            apps.append(PurchasedApp(id: id, name: item.title, bundleID: item.bundle, version: item.version, price: nil, purchaseDate: nil, platforms: ["iphone"], source: "Сохранённый IPA"))
        }
        return apps
    }
    var rows: [PurchasedApp] { catalogApps.filter { (!mobileOnly || $0.mobile) && (search.isEmpty || "\($0.name) \($0.bundleID ?? "") \($0.id)".localizedCaseInsensitiveContains(search)) }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending } }
    var blocked: Bool { shelf.busy || !shelf.pendingTasks.isEmpty || model.working }
    func existing(_ app: PurchasedApp) -> IPAItem? { shelf.items.first { $0.idNumber == app.id && (shelf.cachedIDs.contains($0.id) || (try? $0.file(in: shelf.sourceRoot($0))) != nil) } }
    func savedForAccount(_ app: PurchasedApp) -> Bool { existing(app)?.licenseAccount?.lowercased() == model.selectedEmail.lowercased() }
    func queue(_ apps: [PurchasedApp]) {
        guard model.selectedIsActive else { return }
        for app in apps where app.mobile && !savedForAccount(app) {
            let old = existing(app)
            shelf.download(id: app.id, category: old?.category ?? category, replacing: old, localOnly: old?.localOnly == true || !shelf.rootAvailable, account: model.selectedEmail)
        }
        selected.removeAll()
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label("Мои приложения App Store", systemImage: "person.crop.rectangle.stack").font(.title2.bold())
                Spacer(); Button("Готово") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            HStack(spacing: 16) {
                Picker("Аккаунт", selection: Binding(get: { model.selectedEmail }, set: { model.select($0); selected.removeAll() })) {
                    Text("Выберите аккаунт").tag("")
                    ForEach(model.accounts) { Text($0.email).tag($0.email) }
                }.frame(maxWidth: 480).disabled(model.working)
                Button(model.selectedIsActive ? "Другой аккаунт…" : "Войти в этот аккаунт…") { loginEmail = model.selectedIsActive ? "" : model.selectedEmail; loginShown = true }.disabled(blocked)
                Button("Выйти", systemImage: "rectangle.portrait.and.arrow.right") { selected.removeAll(); model.logout() }
                    .disabled(blocked || model.active == nil)
                    .help("Выйти из текущего аккаунта ipatool. IPA и сохранённая история останутся на Mac.")
                Button("Обновить") { if model.selectedIsActive { model.refreshPurchases() } else { model.refreshCurrent(loadPurchases: true) } }.disabled(blocked)
            }
            HStack {
                Label(model.active.map { "Активен: " + $0.email } ?? "Вход не выполнен", systemImage: model.active == nil ? "person.crop.circle.badge.questionmark" : "checkmark.shield")
                Spacer(); Text("Показано: \(rows.count) · история: \(model.apps.count) · из IPA: \(catalogApps.count - model.apps.count)")
            }.font(.caption).foregroundStyle(.secondary)
            if model.working { HStack { ProgressView(value: Double(model.loaded), total: Double(max(model.expected, 1))).frame(maxWidth: 220); Text(model.status).font(.caption) } }
            if !model.error.isEmpty { Text(model.error).font(.caption).foregroundStyle(.red) }
            if let date = model.snapshotDate { Text("История аккаунта · обновлена \(date.formatted(date: .abbreviated, time: .shortened))").font(.caption2).foregroundStyle(.secondary) }
            HStack {
                TextField("Поиск по названию, Bundle ID или App Store ID", text: $search).textFieldStyle(.roundedBorder)
                Picker("Сохранить в", selection: $category) { ForEach(Array(Set(shelf.categories + ["Другие", "VPN"])).sorted(), id: \.self) { Text($0).tag($0) } }.frame(width: 235)
            }
            Toggle("Только iPhone и iPad", isOn: $mobileOnly).font(.caption)
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 270), spacing: 12)], spacing: 12) {
                    ForEach(rows) { app in
                        let saved = savedForAccount(app)
                        let queued = shelf.currentTask?.appID == app.id || shelf.pendingTasks.contains { $0.appID == app.id }
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(alignment: .top, spacing: 12) {
                                PurchasedIcon(app: app, embedded: shelf.items.first(where: { $0.idNumber == app.id }).flatMap { shelf.library[$0.id]?.iconPath })
                                VStack(alignment: .leading, spacing: 4) { Text(app.name).font(.headline).lineLimit(2); Text("v\(app.version ?? "—") · ID \(app.id)").font(.caption2).textSelection(.enabled) }
                                Spacer(minLength: 0)
                            }
                            if !app.mobile { Text("Приложение другой платформы · установка на iPhone недоступна").font(.caption2).foregroundStyle(.secondary) }
                            Text(app.purchaseDate.map { "В истории с " + String($0.prefix(10)) } ?? (app.source ?? "Есть в истории аккаунта")).font(.caption2).foregroundStyle(.secondary)
                            HStack {
                                if saved { Label("IPA этого аккаунта уже есть", systemImage: "checkmark.circle").font(.caption2) }
                                else {
                                    Toggle("Выбрать", isOn: Binding(get: { selected.contains(app.id) }, set: { if $0 { selected.insert(app.id) } else { selected.remove(app.id) } })).toggleStyle(.checkbox).font(.caption).disabled(!model.selectedIsActive || model.working || queued || !app.mobile)
                                    Spacer()
                                    Button(queued ? "В очереди" : (existing(app) == nil ? "Скачать" : "Заменить IPA")) { queue([app]) }.font(.caption).disabled(!model.selectedIsActive || model.working || queued || !app.mobile)
                                }
                            }
                        }.padding(14).frame(maxWidth: .infinity, minHeight: 148, alignment: .topLeading)
                            .foregroundStyle(saved ? Color.secondary : Color.primary)
                            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 14))
                    }
                }
                if rows.isEmpty { ContentUnavailableView(model.working ? "Загружается история" : "Нет приложений для показа", systemImage: "app.badge", description: Text(model.active == nil ? "Войдите в свой Apple ID, чтобы увидеть приложения аккаунта." : "Обновите историю или измените поиск.")) }
            }
            HStack {
                Button("Выбрать доступные") { selected = Set(rows.filter { $0.mobile && !savedForAccount($0) }.map(\.id)) }.disabled(!model.selectedIsActive || model.working)
                Button("Снять выбор") { selected.removeAll() }
                Spacer()
                Button("В очередь · \(selected.count)") { queue(rows.filter { selected.contains($0.id) }) }.buttonStyle(.borderedProminent).disabled(selected.isEmpty || !model.selectedIsActive || model.working)
                Button("Очередь · \(shelf.pendingTasks.count)") { shelf.queueShown = true; dismiss() }
            }
            Text("Загрузка использует лицензию выбранного Apple ID. Удалённые приложения могут быть недоступны даже при наличии в истории. Покупки автоматически не выполняются. IPA другого аккаунта можно заменить; старый файл сохраняется в резервных копиях.").font(.caption2).foregroundStyle(.secondary)
        }.padding(24).frame(minWidth: 800, idealWidth: 1080, maxWidth: 1080, minHeight: 550, idealHeight: 750, maxHeight: 750)
            .sheet(isPresented: $loginShown) { AccountLoginView(model: model, suggestedEmail: loginEmail) }
            .onAppear { if model.active == nil && !model.working { model.refreshCurrent(loadPurchases: true) } else if model.apps.isEmpty && !model.working { model.refreshPurchases() } }
    }
}
