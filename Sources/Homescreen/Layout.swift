// Pure layout logic: describe pages for the UI, flatten icons, build a new state from a plan.
import Foundation

typealias Item = [String: Any]
typealias IconState = [[Item]]  // page 0 is the dock

struct AppRef: Hashable { var name: String; var bundleId: String? }

struct Tile: Identifiable {
    enum Kind { case app, folder, widget }
    let id = UUID()
    var kind: Kind
    var name: String
    var bundleId: String?
    var apps: [AppRef] = []
    var size = "small"
    var stack = false
}

struct Page: Identifiable {
    let id: Int  // 0 is the dock
    var title: String
    var tiles: [Tile]
}

struct FlatItem {
    var key: String
    var name: String
    var bundleId: String?
    var origin: String?
    var page: Int
    var movable: Bool
    var location: String
    var raw: Item
}

struct Folder: Identifiable, Equatable {
    var id = UUID()
    var name: String
    var apps: [String]  // FlatItem keys
}

struct Plan {
    var folders: [Folder]
    var keepPages: Set<Int>
}

enum Layout {
    // Apple apps sometimes come without a displayName. Names are English keys, localized with L().
    static let appleNames = [
        "com.apple.MobileSMS": "Messages", "com.apple.mobilephone": "Phone", "com.apple.mobilesafari": "Safari", "com.apple.Music": "Music",
        "com.apple.mobilemail": "Mail", "com.apple.mobilecal": "Calendar", "com.apple.mobileslideshow": "Photos", "com.apple.camera": "Camera",
        "com.apple.weather": "Weather", "com.apple.mobilenotes": "Notes", "com.apple.Preferences": "Settings", "com.apple.AppStore": "App Store",
        "com.apple.facetime": "FaceTime", "com.apple.mobiletimer": "Clock", "com.apple.reminders": "Reminders", "com.apple.Maps": "Maps",
    ]
    // Readable names for Apple's own widgets, keyed by the last part of the app's bundle id.
    static let appleWidgets = [
        "batteries": "Batteries", "weather": "Weather", "mobilecal": "Calendar", "mobiletimer": "Clock", "mobileslideshow": "Photos", "reminders": "Reminders",
        "maps": "Maps", "news": "News", "stocks": "Stocks", "fitness": "Fitness", "health": "Health", "mobilenotes": "Notes", "findmy": "Find My",
        "music": "Music", "podcasts": "Podcasts", "home": "Home", "shortcuts": "Shortcuts", "tips": "Tips", "screentimewidgetapplication": "Screen Time",
        "mobilesafari": "Safari", "files": "Files", "tv": "TV", "journal": "Journal", "contacts": "Contacts", "mobilemail": "Mail", "sleep": "Sleep",
    ]

    /// The phone's reply as an icon state. Refuses anything unexpected rather than silently dropping icons.
    static func parse(_ plist: Any) throws -> IconState {
        guard let pages = plist as? [[Any]] else { throw DeviceError(L("The iPhone returned an unexpected home screen format.")) }
        return try pages.map { page in
            try page.map { guard let item = $0 as? Item else { throw DeviceError(L("The iPhone returned an unexpected home screen format.")) }; return item }
        }
    }

    static func bundleId(_ i: Item) -> String? { i["bundleIdentifier"] as? String }
    static func displayName(_ i: Item) -> String? { (i["displayName"] as? String).flatMap { $0.isEmpty ? nil : $0 } }
    static func key(_ i: Item) -> String { displayName(i) ?? bundleId(i).flatMap { appleNames[$0].map(L) ?? $0 } ?? "?" }
    static func isFolder(_ i: Item) -> Bool { i["listType"] as? String == "folder" }
    static func lists(_ i: Item) -> [[Item]]? { (i["iconLists"] as? [[Any]])?.map { $0.compactMap { $0 as? Item } } }
    static func members(_ f: Item) -> [Item] { (lists(f) ?? []).flatMap { $0 } }
    static func isStack(_ i: Item) -> Bool { i["iconLists"] is [Any] && !isFolder(i) }
    static func isWidget(_ x: Item) -> Bool {
        if x["gridSize"] != nil { return true }
        let type = (x["elementType"] ?? x["iconType"]).map { "\($0)" } ?? ""
        if type.range(of: "widget", options: .caseInsensitive) != nil { return true }
        return displayName(x) == nil && (bundleId(x) ?? "").range(of: "widget|extension", options: [.regularExpression, .caseInsensitive]) != nil
    }

