import SwiftUI
import AppKit

struct PhonePreview: View {
    let device: RememberedDevice?
    var body: some View {
        VStack(spacing: 6) {
            ZStack(alignment: .top) {
                RoundedRectangle(cornerRadius: 25).fill(Color.black).frame(width: 110, height: 218)
                    .overlay(RoundedRectangle(cornerRadius: 25).stroke(Color.gray.opacity(0.65), lineWidth: 2))
                Group {
                    if let path = device?.imagePath, let image = NSImage(contentsOfFile: path) {
                        Image(nsImage: image).resizable().scaledToFill()
                    } else {
                        LinearGradient(colors: [.indigo, .purple, .blue.opacity(0.7)], startPoint: .topTrailing, endPoint: .bottomLeading)
                            .overlay(Image(systemName: "iphone").font(.system(size: 38, weight: .ultraLight)).foregroundStyle(.white.opacity(0.65)))
                    }
                }.frame(width: 98, height: 204).clipShape(RoundedRectangle(cornerRadius: 20)).padding(.top, 7)
                Capsule().fill(Color.black).frame(width: 36, height: 11).padding(.top, 13)
            }
            Text(device?.imageKind ?? "Иллюстрация · не обои устройства").font(.caption2).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }.frame(maxWidth: .infinity)
    }
}
struct DeviceHistoryView: View {
    @ObservedObject var shelf: Shelf
    @Environment(\.dismiss) private var dismiss
    @State private var page = "Приложения"
    @State private var search = ""
    @State private var forgetShown = false
    var device: RememberedDevice? { shelf.book.devices.first { $0.id == shelf.historyDeviceID } }
    var connected: Bool { shelf.phones.contains { $0.id == shelf.historyDeviceID } }
    var events: [InstallationEvent] { shelf.book.events.filter { $0.deviceID == shelf.historyDeviceID }.sorted { $0.date > $1.date } }
    var appBundles: [String] {
        (device?.versions.keys.map { $0 } ?? []).filter { search.isEmpty || (($0 + " " + (device?.appNames[$0] ?? "")).localizedCaseInsensitiveContains(search)) }.sorted {
            (device?.appNames[$0] ?? $0).localizedStandardCompare(device?.appNames[$1] ?? $1) == .orderedAscending
        }
    }
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Label("Устройства и история", systemImage: "iphone.gen3").font(.title2.bold())
                Spacer()
                Button("Импорт отчёта iMazing…") { shelf.importDeviceReport() }.disabled(shelf.busy)
                Button("Готово") { dismiss() }.keyboardShortcut(.cancelAction)
            }.padding(22)
            Divider()
            HStack(spacing: 0) {
                List(selection: $shelf.historyDeviceID) {
                    ForEach(shelf.book.devices.sorted { $0.phone.name < $1.phone.name }) { record in
                        VStack(alignment: .leading, spacing: 5) {
                            Text(record.phone.name).font(.headline)
                            Text(record.phone.displayModel).font(.caption).foregroundStyle(.secondary)
                            Label(shelf.phones.contains { $0.id == record.id } ? "Подключено" : "Не подключено", systemImage: shelf.phones.contains { $0.id == record.id } ? "cable.connector" : "clock").font(.caption2).foregroundStyle(.secondary)
                        }.padding(.vertical, 6).tag(record.id)
                    }
                }.listStyle(.sidebar).frame(width: 215)
                Divider()
                if let device {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 16) {
                            HStack(alignment: .top, spacing: 22) {
                                VStack(spacing: 10) {
                                    PhonePreview(device: device)
                                    Button("Выбрать картинку…") { shelf.chooseDeviceImage(device.id) }.disabled(shelf.busy)
                                    Button("Снимок по USB") { shelf.captureDeviceImage(device.id) }.disabled(!connected || shelf.busy)
                                }.frame(width: 185)
                                VStack(alignment: .leading, spacing: 9) {
                                    Text(device.phone.name).font(.title.bold())
                                    Text(device.phone.displayModel).font(.title3)
                                    Text("iOS \(device.phone.ios)").foregroundStyle(.secondary)
                                    if !device.phone.modelNumber.isEmpty { Text("Номер модели: \(device.phone.modelNumber)") }
                                    if !device.phone.regulatoryModel.isEmpty { Text("Модель Apple: \(device.phone.regulatoryModel)") }
                                    Text("Серийный номер: \(device.phone.serial.isEmpty ? "—" : device.phone.serial)").textSelection(.enabled)
                                    Text("ProductType: \(device.phone.model)").font(.caption).foregroundStyle(.secondary)
                                    Text("UDID: \(device.id)").font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                                    if let date = device.lastConnected { Text("Последнее подключение: \(date.formatted(date: .abbreviated, time: .shortened))").font(.caption).foregroundStyle(.secondary) }
                                    Text("Источник: \(device.source)").font(.caption).foregroundStyle(.secondary)
                                    Button("Забыть устройство…", role: .destructive) { forgetShown = true }.disabled(shelf.busy || shelf.refreshing || !shelf.pendingTasks.isEmpty)
                                }
                            }
                            Divider()
                            Picker("Раздел", selection: $page) { Text("Приложения").tag("Приложения"); Text("История установок").tag("История"); Text("Сохранить с iPhone").tag("Сохранить") }.pickerStyle(.segmented)
                            if page == "Сохранить" {
                                DeviceSaveView(shelf: shelf, model: shelf.accounts, device: device)
                            } else if page == "Приложения" {
                                if let checked = device.inventoryChecked {
                                    Text("Список прочитан с iPhone: \(checked.formatted(date: .abbreviated, time: .shortened)). После отключения это сохранённый снимок, а не текущая проверка.").font(.caption).foregroundStyle(.secondary)
                                    TextField("Поиск по приложениям", text: $search).textFieldStyle(.roundedBorder)
                                    ForEach(appBundles, id: \.self) { bundle in
                                        HStack {
                                            VStack(alignment: .leading, spacing: 3) { Text(device.appNames[bundle] ?? bundle); Text(bundle).font(.caption).foregroundStyle(.secondary) }
                                            Spacer(); Text("v" + (device.versions[bundle] ?? ""))
                                        }.padding(10).background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 10))
                                    }
                                } else {
                                    ContentUnavailableView("Список ещё не получен", systemImage: "apps.iphone", description: Text("Подключите этот iPhone и выберите его в главном окне. В текстовом отчёте нет списка установленных приложений."))
                                }
                            } else {
                                Text("История действий AppDock. Установки через другие программы сюда не добавляются задним числом.").font(.caption).foregroundStyle(.secondary)
                                ForEach(events) { event in
                                    VStack(alignment: .leading, spacing: 7) {
                                        HStack {
                                            Image(systemName: event.outcome == "Установлено" ? "checkmark.circle.fill" : event.outcome == "Ошибка" ? "xmark.circle.fill" : "clock").foregroundStyle(event.outcome == "Ошибка" ? .red : .indigo)
                                            Text(event.appName).font(.headline); Spacer(); Text(event.outcome).font(.caption.bold())
                                        }
                                        Text("\(event.previousVersion.map { "v\($0) → " } ?? "")v\(event.requestedVersion) · \(event.date.formatted(date: .abbreviated, time: .shortened))").font(.caption).foregroundStyle(.secondary)
                                        Text(event.detail).font(.caption).textSelection(.enabled)
                                        if let result = event.resultVersion { Text("Подтверждено на устройстве: v\(result)").font(.caption).foregroundStyle(.secondary) }
                                    }.padding(14).background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 12))
                                }
                                if events.isEmpty { ContentUnavailableView("История пока пуста", systemImage: "clock.arrow.circlepath", description: Text("Здесь появятся установки, пропуски и ошибки для этого iPhone.")) }
                            }
                        }.padding(24).id(device.id + page)
                    }
                } else {
                    ContentUnavailableView("Выберите устройство", systemImage: "iphone", description: Text("Подключите iPhone или импортируйте текстовый отчёт iMazing.")).frame(maxWidth: .infinity)
                }
            }
        }.frame(width: 960, height: 720)
            .confirmationDialog("Забыть выбранное устройство?", isPresented: $forgetShown, titleVisibility: .visible) {
                Button("Удалить карточку и историю", role: .destructive) { if let device { shelf.forgetDevice(device.id) } }
            } message: { Text("Сохранённая карточка и история установок будут удалены из AppDock. Приложения на iPhone и IPA в библиотеке останутся. Подключённое устройство снова появится после сканирования.") }
            .onAppear { if device == nil { shelf.historyDeviceID = shelf.book.devices.first?.id ?? "" } }
    }
}
struct QueueView: View {
    @ObservedObject var shelf: Shelf
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack { Label("Очередь задач", systemImage: "list.bullet.clipboard").font(.title2.bold()); Spacer(); Button("Готово") { dismiss() }.keyboardShortcut(.cancelAction) }
            Text("У каждой установки закреплено устройство. Пауза действует после текущей задачи. Очередь хранится в текущем сеансе приложения.").font(.caption).foregroundStyle(.secondary)

