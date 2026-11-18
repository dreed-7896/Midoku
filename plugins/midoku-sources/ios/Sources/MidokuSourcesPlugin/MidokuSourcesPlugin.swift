import AidokuRunner
import Capacitor
import Foundation
import UIKit
import ZIPFoundation

/// On-device Aidoku extensions for Midoku Web. The web app calls these through `registerPlugin('MidokuSources')`
/// (src/data/device.ts). Models cross the bridge as AidokuRunner's own Codable JSON, so a manga or chapter the web
/// got from here can be handed straight back.
@objc(MidokuSourcesPlugin)
public class MidokuSourcesPlugin: CAPPlugin, CAPBridgedPlugin {
    public let identifier = "MidokuSourcesPlugin"
    public let jsName = "MidokuSources"
    public let pluginMethods: [CAPPluginMethod] = [
        CAPPluginMethod(name: "fetchText", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "installed", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "install", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "uninstall", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "search", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "listing", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "manga", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "pages", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "image", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "settings", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "setSetting", returnType: CAPPluginReturnPromise)
    ]

    private let store = SourceStore()

    // MARK: Repos and installs

    /// GET a URL natively (no CORS), e.g. a source list's index.
    @objc func fetchText(_ call: CAPPluginCall) {
        guard let url = call.getString("url").flatMap(URL.init(string:)) else { return call.reject("Missing url") }
        run(call) {
            let (data, response) = try await URLSession.shared.data(for: await SourceStore.prepared(URLRequest(url: url)))
            let code = (response as? HTTPURLResponse)?.statusCode ?? 200
            return ["status": code, "text": String(decoding: data, as: UTF8.self)]
        }
    }

    @objc func installed(_ call: CAPPluginCall) {
        run(call) { [store] in
            var list: [JSObject] = []
            for source in await store.all() { list.append(try await Self.info(source)) }
            return ["sources": list]
        }
    }

    /// Download an .aix package, load it and keep it under Application Support.
    @objc func install(_ call: CAPPluginCall) {
        guard let url = call.getString("url").flatMap(URL.init(string:)) else { return call.reject("Missing url") }
        run(call) { [store] in
            let source = try await store.install(from: url)
            return try await Self.info(source)
        }
    }

    @objc func uninstall(_ call: CAPPluginCall) {
        guard let key = call.getString("key") else { return call.reject("Missing key") }
        run(call) { [store] in
            await store.uninstall(key: key)
            return [:]
        }
    }

    // MARK: Browsing

    @objc func search(_ call: CAPPluginCall) {
        guard let key = call.getString("key") else { return call.reject("Missing key") }
        let query = call.getString("query")
        let page = call.getInt("page") ?? 1
        let filters: [FilterValue] = (try? Self.decode([FilterValue].self, call.getArray("filters") ?? [])) ?? []
        run(call) { [store] in
            let source = try await store.source(key)
            let result = try await source.getSearchMangaList(query: query, page: page, filters: filters)
            return try Self.object(result)
        }
    }

    @objc func listing(_ call: CAPPluginCall) {
        guard let key = call.getString("key"), let id = call.getString("id") else { return call.reject("Missing key or id") }
        let page = call.getInt("page") ?? 1
        run(call) { [store] in
            let source = try await store.source(key)
            let listing = try await source.getListings().first { $0.id == id } ?? Listing(id: id, name: id)
            let result = try await source.getMangaList(listing: listing, page: page)
            return try Self.object(result)
        }
    }

    /// Details and/or chapters for a manga (pass back the manga object from search or listing).
    @objc func manga(_ call: CAPPluginCall) {
        guard let key = call.getString("key"), let raw = call.getObject("manga") else { return call.reject("Missing key or manga") }
        let details = call.getBool("details") ?? true
        let chapters = call.getBool("chapters") ?? true
        run(call) { [store] in
            let source = try await store.source(key)
            let manga = try Self.decode(Manga.self, raw)
            let result = try await source.getMangaUpdate(manga: manga, needsDetails: details, needsChapters: chapters)
            return try Self.object(result)
        }
    }

    @objc func pages(_ call: CAPPluginCall) {
        guard let key = call.getString("key"), let rawManga = call.getObject("manga"), let rawChapter = call.getObject("chapter") else {
            return call.reject("Missing key, manga or chapter")
        }
        run(call) { [store] in
            let source = try await store.source(key)
            let manga = try Self.decode(Manga.self, rawManga)
            let chapter = try Self.decode(Chapter.self, rawChapter)
            let pages = try await source.getPageList(manga: manga, chapter: chapter)
            let list: [JSObject] = pages.map { page in
                switch page.content {
                    case let .url(url, context):
                        var object: JSObject = ["type": "url", "url": url.absoluteString]
                        if let context { object["context"] = context as JSObject }
                        return object
                    case let .text(text):
                        return ["type": "text", "text": text]
                    case let .image(image):
                        return ["type": "image", "data": image.jpegData(compressionQuality: 0.92)?.base64EncodedString() ?? "", "mime": "image/jpeg"]
                    case .zipFile:
                        return ["type": "unsupported"]
                }
            }
            return ["pages": list]
        }
    }

