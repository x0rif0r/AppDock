import Foundation
import AppKit

struct StorePresentation: Codable, Sendable {
    let title: String
    let iconPath: String?
    let source: String
    var firstRelease: String? = nil
    var build: String? = nil
    var metadataRead: Bool? = nil
}
enum LibraryArt {
    static func key(_ item: IPAItem) -> String { (item.bundle ?? String(item.idNumber ?? 0)).filter { $0.isLetter || $0.isNumber || $0 == "." } + "-" + String((item.sha256 ?? "unknown").prefix(12)) }
    static func cached(items: [IPAItem], folder: URL) -> [String: StorePresentation] {
        var output: [String: StorePresentation] = [:]
        for item in items {
            if let data = try? Data(contentsOf: folder.appendingPathComponent("AppArtwork/" + key(item) + ".json")), let value = try? JSONDecoder().decode(StorePresentation.self, from: data) { output[item.id] = value }
        }
        return output
    }
    static func resolve(_ item: IPAItem, root: URL, folder: URL, fileOverride: URL? = nil) -> StorePresentation? {
        let dir = folder.appendingPathComponent("AppArtwork")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let record = dir.appendingPathComponent(key(item) + ".json")
        if let data = try? Data(contentsOf: record), let cached = try? JSONDecoder().decode(StorePresentation.self, from: data), cached.metadataRead == true, cached.iconPath.flatMap({ NSImage(contentsOfFile: $0) }) != nil { return cached }
        var firstRelease: String?
        var build: String?
        var title = item.title
        var icon: URL?
        var source = "Название из IPA"
        // The embedded icon is tied to the saved version, including removed applications.
        if let ipa = fileOverride ?? (try? item.file(in: root)), let listing = try? DeviceTools.run(URL(fileURLWithPath: "/usr/bin/unzip"), ["-Z", "-1", ipa.path]) {
            let files = listing.output.split(whereSeparator: \.isNewline).map(String.init)
            if let plistPath = files.first(where: { $0.hasPrefix("Payload/") && $0.hasSuffix(".app/Info.plist") && $0.components(separatedBy: "/").count == 3 }),
               let plist = try? DeviceTools.run(URL(fileURLWithPath: "/usr/bin/unzip"), ["-p", ipa.path, "Payload/*.app/Info.plist", "-x", "Payload/*/*/Info.plist"]),
               let info = (try? PropertyListSerialization.propertyList(from: plist.data, format: nil)) as? [String: Any] {
                build = info["CFBundleVersion"] as? String
                if let metadata = try? DeviceTools.run(URL(fileURLWithPath: "/usr/bin/unzip"), ["-p", ipa.path, "iTunesMetadata.plist"]), let store = (try? PropertyListSerialization.propertyList(from: metadata.data, format: nil)) as? [String: Any] {
                    firstRelease = store["releaseDate"] as? String
                }
                let prefix = String(plistPath.dropLast("Info.plist".count))
                let icons = info["CFBundleIcons"] as? [String: Any]
                let primary = icons?["CFBundlePrimaryIcon"] as? [String: Any]
                let names = (primary?["CFBundleIconFiles"] as? [String]) ?? (info["CFBundleIconFiles"] as? [String]) ?? []
                let candidates = files.filter { path in
                    guard path.hasPrefix(prefix), path.components(separatedBy: "/").count == 3, path.lowercased().hasSuffix(".png") else { return false }
                    let filename = URL(fileURLWithPath: path).lastPathComponent
                    return names.contains { filename.hasPrefix($0) } || filename.hasPrefix("AppIcon") || filename.lowercased().hasPrefix("icon")
                }.sorted { lhs, rhs in
                    func score(_ path: String) -> Int { (path.contains("@3x") ? 100 : path.contains("@2x") ? 50 : 0) + (path.contains("60x60") ? 20 : path.contains("76x76") ? 10 : 0) }
                    return score(lhs) > score(rhs)
                }
                for candidate in candidates {
                    guard let bytes = try? DeviceTools.run(URL(fileURLWithPath: "/usr/bin/unzip"), ["-p", ipa.path, "Payload/*.app/" + URL(fileURLWithPath: candidate).lastPathComponent, "-x", "Payload/*/*/" + URL(fileURLWithPath: candidate).lastPathComponent]), bytes.status == 0, NSImage(data: bytes.data) != nil else { continue }
                    let output = dir.appendingPathComponent(key(item) + ".png")
                    if (try? bytes.data.write(to: output, options: .atomic)) != nil { icon = output; source = "Иконка и название из IPA"; break }
                }
            }
        }
        if icon == nil, let id = item.idNumber {
            for country in ["ru", "tr", "us"] {
                guard let url = URL(string: "https://itunes.apple.com/lookup?id=\(id)&country=\(country)"),
                      let data = fetch(url), let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                      let rows = json["results"] as? [[String: Any]],
                      let row = rows.first(where: { ($0["trackId"] as? NSNumber)?.intValue == id && $0["bundleId"] as? String == item.bundle }) else { continue }
                title = row["trackName"] as? String ?? title
                if let artwork = row["artworkUrl512"] as? String ?? row["artworkUrl100"] as? String,
                   let url = URL(string: artwork), url.scheme == "https", let host = url.host, host == "mzstatic.com" || host.hasSuffix(".mzstatic.com"),
                   let bytes = fetch(url), NSImage(data: bytes) != nil {
                    let output = dir.appendingPathComponent(key(item) + ".store-image")
                    if (try? bytes.write(to: output, options: .atomic)) != nil { icon = output }
                }
                source = "Каталог Apple (\(country.uppercased()))"; break
            }
        }
        let value = StorePresentation(title: title, iconPath: icon?.path, source: source, firstRelease: firstRelease, build: build, metadataRead: true)
        if let data = try? JSONEncoder().encode(value) { try? data.write(to: record, options: .atomic) }
        return value
    }

    private static func fetch(_ url: URL) -> Data? {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 8
        configuration.timeoutIntervalForResource = 12
        let session = URLSession(configuration: configuration)
        let semaphore = DispatchSemaphore(value: 0)
        let box = DataBox()
        let task = session.dataTask(with: url) { data, response, _ in
            if let http = response as? HTTPURLResponse, http.statusCode == 200, let data, data.count < 8_000_000 { box.data = data }
            semaphore.signal()
        }
        task.resume()
        let completed = semaphore.wait(timeout: .now() + 13) == .success
        if !completed { task.cancel() }
        session.invalidateAndCancel()
        return completed ? box.data : nil
    }
    private final class DataBox: @unchecked Sendable { var data: Data? }
}

struct QueuedTask: Identifiable {
    enum Kind { case install, download, cache }
    var id = UUID().uuidString
    let kind: Kind
    let title: String
    var apps: [IPAItem] = []
    var phone: Phone?
    var appID: Int?
    var category = "Другие"
    var replacing: IPAItem?
    var localOnly = false
    var appleAccount: String? = nil
    var exportDirectory: URL?
}

struct DownloadRequest: Identifiable { var id = UUID().uuidString; var replacing: IPAItem? }