            if let current = shelf.currentTask {
                VStack(alignment: .leading, spacing: 6) {
                    Label(current.title, systemImage: "play.circle.fill").font(.headline)
                    if let account = current.appleAccount { Text("Apple ID: " + account).font(.caption).textSelection(.enabled) }
                    if let phone = current.phone { Text(phone.name + " · " + phone.displayModel).font(.caption).foregroundStyle(.secondary) }
                    Text(shelf.headline).font(.caption)
                    if current.kind == .download {
                        if let progress = shelf.downloadProgress { ProgressView(value: progress); Text("\(Int(progress * 100))%").font(.caption.monospacedDigit()) }
                        else { ProgressView().controlSize(.small); Text("Ожидание данных о размере загрузки").font(.caption2).foregroundStyle(.secondary) }
                    }
                    if current.kind == .install { Button("Остановить после текущего приложения") { shelf.cancelRequested = true; shelf.queuePaused = true } }
                }.padding(16).frame(maxWidth: .infinity, alignment: .leading).background(Color.indigo.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
            }
            HStack {
                Text("Ожидают: \(shelf.pendingTasks.count)").font(.headline)
                Spacer()
                Button(shelf.queuePaused ? "Продолжить" : "Пауза") { shelf.queuePaused.toggle(); if !shelf.queuePaused { shelf.startNextTask() } }
            }
            ScrollView {
                VStack(spacing: 10) {
                    ForEach(Array(shelf.pendingTasks.enumerated()), id: \.element.id) { index, task in
                        HStack(spacing: 12) {
                            Text("\(index + 1)").font(.headline).foregroundStyle(.secondary).frame(width: 25)
                            VStack(alignment: .leading, spacing: 5) {
                                Text(task.title).font(.headline)
                                if let account = task.appleAccount { Text("Apple ID: " + account).font(.caption2) }
                                if let phone = task.phone { Text(phone.name + " · " + phone.displayModel).font(.caption).foregroundStyle(.secondary) }
                                if task.kind == .download { Text("Категория: " + task.category).font(.caption).foregroundStyle(.secondary) }
                                if task.kind == .install || task.kind == .cache { Text(task.apps.map(\.title).joined(separator: ", ")).font(.caption).foregroundStyle(.secondary).lineLimit(2) }
                            }
                            Spacer()
                            Button { if index > 0 { shelf.pendingTasks.swapAt(index, index - 1) } } label: { Image(systemName: "arrow.up") }.disabled(index == 0).help("Раньше в очереди")
                            Button { if index + 1 < shelf.pendingTasks.count { shelf.pendingTasks.swapAt(index, index + 1) } } label: { Image(systemName: "arrow.down") }.disabled(index + 1 == shelf.pendingTasks.count).help("Позже в очереди")
                            Button { shelf.pendingTasks.removeAll { $0.id == task.id } } label: { Image(systemName: "xmark") }.help("Убрать задачу")
                        }.padding(14).background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 12))
                    }
                    if shelf.pendingTasks.isEmpty { ContentUnavailableView("Нет ожидающих задач", systemImage: "checklist", description: Text("Выберите приложения или набор, затем добавьте установку в очередь. Скачивания тоже выполняются последовательно.")) }
                }
            }
        }.padding(24).frame(width: 720, height: 580)
    }
}