    /// A page or cover image with the source's own request headers and descrambling, as base64.
    @objc func image(_ call: CAPPluginCall) {
        guard let key = call.getString("key"), let urlString = call.getString("url"), let url = URL(string: urlString) else {
            return call.reject("Missing key or url")
        }
        let context = call.getObject("context") as? [String: String]
        let cover = call.getBool("cover") ?? false
        run(call) { [store] in
            let source = try await store.source(key)
            var request = (try? await source.getImageRequest(url: urlString, context: context)) ?? URLRequest(url: url)
            request = await SourceStore.prepared(request)
            let (data, response) = try await URLSession.shared.data(for: request)
            let http = response as? HTTPURLResponse
            let processes = cover ? source.features.processesCovers : source.features.processesPages
            if processes, let image = UIImage(data: data) {
                let ref = try await source.store(value: image)
                let wrapped = Response(
                    code: http?.statusCode ?? 200,
                    headers: Self.stringMap(http?.allHeaderFields ?? [:]),
                    request: Request(url: request.url, headers: request.allHTTPHeaderFields ?? [:]),
                    image: ref
                )
                let result = cover
                    ? try await source.processCoverImage(response: wrapped)
                    : try await source.processPageImage(response: wrapped, context: context)
                try? await source.remove(value: ref)
                if let result, let png = result.pngData() {
                    return ["data": png.base64EncodedString(), "mime": "image/png"]
                }
            }
            return ["data": data.base64EncodedString(), "mime": http?.mimeType ?? "image/jpeg", "status": http?.statusCode ?? 200]
        }
    }

    // MARK: Settings

    @objc func settings(_ call: CAPPluginCall) {
        guard let key = call.getString("key") else { return call.reject("Missing key") }
        run(call) { [store] in
            let source = try await store.source(key)
            let settings = try await source.getSettings()
            var values: JSObject = [:]
            for (name, value) in UserDefaults.standard.dictionaryRepresentation() where name.hasPrefix("\(key).") {
                if let json = Self.jsValue(value) { values[String(name.dropFirst(key.count + 1))] = json }
            }
            return ["settings": try Self.json(settings), "values": values]
        }
    }

    @objc func setSetting(_ call: CAPPluginCall) {
        guard let key = call.getString("key"), let name = call.getString("name") else { return call.reject("Missing key or name") }
        let value = call.options["value"]
        UserDefaults.standard.set(value is NSNull ? nil : value, forKey: "\(key).\(name)")
        Task { [store] in
            if let source = try? await store.source(key) {
                try? await source.runner.handleNotification(notification: name)
            }
        }
        call.resolve()
    }

    // MARK: Helpers

    private func run(_ call: CAPPluginCall, _ work: @escaping @Sendable () async throws -> JSObject) {
        nonisolated(unsafe) let call = call
        Task {
            do {
                call.resolve(try await work())
            } catch {
                call.reject(Self.describe(error), nil, error)
            }
        }
    }

    private static func describe(_ error: Error) -> String {
        if let error = error as? SourceError {
            switch error {
                case .unimplemented: return "This source doesn't support that."
                case let .message(message): return message
                default: return "Source error: \(error)"
            }
        }
        return error.localizedDescription
    }

    private static func info(_ source: AidokuRunner.Source) async throws -> JSObject {
        var object: JSObject = [
            "key": source.key,
            "name": source.name,
            "version": source.version,
            "languages": source.languages as JSArray,
            "urls": source.urls.map(\.absoluteString) as JSArray,
            "contentRating": source.contentRating.rawValue,
            "onlySearch": source.onlySearch,
            "providesListings": source.features.providesListings,
            "providesHome": source.features.providesHome
        ]
        if let icon = source.imageUrl, let data = try? Data(contentsOf: icon) {
            object["icon"] = "data:image/png;base64," + data.base64EncodedString()
        }
        object["listings"] = (try? json(try await source.getListings())) ?? JSArray()
        object["filters"] = (try? json(try await source.getSearchFilters())) ?? JSArray()
        return object
    }

    private static func stringMap(_ dict: [AnyHashable: Any]) -> [String: String] {
        var result: [String: String] = [:]
        for (key, value) in dict { if let key = key as? String, let value = value as? String { result[key] = value } }
        return result
    }

