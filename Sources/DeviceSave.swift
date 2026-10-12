import SwiftUI
import AppKit

struct CommunityApp: Decodable {
    let id: Int
    let name: String
    let bundleID: String?
}
struct CommunityCatalog: Decodable {
    let apps: [CommunityApp]
    static let bundled: [CommunityApp] = {
        guard let url = Bundle.main.url(forResource: "app-catalog", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let catalog = try? JSONDecoder().decode(Self.self, from: data) else { return [] }
        return catalog.apps
    }()
}

/// Exact identifiers only. An ambiguous mapping is never chosen automatically.
enum DeviceAppMatch {
    static func resolve(deviceID: Int?, candidates: [Int]) -> Int? {
        let ids = Set(candidates.filter { $0 > 0 })
        if let deviceID, deviceID > 0 { return ids.isEmpty || ids == [deviceID] ? deviceID : nil }
        return ids.count == 1 ? ids.first : nil
    }
}

struct DeviceSaveView: View {
    @ObservedObject var shelf: Shelf
    @ObservedObject var model: AccountsModel
    let device: RememberedDevice
    @State private var selected: Set<String> = []
    @State private var search = ""
    @State private var onlyKnown = true
    @State private var loginShown = false
    @State private var pendingDownloads: [Int] = []
    @State private var pendingAccount = ""
    @State private var availability: [String: String] = [:]
    @State private var checking: Set<String> = []
    var blocked: Bool { shelf.busy || shelf.refreshing || !shelf.pendingTasks.isEmpty || model.working }
    var bundles: [String] {
        device.versions.keys.filter { !onlyKnown || identifier($0) != nil }.filter { search.isEmpty || ((device.appNames[$0] ?? $0) + " " + $0).localizedCaseInsensitiveContains(search) }.sorted {
            (device.appNames[$0] ?? $0).localizedStandardCompare(device.appNames[$1] ?? $1) == .orderedAscending
        }
    }
    func identifier(_ bundle: String) -> Int? {
        let candidates = shelf.items.filter { $0.bundle == bundle }.compactMap(\.idNumber)
            + model.apps.filter { $0.bundleID == bundle }.map(\.id)
            + CommunityCatalog.bundled.filter { $0.bundleID == bundle }.map(\.id)
        return DeviceAppMatch.resolve(deviceID: device.storeIDs?[bundle], candidates: candidates)
    }
    func saved(_ bundle: String) -> IPAItem? {
        shelf.items.first { $0.bundle == bundle && (shelf.cachedIDs.contains($0.id) || (try? $0.file(in: shelf.sourceRoot($0))) != nil) }
    }
    var savedVisibleIDs: Set<String> { Set(bundles.compactMap { saved($0)?.id }) }
    func enqueue(_ ids: [Int]) {
        guard model.selectedIsActive, !model.working else { return }
        for id in Set(ids).sorted() { shelf.download(id: id, category: "С iPhone", replacing: nil, account: model.selectedEmail) }
        selected.removeAll()
    }
    func startDownloads() {
        let ids = selected.filter { saved($0) == nil }.compactMap(identifier)
        guard !ids.isEmpty, !blocked else { return }
        if model.selectedIsActive { enqueue(ids) }
        else { pendingDownloads = ids; pendingAccount = model.selectedEmail; loginShown = true }
    }
    func checkAvailability(_ bundle: String, id: Int) {
        checking.insert(bundle)
        Task {
            defer { checking.remove(bundle) }
            do {
                let url = URL(string: "https://itunes.apple.com/lookup?id=\(id)&country=ru")!
                let (data, response) = try await URLSession.shared.data(from: url)
                guard (response as? HTTPURLResponse)?.statusCode == 200,
                      let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let results = json["results"] as? [[String: Any]] else { throw ShelfError.message("Ошибка ответа App Store") }
                if results.isEmpty { availability[bundle] = "Нет в витрине RU" }
                else if results.contains(where: { ($0["bundleId"] as? String) == bundle && ($0["trackId"] as? NSNumber)?.intValue == id }) { availability[bundle] = "Есть в витрине RU" }
                else { availability[bundle] = "Идентификаторы не совпали" }
            } catch { availability[bundle] = "Проверка не удалась" }
        }
    }
    func propose(_ bundle: String, id: Int) {
        let name = device.appNames[bundle] ?? bundle
        let body = "Название: \(name)\nApp Store ID: \(id)\nBundle ID: \(bundle)\nВерсия на устройстве: \(device.versions[bundle] ?? "")\nПроверка: не найдено в публичной витрине RU. Это не доказывает удаление во всех странах.\nИсточник подлинности: [добавьте официальный источник]\n"
        var components = URLComponents(string: "https://github.com/x0rif0r/AppDock/issues/new")!
        components.queryItems = [URLQueryItem(name: "title", value: "Каталог: " + name), URLQueryItem(name: "body", value: body)]
        if let url = components.url { NSWorkspace.shared.open(url) }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Сохранить приложения старого iPhone").font(.title3.bold())
            Text("Выберите приложения: IPA скачиваются из App Store по лицензии вашего аккаунта. Версия загрузки может отличаться от установленной. Затем выберите новый iPhone в главном окне и установите сохранённый набор.").font(.caption).foregroundStyle(.secondary)
            HStack {
                Button("Прочитать по USB", systemImage: "arrow.clockwise") { shelf.phoneID = device.id; shelf.refreshDevices() }.disabled(blocked || !shelf.phones.contains { $0.id == device.id })
                Picker("Apple ID", selection: Binding(get: { model.selectedEmail }, set: {
                    model.select($0)
                    if !$0.isEmpty && !model.selectedIsActive { pendingDownloads = []; loginShown = true }
                })) {
                    Text("Выберите аккаунт").tag("")
                    ForEach(model.accounts) { Text($0.email).tag($0.email) }
                }.disabled(blocked)
            }
            TextField("Название или Bundle ID", text: $search).textFieldStyle(.roundedBorder)
            HStack {
                if model.selectedIsActive {
                    Label("Сессия подтверждена: \(model.selectedEmail)", systemImage: "checkmark.shield").font(.caption).foregroundStyle(.secondary)
                } else {
                    Text("Показана сохранённая история. Вход в выбранный аккаунт не выполнен.").font(.caption).foregroundStyle(.orange)
                    Button("Войти в этот аккаунт…") { pendingDownloads = []; loginShown = true }.disabled(blocked || model.selectedEmail.isEmpty)
                }
            }
            Toggle("Только найденные ID · \(device.versions.keys.filter { identifier($0) != nil }.count) из \(device.versions.count)", isOn: $onlyKnown).toggleStyle(.checkbox)
            if device.inventoryChecked == nil { Text("Сначала прочитайте список приложений по USB.").foregroundStyle(.secondary) }
            ForEach(bundles, id: \.self) { bundle in
                let id = identifier(bundle)
                let existing = saved(bundle)
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Toggle(isOn: Binding(get: { selected.contains(bundle) }, set: { if $0 { selected.insert(bundle) } else { selected.remove(bundle) } })) {
                            VStack(alignment: .leading) {
                                Text(device.appNames[bundle] ?? bundle).font(.headline)
                                Text("v\(device.versions[bundle] ?? "") · \(bundle)").font(.caption).textSelection(.enabled)
                            }
                        }.toggleStyle(.checkbox).disabled(existing != nil || id == nil || blocked)
                        Spacer()
                        Text(existing != nil ? "IPA сохранён" : id.map { "ID \($0)" } ?? "ID не определён").font(.caption)
                    }
                    if let id {
                        HStack {
                            Button(checking.contains(bundle) ? "Проверяем…" : "Проверить App Store") { checkAvailability(bundle, id: id) }.disabled(checking.contains(bundle))
                            if let status = availability[bundle] { Text(status).font(.caption) }
                            if availability[bundle] == "Нет в витрине RU", !CommunityCatalog.bundled.contains(where: { $0.id == id }) {
                                Button("Предложить в каталог…") { propose(bundle, id: id) }.help("Откроется черновик заявки. Добавьте источник и отправьте самостоятельно.")
                            }
                        }.font(.caption)
                    }
                }.padding(12).foregroundStyle(existing != nil ? .secondary : .primary)
                    .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 12))
            }
            HStack {
                Button("Выбрать найденные") { selected = Set(bundles.filter { identifier($0) != nil && saved($0) == nil }) }.disabled(blocked)
                Button("Скачать в очередь · \(selected.count)") { startDownloads() }.buttonStyle(.borderedProminent).disabled(selected.isEmpty || blocked)
                Button("К установке · \(savedVisibleIDs.count) сохранённых") {
                    shelf.selected = savedVisibleIDs
                    let suffix = search.trimmingCharacters(in: .whitespacesAndNewlines)
                    shelf.savePreset("С iPhone · " + device.phone.name + (suffix.isEmpty ? "" : " · " + suffix))
                    shelf.historyShown = false
                }.disabled(blocked || savedVisibleIDs.isEmpty)
            }
            Text("Удаление из магазина не означает отсутствие лицензии. Возможность загрузки проверяется самой загрузкой; AppDock не выдаёт новую лицензию автоматически.").font(.caption).foregroundStyle(.secondary)
        }
        .sheet(isPresented: $loginShown, onDismiss: {
            if model.authState != "done" { pendingDownloads = []; pendingAccount = "" }
        }) { AccountLoginView(model: model, suggestedEmail: model.selectedEmail) }
        .onChange(of: model.working) { _, working in
            guard !working, !pendingDownloads.isEmpty, model.selectedIsActive,
                  pendingAccount.isEmpty || model.active?.email.lowercased() == pendingAccount.lowercased() else { return }
            let ids = pendingDownloads; pendingDownloads = []; pendingAccount = ""; enqueue(ids)
        }
    }
}