struct DownloadsCatalogView: View {
    @ObservedObject var shelf: Shelf
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""
    var rows: [IPAItem] { shelf.downloadHistory.filter { search.isEmpty || "\($0.family) \($0.title) \($0.idNumber ?? 0) \($0.bundle ?? "")".localizedCaseInsensitiveContains(search) }.sorted { $0.family.localizedStandardCompare($1.family) == .orderedAscending } }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack { Text("Каталог скачиваний").font(.title2.bold()); Spacer(); Button("Готово") { dismiss() }.keyboardShortcut(.cancelAction) }
            Text("Автоматически собирается из архива. Сохраняет ID и версии после замены IPA. App Store выдаёт доступную ему версию; выбрать старую версию по этому списку нельзя.").font(.caption).foregroundStyle(.secondary)
            TextField("Название, банк, Bundle ID или App Store ID", text: $search).textFieldStyle(.roundedBorder)
            ScrollView {
                LazyVStack(spacing: 10) {
                    ForEach(rows, id: \.sha256) { item in
                        let saved = shelf.items.first { $0.idNumber == item.idNumber && $0.version == item.version && $0.sha256 == item.sha256 && ((try? $0.file(in: shelf.sourceRoot($0))) != nil || shelf.cachedIDs.contains($0.id)) }
                        let queued = shelf.currentTask?.appID == item.idNumber || shelf.pendingTasks.contains { $0.appID == item.idNumber }
                        HStack {
                            VStack(alignment: .leading, spacing: 5) {
                                Text(item.family).font(.headline)
                                Text("\(item.title) · v\(item.version ?? "—")").font(.callout)
                                Text("ID \(item.idNumber.map(String.init) ?? "—") · \(item.bundle ?? "—")").font(.caption).textSelection(.enabled)
                            }
                            Spacer()
                            if saved != nil { Label("IPA есть", systemImage: "checkmark.circle").font(.caption) }
                            Button(saved != nil ? "Скачать повторно" : "Скачать IPA") {
                                shelf.download(id: item.idNumber ?? 0, category: item.category, replacing: saved, localOnly: !shelf.rootAvailable || saved?.localOnly == true)
                            }.disabled(item.idNumber == nil || queued)
                            if queued { Text("В очереди").font(.caption) }
                        }.foregroundStyle(saved != nil ? Color.secondary : Color.primary).padding(14)
                            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
                    }
                }
            }
            HStack { Text("Версий в каталоге: \(shelf.downloadHistory.count)").font(.caption).foregroundStyle(.secondary); Spacer(); Button("Открыть очередь · \(shelf.pendingTasks.count)") { shelf.queueShown = true; dismiss() } }
        }.padding(24).frame(width: 850, height: 650)
    }
}

