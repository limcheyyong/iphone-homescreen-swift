// App Store category for each app (public iTunes Lookup API), and grouping apps into folders by it.
import Foundation
import SwiftUI

struct AppMeta: Identifiable {
    var id: String { key }
    var key: String
    var bundleId: String
    var name: String
    var location: String
    var page: Int
    var genre: String?
}

enum Classifier {
    private static let stores = ["tw", "us", "my", "cn"]  // most apps resolve in the first; only look further for the rest
    @MainActor private static var cache: [String: String?] = [:]  // bundleId -> genre

    private struct Lookup: Decodable {
        struct Result: Decodable { var bundleId: String?; var primaryGenreName: String? }
        var results: [Result]
    }

    private static func lookup(_ ids: [String], store: String) async -> [String: String] {
        var out: [String: String] = [:]
        for start in stride(from: 0, to: ids.count, by: 50) {
            var url = URLComponents(string: "https://itunes.apple.com/lookup")!
            url.queryItems = [.init(name: "bundleId", value: ids[start..<min(start + 50, ids.count)].joined(separator: ",")),
                              .init(name: "country", value: store)]
            // offline or rate-limited: those apps get no genre
            guard let (data, _) = try? await URLSession.shared.data(from: url.url!),
                  let r = try? JSONDecoder().decode(Lookup.self, from: data) else { continue }
            for x in r.results { if let id = x.bundleId, let g = x.primaryGenreName { out[id] = g } }
        }
        return out
    }

    @MainActor static func metadata(_ items: [FlatItem]) async -> [AppMeta] {
        let movable = items.filter(\.movable)
        var left = Array(Set(movable.compactMap(\.bundleId))).filter { cache[$0] == nil }
        for store in stores where !left.isEmpty {
            let found = await lookup(left, store: store)
            for (id, g) in found { cache[id] = g }
            left = left.filter { found[$0] == nil }
        }
        for id in left { cache[id] = .some(nil) }
        return movable.map { AppMeta(key: $0.key, bundleId: $0.bundleId!, name: $0.name, location: $0.location, page: $0.page,
                                     genre: cache[$0.bundleId!] ?? nil) }
    }
}

enum Grouping {
    static let genres = [
        "Games": "遊戲", "Entertainment": "娛樂", "Photo & Video": "影音", "Music": "影音", "Graphics": "影音", "Graphics & Design": "影音",
        "Social Networking": "社群", "Finance": "理財", "Business": "工作", "Productivity": "工作",
        "Utilities": "工具", "Developer Tools": "工具", "Education": "學習", "Reference": "學習", "Books": "學習",
        "Travel": "旅遊", "Navigation": "旅遊", "Weather": "旅遊", "Food & Drink": "生活", "Lifestyle": "生活",
        "Shopping": "購物", "Health & Fitness": "健康", "Medical": "健康", "News": "新聞", "Magazines": "新聞", "Sports": "運動",
    ]

    static func type(_ a: AppMeta) -> String {
        if let g = a.genre { return genres[g] ?? "其他" }
        return a.bundleId.hasPrefix("com.apple.") ? "Apple 內建" : "其他"
    }

    /// One folder per type, biggest first. Types with fewer than `minSize` apps go into 其他.
    static func group(_ apps: [AppMeta], minSize: Int) -> [Folder] {
        var byType: [String: [String]] = [:], order: [String] = []
        for a in apps {
            let t = type(a)
            if byType[t] == nil { order.append(t) }
            byType[t, default: []].append(a.key)
        }
        var other = byType.removeValue(forKey: "其他") ?? []
        for (t, keys) in byType where keys.count < minSize { other += keys; byType[t] = nil }
        var out = order.compactMap { t in byType[t].map { Folder(name: t, apps: $0) } }
        out.sort { $0.apps.count > $1.apps.count }
        if !other.isEmpty { out.append(Folder(name: "其他", apps: other)) }
        return out
    }

    private static let tints: [Color] = [.orange, .green, .blue, .purple, .pink, .teal, .yellow, .indigo]
    /// A stable color for apps without an icon.
    static func tint(_ s: String) -> Color {
        tints[Int(s.unicodeScalars.reduce(UInt32(7)) { $0 &* 31 &+ $1.value } % UInt32(tints.count))]
    }
}