    // ---- widgets -----------------------------------------------------------------
    private static func container(_ x: Item) -> String {
        if let c = x["containerBundleIdentifier"] as? String { return c }
        var parts = (bundleId(x) ?? "").split(separator: ".").map(String.init)
        while parts.count > 2, parts.last!.range(of: "widget|extension|intent", options: [.regularExpression, .caseInsensitive]) != nil { parts.removeLast() }
        return parts.joined(separator: ".")
    }
    private static func prettify(_ s: String) -> String {
        let trimmed = s.replacingOccurrences(of: "(Widget|Extension|Intents?)+$", with: "", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: "([a-z])([A-Z])", with: "$1 $2", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? s : trimmed
    }
    private static func gridSize(_ x: Item) -> String {
        let s = (x["gridSize"].map { "\($0)" } ?? "small").lowercased().filter(\.isLetter)
        return ["small", "medium", "large", "extralarge"].contains(s) ? s : "small"
    }
    private static func widgetTile(_ x: Item, _ names: [String: String], stack: Bool = false) -> Tile {
        let app = container(x)
        let last = app.split(separator: ".").last.map(String.init) ?? ""
        return Tile(kind: .widget, name: names[app] ?? appleWidgets[last.lowercased()].map(L) ?? prettify(last), bundleId: app,
                    size: gridSize(x), stack: stack)
    }

    // ---- describing a state for the UI ---------------------------------------------
    private static func appNames(_ state: IconState) -> [String: String] {
        var names: [String: String] = [:]
        for page in state { for it in page { for x in isFolder(it) ? members(it) : [it] {
            if let id = bundleId(x), let n = displayName(x) { names[id] = n }
        } } }
        return names
    }
    private static func tile(_ it: Item, _ names: [String: String]) -> Tile {
        if isFolder(it) {
            return Tile(kind: .folder, name: displayName(it) ?? L("Folder"), apps: members(it).map { AppRef(name: key($0), bundleId: bundleId($0)) })
        }
        if isStack(it) {
            var first = members(it).first ?? [:]
            if let g = it["gridSize"] { first["gridSize"] = g }
            return widgetTile(first, names, stack: true)
        }
        if isWidget(it) { return widgetTile(it, names) }
        return Tile(kind: .app, name: key(it), bundleId: bundleId(it))
    }
    static func pages(_ state: IconState) -> [Page] {
        let names = appNames(state)
        return state.enumerated().map { i, p in Page(id: i, title: i == 0 ? "Dock" : L("Page %ld", i), tiles: p.map { tile($0, names) }) }
    }
    static func bundleIds(_ pages: [Page]) -> [String] {
        var ids: [String] = [], seen = Set<String>()
        for p in pages { for t in p.tiles { for id in [t.bundleId] + t.apps.map(\.bundleId) {
            if let id, seen.insert(id).inserted { ids.append(id) }
        } } }
        return ids
    }

    // ---- flatten & build -------------------------------------------------------------
    /// Every icon on the home pages (not the dock), with a unique key and where it sits now.
    static func flatten(_ state: IconState, keep: Set<Int> = []) -> [FlatItem] {
        var items: [FlatItem] = []
        var seen: [String: Int] = [:]
        for (pi, page) in state.dropFirst().enumerated() where !keep.contains(pi + 1) {  // pinned pages stay exactly as they are
            for it in page {
                let inFolder = isFolder(it)
                for x in inFolder ? members(it) : [it] {
                    let name = key(x)
                    let n = (seen[name] ?? 0) + 1
                    seen[name] = n
                    let folder = inFolder ? displayName(it) : nil
                    items.append(FlatItem(
                        key: n > 1 ? "\(name)#\(n)" : name, name: name, bundleId: bundleId(x), origin: folder, page: pi + 1,
                        // widgets, stacks and other non-app tiles stay where they are
                        movable: bundleId(x) != nil && !isWidget(x) && !isStack(x),
                        location: L("Page %ld", pi + 1) + (folder.map { " / \($0)" } ?? ""), raw: x))
                }
            }
        }
        return items
    }

    /// The new icon state for a plan. The dock and pinned pages are untouched, and no icon is ever dropped.
    static func build(_ state: IconState, _ plan: Plan) throws -> IconState {
        let items = flatten(state, keep: plan.keepPages)
        let pool = Dictionary(items.map { ($0.key, $0) }, uniquingKeysWith: { a, _ in a })
        var oldFolders: [String: Item] = [:]
        for (i, p) in state.dropFirst().enumerated() where !plan.keepPages.contains(i + 1) {
            for it in p where isFolder(it) { oldFolders[displayName(it) ?? ""] = it }
        }
        var used = Set<String>()
        func take(_ k: String) throws -> Item {
            guard let it = pool[k] else { throw DeviceError(L("App not found: %@", k)) }
            guard used.insert(k).inserted else { throw DeviceError(L("App appears twice: %@", k)) }
            return it.raw
        }
        var tiles: [Item] = []
        for f in plan.folders {
            let apps = try f.apps.map(take)
            if apps.isEmpty { continue }
            if apps.count == 1 { tiles.append(apps[0]); continue }  // a one-app folder is just the app
            var folder = oldFolders[f.name] ?? [:]
            folder["displayName"] = f.name
            folder["listType"] = "folder"
            folder["iconLists"] = stride(from: 0, to: apps.count, by: 9).map { Array(apps[$0..<min($0 + 9, apps.count)]) }
            tiles.append(folder)
        }
        let left = items.filter { !used.contains($0.key) }.map(\.raw)  // widgets included
        let pinned = state.dropFirst().enumerated().filter { plan.keepPages.contains($0.offset + 1) }.map(\.element)
        return [state[0]] + pinned + paginate(tiles) + paginate(left)
    }

    /// Splits tiles into pages of 4 x 6 slots. Widgets take 2 x 2, 4 x 2 or 4 x 4 slots, not one.
    static func paginate(_ tiles: [Item]) -> [[Item]] {
        var pages: [[Item]] = [], page: [Item] = [], used = 0
        for t in tiles {
            let slots = isWidget(t) || isStack(t) ? ["small": 4, "medium": 8, "large": 16, "extralarge": 16][gridSize(t)]! : 1
            if used + slots > 24, !page.isEmpty { pages.append(page); page = []; used = 0 }
            page.append(t)
            used += slots
        }
        if !page.isEmpty { pages.append(page) }
        return pages
    }
}