struct StorageView: View {
    @ObservedObject var shelf: Shelf
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack { Label("Хранилище AppDock", systemImage: "externaldrive").font(.title2.bold()); Spacer(); Button("Готово") { dismiss() } }
            Picker("Режим", selection: $shelf.storageMode) { Text("Local").tag("Local"); Text("NAS").tag("NAS") }
                .pickerStyle(.segmented).disabled(shelf.busy || !shelf.pendingTasks.isEmpty)
                .onChange(of: shelf.storageMode) { old, _ in shelf.applyStorageMode(previous: old) }
            Text(shelf.root.path).textSelection(.enabled)
            Label(shelf.rootAvailable ? "Библиотека подключена" : "Библиотека недоступна", systemImage: shelf.rootAvailable ? "checkmark.circle" : "wifi.slash")
            HStack { Button("Выбрать папку…") { shelf.chooseFolder() }; Button("Обновить") { shelf.load() } }.disabled(shelf.busy || !shelf.pendingTasks.isEmpty)
            Text("Для NAS подключите SMB через Finder и выберите сетевую папку. ipatool всегда работает на этом Mac. Новая папка создаёт пустой каталог; старый архив автоматически не переносится.").font(.caption).foregroundStyle(.secondary)
            Divider()
            Text("Локальные копии: \(shelf.cachedIDs.count) из \(shelf.items.count) IPA").font(.headline)
            Text("Перед установкой IPA копируется на Mac и проверяется по SHA-256. Сохранённые копии доступны при отключённом NAS.").font(.caption)
            HStack { Button("Сохранить выбранные на Mac") { shelf.cache(shelf.chosen) }; Button("Экспорт в папку…") { shelf.chooseExport(shelf.chosen) } }.disabled(shelf.chosen.isEmpty)
            Button("Сохранить всю библиотеку на Mac") { shelf.cache(shelf.items) }.disabled(shelf.items.isEmpty)
            Spacer()
        }.padding(28).frame(width: 660, height: 480)
    }
}