    private static func json<T: Encodable>(_ value: T) throws -> JSValue {
        let data = try JSONEncoder().encode(value)
        let object = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        guard let js = jsValue(object) else { throw CocoaError(.coderInvalidValue) }
        return js
    }

    private static func object<T: Encodable>(_ value: T) throws -> JSObject {
        guard let object = try json(value) as? JSObject else { throw CocoaError(.coderInvalidValue) }
        return object
    }

    private static func decode<T: Decodable>(_ type: T.Type, _ value: Any) throws -> T {
        let data = try JSONSerialization.data(withJSONObject: value, options: [.fragmentsAllowed])
        return try JSONDecoder().decode(type, from: data)
    }

    /// Foundation JSON / plist values to Capacitor's JSValue.
    private static func jsValue(_ value: Any) -> JSValue? {
        switch value {
            case let value as NSNumber:
                if CFGetTypeID(value) == CFBooleanGetTypeID() { return value.boolValue }
                return value.doubleValue
            case let value as String: return value
            case let value as [Any]: return value.compactMap(jsValue) as JSArray
            case let value as [String: Any]:
                var object: JSObject = [:]
                for (key, item) in value { if let js = jsValue(item) { object[key] = js } }
                return object
            case let value as Date: return value.timeIntervalSince1970
            case is NSNull: return NSNull()
            default: return nil
        }
    }
}

/// Installed sources, loaded lazily from Application Support/MidokuSources/<key>.
actor SourceStore {
    private var sources: [String: AidokuRunner.Source] = [:]
    private var loaded = false

    static let directory: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let url = base.appendingPathComponent("MidokuSources", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()

    static let userAgent =
        "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1"

    /// Adds a browser user agent and stored cookies (from Cloudflare checks) when the source didn't set them.
    static func prepared(_ original: URLRequest) async -> URLRequest {
        var request = original
        if request.value(forHTTPHeaderField: "User-Agent") == nil {
            request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        }
        if let url = request.url, let cookies = HTTPCookieStorage.shared.cookies(for: url), !cookies.isEmpty {
            for (name, value) in HTTPCookie.requestHeaderFields(with: cookies) {
                if name == "Cookie", let existing = request.value(forHTTPHeaderField: "Cookie") {
                    request.setValue(value + "; " + existing, forHTTPHeaderField: name)
                } else {
                    request.setValue(value, forHTTPHeaderField: name)
                }
            }
        }
        return request
    }

    private static func config(for key: String) -> InterpreterConfiguration {
        InterpreterConfiguration(
            printHandler: { print("[\(key)] \($0)") },
            requestHandler: { request in
                try await URLSession.shared.data(for: await SourceStore.prepared(request))
            }
        )
    }

    private func loadAll() async {
        guard !loaded else { return }
        loaded = true
        let folders = (try? FileManager.default.contentsOfDirectory(at: Self.directory, includingPropertiesForKeys: nil)) ?? []
        for folder in folders where sources[folder.lastPathComponent] == nil {
            if let source = try? await AidokuRunner.Source(url: folder, interpreterConfig: Self.config(for: folder.lastPathComponent)) {
                sources[source.key] = source
            }
        }
    }

    func all() async -> [AidokuRunner.Source] {
        await loadAll()
        return sources.values.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    func source(_ key: String) async throws -> AidokuRunner.Source {
        await loadAll()
        guard let source = sources[key] else { throw SourceStoreError.notInstalled(key) }
        return source
    }

    func install(from url: URL) async throws -> AidokuRunner.Source {
        await loadAll()
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporary) }

        let (location, _) = try await URLSession.shared.download(for: await Self.prepared(URLRequest(url: url)))
        try FileManager.default.unzipItem(at: location, to: temporary)
        let payload = temporary.appendingPathComponent("Payload")

        // read the key first, then load from the final location
        let probe = try await AidokuRunner.Source(url: payload)
        let key = probe.key
        guard key.range(of: #"^[A-Za-z0-9._-]+$"#, options: .regularExpression) != nil else { throw SourceStoreError.invalidKey }
        let destination = Self.directory.appendingPathComponent(key, isDirectory: true)
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.moveItem(at: payload, to: destination)
        let source = try await AidokuRunner.Source(url: destination, interpreterConfig: Self.config(for: key))
        sources[key] = source
        return source
    }

    func uninstall(key: String) async {
        await loadAll()
        sources[key] = nil
        try? FileManager.default.removeItem(at: Self.directory.appendingPathComponent(key, isDirectory: true))
    }
}

enum SourceStoreError: LocalizedError {
    case notInstalled(String)
    case invalidKey

    var errorDescription: String? {
        switch self {
            case let .notInstalled(key): "The extension \(key) isn't installed on this device."
            case .invalidKey: "The extension has an invalid id."
        }
    }
}
