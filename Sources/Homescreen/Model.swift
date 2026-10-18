// App state and the read / organize / apply / restore flow.
import AppKit
import SwiftUI

@MainActor
final class AppModel: ObservableObject {
    enum Screen { case current, new }
    enum Confirm: Identifiable { case apply, restore; var id: Self { self } }

    static let donateURL = URL(string: "https://www.buymeacoffee.com/jayden_lim")!

    // ---- device
    @Published var detected: String?  // udid of a plugged-in iPhone
    @Published var deviceName: String?
    @Published var state: IconState?
    @Published var pages: [Page] = []
    @Published var icons: [String: NSImage] = [:]
    private var backup: URL?
    // ---- organizing
    @Published var meta: [AppMeta]?
    @Published var folders: [Folder] = []
    @Published var scope: Set<Int> = []  // home pages to reorganize; the rest stay as they are
    @Published var minSize = 2
    @Published var edited = false
    @Published var applied = false
    // ---- ui
    @Published var screen: Screen = .current
    @Published var busy: String?
    @Published var error: String?
    @Published var toast: String?
    @Published var confirm: Confirm?
    @Published var showOptions = false
    @Published var dropTarget: UUID?  // folder being dragged over (SwiftUI's @State macro needs full Xcode to build)

    init() {
        DeviceWatcher.shared.onChange = { [weak self] in
            Task { @MainActor in self?.detected = DeviceWatcher.shared.devices.keys.sorted().first }
        }
        DeviceWatcher.shared.start()
        if !MD.available { error = L("Apple’s MobileDevice component was not found. This app needs macOS 13 or later.") }
    }

    var isRead: Bool { state != nil }
    var homePages: [Page] { Array(pages.dropFirst()) }
    var keepPages: Set<Int> { Set(homePages.map(\.id)).subtracting(scope) }
    var appsByKey: [String: AppMeta] { Dictionary((meta ?? []).map { ($0.key, $0) }, uniquingKeysWith: { a, _ in a }) }
    var folderCount: Int { folders.filter { $0.apps.count > 1 }.count }
    var movedCount: Int { folders.reduce(0) { $0 + $1.apps.count } }
    var hasNew: Bool { !folders.isEmpty }
    var stats: (apps: Int, folders: Int, widgets: Int, pages: Int) {
        let tiles = homePages.flatMap(\.tiles)
        return (state.map { Layout.flatten($0).filter(\.movable).count } ?? 0, tiles.filter { $0.kind == .folder }.count,
                tiles.filter { $0.kind == .widget }.count, homePages.count)
    }
    var scopeLabel: String {
        let list = { (pages: [Page]) in ListFormatter.localizedString(byJoining: pages.map(\.title)) }
        let on = homePages.filter { scope.contains($0.id) }, off = homePages.filter { !scope.contains($0.id) }
        if on.isEmpty { return L("Choose the pages to organize in Options first.") }
        return off.isEmpty ? L("Organizes %@.", list(on)) : L("Organizes %@; %@ stay as they are.", list(on), list(off))
    }
    func icon(_ id: String?) -> NSImage? { id.flatMap { icons[$0] } }

    // ---- device calls
    private func run(_ label: String, _ work: () async throws -> Void) async {
        busy = label
        error = nil
        defer { busy = nil }
        do { try await work() } catch { self.error = error.localizedDescription }
    }

    private func device() throws -> MD.Ref {
        guard let udid = detected, let ref = DeviceWatcher.shared.devices[udid] else {
            throw DeviceError(L("No iPhone found. Connect it with a USB cable and unlock it (Wi-Fi does not work)."))
        }
        return ref
    }

    /// Shows a new state, fetching icons we have not seen yet in the same session.
    private func show(_ st: IconState, pngs: [String: Data]) {
        for (id, data) in pngs { icons[id] = NSImage(data: data) }
        state = st
        pages = Layout.pages(st)
    }

    func read() async {
        await run(L("Reading your iPhone and app icons…")) {
            let known = Set(icons.keys)
            let (st, name, pngs) = try await Device.session(try device()) { d in
                let st = try d.iconState()
                return (st, d.name, d.iconPNGs(Layout.bundleIds(Layout.pages(st)).filter { !known.contains($0) }))
            }
            try saveBackup(st)
            deviceName = name
            show(st, pngs: pngs)
            applied = false
            folders = []
            screen = .current
            // reorganize every page except the first (usually Apple's own apps) unless there is only one
            let n = st.count - 1
            scope = Set((1...max(n, 1)).filter { $0 != 1 || n == 1 })
            meta = nil
            Task { await loadMeta() }
        }
    }