struct AboutAppDockView: View {
    @Environment(\.dismiss) private var dismiss
    private let github = URL(string: "https://github.com/x0rif0r/AppDock")!
    private var version: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—" }
    private var build: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—" }
    private let tools: [(String, String, String, String)] = [
        ("ipatool", "MIT", "Majd Alfhaily и участники · скачивание из App Store", "https://github.com/majd/ipatool"),
        ("libimobiledevice", "LGPL-2.1-or-later", "Команда libimobiledevice · связь с устройствами по USB", "https://github.com/libimobiledevice/libimobiledevice"),
        ("ideviceinstaller", "GPL-2.0-or-later", "Команда libimobiledevice · установка приложений", "https://github.com/libimobiledevice/ideviceinstaller"),
        ("DeviceKit", "MIT", "Dennis Weissmann и участники · справочник моделей", "https://github.com/devicekit/DeviceKit")
    ]
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 16) {
                Image(systemName: "square.stack.3d.up.fill").font(.system(size: 40)).foregroundStyle(.indigo)
                VStack(alignment: .leading, spacing: 5) {
                    Text("AppDock").font(.largeTitle.bold())
                    Text("Версия \(version) · сборка \(build)").font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Готово") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            Text("Ваши приложения. Ваша библиотека. Ваши устройства.").font(.headline)
            HStack {
                Label("Автор: x0rif0r", systemImage: "person.crop.circle")
                Spacer()
                Link("GitHub ↗", destination: github)
                Link("Сообщить об ошибке ↗", destination: github.appendingPathComponent("issues"))
            }.font(.callout)
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Открытый исходный код · MIT").font(.headline)
                        Text("© 2026 x0rif0r. Собственный код AppDock можно использовать и изменять с сохранением авторства и текста лицензии.").font(.callout).foregroundStyle(.secondary)
                        Button("Прочитать лицензию AppDock") { if let url = Bundle.main.url(forResource: "LICENSE", withExtension: nil) { NSWorkspace.shared.open(url) } }
                    }.padding(16).frame(maxWidth: .infinity, alignment: .leading).background(.quaternary, in: RoundedRectangle(cornerRadius: 14))
                    Text("Сторонние проекты").font(.headline).padding(.top, 4)
                    ForEach(tools, id: \.0) { tool in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack { Text(tool.0).font(.headline); Spacer(); Text(tool.1).font(.caption.monospaced()).foregroundStyle(.secondary) }
                            Text(tool.2).font(.caption).foregroundStyle(.secondary)
                            Link("Исходный проект ↗", destination: URL(string: tool.3)!).font(.caption)
                        }.padding(14).frame(maxWidth: .infinity, alignment: .leading).background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
                    }
                    Text("Внешние CLI устанавливаются отдельно. Их бинарные файлы не входят в AppDock. Иконки и приложения принадлежат своим правообладателям; лицензия MIT не передаёт права на IPA и лицензии Apple ID.").font(.caption).foregroundStyle(.secondary)
                }
            }
            HStack {
                Button("Все тексты лицензий") { if let url = Bundle.main.resourceURL?.appendingPathComponent("Licenses") { NSWorkspace.shared.activateFileViewerSelecting([url]) } }
                Spacer()
                Text("Apple Silicon · macOS 14+").font(.caption).foregroundStyle(.secondary)
            }
        }.padding(28).frame(width: 720, height: 710)
    }
}