    private func saveBackup(_ st: IconState) throws {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Homescreen Organizer/backups", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let file = dir.appendingPathComponent("backup-\(stamp).plist")
        try PropertyListSerialization.data(fromPropertyList: st, format: .xml, options: 0).write(to: file)
        if backup == nil { backup = file }  // restore goes back to how the phone was before this session
    }

    private var loadingMeta = false
    func loadMeta() async {
        guard let st = state, !loadingMeta else { return }
        loadingMeta = true
        defer { loadingMeta = false }
        meta = await Classifier.metadata(Layout.flatten(st))
    }

    func generate() async {
        if meta == nil {
            busy = L("Looking up App Store categories…")
            while loadingMeta { try? await Task.sleep(nanoseconds: 100_000_000) }
            if meta == nil { await loadMeta() }
            busy = nil
        }
        let again = hasNew
        folders = Grouping.group((meta ?? []).filter { scope.contains($0.page) }, minSize: minSize)
        edited = false
        showOptions = false
        screen = .new
        if again { notify(L("Sorted by category again")) }
    }

    func apply() async {
        let plan = Plan(folders: folders.filter { !$0.apps.isEmpty }.map {
            Folder(name: $0.name.trimmingCharacters(in: .whitespaces).isEmpty ? L("Untitled") : $0.name, apps: $0.apps)
        }, keepPages: keepPages)
        await run(L("Writing to your iPhone…")) {
            let known = Set(icons.keys)
            let (st, pngs) = try await Device.session(try device()) { d in
                let next = try Layout.build(try d.iconState(), plan)  // build on the phone's latest state, not a stale copy
                try d.setIconState(next)
                let after = try d.iconState()
                return (after, d.iconPNGs(Layout.bundleIds(Layout.pages(after)).filter { !known.contains($0) }))
            }
            afterWrite(st, pngs)
            applied = true
            scope = Set(homePages.map(\.id)).subtracting(plan.keepPages)
        }
    }

    func restore() async {
        await run(L("Restoring…")) {
            guard let file = backup else { throw DeviceError(L("Nothing to restore yet. Read your iPhone first.")) }
            let saved = try Layout.parse(PropertyListSerialization.propertyList(from: Data(contentsOf: file), format: nil))
            let st = try await Device.session(try device()) { d in
                try d.setIconState(saved)
                return try d.iconState()
            }
            afterWrite(st, [:])
            applied = false
            notify(L("Restored the original layout"))
        }
    }

    private func afterWrite(_ st: IconState, _ pngs: [String: Data]) {
        show(st, pngs: pngs)
        folders = []
        meta = nil  // page numbers changed: refetch for the next round
        screen = .current
        Task { await loadMeta() }
    }

    // ---- manual arranging
    func toggle(page: Int) { if scope.contains(page) { scope.remove(page) } else { scope.insert(page) } }

    func move(_ key: String, to index: Int) {
        guard folders.indices.contains(index), !folders[index].apps.contains(key) else { return }
        for i in folders.indices { folders[i].apps.removeAll { $0 == key } }
        folders[index].apps.append(key)
        edited = true
    }

    func addFolder() {
        folders.append(Folder(name: L("New Folder"), apps: []))
        edited = true
    }

    func removeFolder(_ index: Int) {
        let gone = folders.remove(at: index)
        if !gone.apps.isEmpty {
            let other = Grouping.other
            if let i = folders.firstIndex(where: { $0.name == other }) { folders[i].apps += gone.apps }
            else { folders.append(Folder(name: other, apps: gone.apps)) }
            notify(L("Apps from “%@” moved to “%@”", gone.name, other))
        }
        edited = true
    }

    func donate() { NSWorkspace.shared.open(Self.donateURL) }

    private var toastTask: Task<Void, Never>?
    func notify(_ text: String) {
        toast = text
        toastTask?.cancel()
        toastTask = Task { try? await Task.sleep(nanoseconds: 3_200_000_000); if !Task.isCancelled { toast = nil } }
    }
}
