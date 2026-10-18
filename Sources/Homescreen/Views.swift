import SwiftUI

struct ContentView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        NavigationSplitView {
            Sidebar().navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 280)
        } detail: {
            Detail()
        }
        .alert(item: $model.confirm) { c in
            switch c {
            case .apply:
                return Alert(title: Text("把新排版套用到 iPhone？"),
                             message: Text("會建立 \(model.folderCount) 個資料夾、整理 \(model.movedCount) 個 App。"
                                           + (model.keepPages.isEmpty ? "Dock 不會改變。" : "沒選的頁面和 Dock 不會改變。")
                                           + "\n原本的排版已經備份，隨時可以還原。"),
                             primaryButton: .default(Text("套用")) { Task { await model.apply() } },
                             secondaryButton: .cancel(Text("取消")))
            case .restore:
                return Alert(title: Text("還原成原本的排版？"),
                             message: Text("iPhone 會回到這次第一次讀取時的樣子。讀取之後在手機上做的變更會被覆蓋。"),
                             primaryButton: .default(Text("還原")) { Task { await model.restore() } },
                             secondaryButton: .cancel(Text("取消")))
            }
        }
    }
}

// MARK: - Sidebar

struct Sidebar: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 10) {
                Image(systemName: "iphone").font(.system(size: 26, weight: .light)).foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.deviceName ?? "iPhone").font(.headline).lineLimit(1)
                    Label(model.detected == nil ? "尚未連接" : "已透過 USB 連接", systemImage: "circle.fill")
                        .labelStyle(StatusLabel(on: model.detected != nil))
                }
            }
            VStack(alignment: .leading, spacing: 10) {
                step(1, "連接 iPhone", done: model.isRead, current: !model.isRead)
                step(2, "整理主畫面", done: model.applied, current: model.isRead && !model.applied)
                step(3, "套用到 iPhone", done: model.applied, current: false)
            }
            Spacer()
            if model.isRead {
                Button { Task { await model.read() } } label: { Label("重新讀取 iPhone", systemImage: "arrow.clockwise") }
                Button { model.confirm = .restore } label: { Label("還原原本排版", systemImage: "arrow.uturn.backward") }
            }
            Button { model.donate() } label: { Label("請我喝杯咖啡", systemImage: "cup.and.saucer") }
        }
        .buttonStyle(.borderless)
        .disabled(model.busy != nil)
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func step(_ n: Int, _ label: String, done: Bool, current: Bool) -> some View {
        HStack(spacing: 10) {
            ZStack {
                Circle().fill(done ? Color.accentColor : current ? Color.accentColor.opacity(0.15) : Color.secondary.opacity(0.15))
                if done { Image(systemName: "checkmark").font(.system(size: 10, weight: .bold)).foregroundStyle(.white) }
                else { Text("\(n)").font(.system(size: 11, weight: .semibold)).foregroundStyle(current ? Color.accentColor : .secondary) }
            }
            .frame(width: 20, height: 20)
            Text(label).foregroundStyle(current || done ? .primary : .secondary).fontWeight(current ? .semibold : .regular)
        }
    }
}

struct StatusLabel: LabelStyle {
    var on: Bool
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 5) {
            configuration.icon.font(.system(size: 6)).foregroundStyle(on ? .green : .secondary)
            configuration.title.font(.caption).foregroundStyle(.secondary)
        }
    }
}

// MARK: - Detail

struct Detail: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        ZStack(alignment: .bottom) {
            VStack(spacing: 0) {
                if let error = model.error { ErrorBanner(text: error) }
                if !model.isRead { EmptyState() }
                else if model.screen == .current { CurrentLayout() }
                else { NewLayout() }
            }
            if let toast = model.toast {
                Text(toast).font(.callout.weight(.medium)).padding(.horizontal, 16).padding(.vertical, 8)
                    .background(.regularMaterial, in: Capsule()).shadow(radius: 8, y: 2).padding(.bottom, 20)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(duration: 0.35), value: model.toast)
        .navigationTitle(model.isRead ? "主畫面" : "主畫面整理")
        .navigationSubtitle(subtitle)
        .toolbar { if model.isRead { toolbar } }
        .overlay(alignment: .top) { if model.busy != nil { ProgressView().progressViewStyle(.linear).frame(height: 2) } }
    }

    private var subtitle: String {
        if let busy = model.busy { return busy }
        guard model.isRead else { return "" }
        if model.screen == .new { return "\(model.folderCount) 個資料夾、\(model.movedCount) 個 App" + (model.edited ? "，含手動調整" : "") }
        return model.applied ? "已套用新排版" : "已備份原本排版"
    }

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            Picker("檢視", selection: $model.screen) {
                Text("目前").tag(AppModel.Screen.current)
                Text("新排版").tag(AppModel.Screen.new).disabled(!model.hasNew)
            }
            .pickerStyle(.segmented).frame(width: 160)
        }
        ToolbarItemGroup(placement: .primaryAction) {
            Button { model.showOptions.toggle() } label: { Label("分類選項", systemImage: "slider.horizontal.3") }
                .help("分類選項")
                .popover(isPresented: $model.showOptions, arrowEdge: .bottom) { Options().environmentObject(model) }
            if model.hasNew {
                Button("套用到 iPhone…") { model.confirm = .apply }.buttonStyle(.borderedProminent)
            } else {
                Button("依類型分類") { Task { await model.generate() } }.buttonStyle(.borderedProminent).disabled(model.scope.isEmpty)
            }
        }
    }
}

struct ErrorBanner: View {
    @EnvironmentObject var model: AppModel
    let text: String
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.red)
            Text(text).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
            Button("關閉") { model.error = nil }.controlSize(.small)
        }
        .padding(12)
        .background(Color.red.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
        .padding([.horizontal, .top], 20)
    }
}

struct EmptyState: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: "cable.connector.horizontal").font(.system(size: 56, weight: .thin)).foregroundStyle(Color.accentColor)
            Text("用 USB 線接上 iPhone").font(.title.bold())
            Text("解鎖手機。第一次連接時，iPhone 會問要不要信任這台電腦，請點「信任」。讀取只會備份並顯示目前的排版，不會改動手機。")
                .multilineTextAlignment(.center).foregroundStyle(.secondary).frame(maxWidth: 420)
            Button { Task { await model.read() } } label: { Text("讀取 iPhone").padding(.horizontal, 12) }
                .buttonStyle(.borderedProminent).controlSize(.large).disabled(model.busy != nil || model.detected == nil)
            Text(model.detected == nil ? "等待 iPhone 連接…" : "已偵測到 iPhone").font(.caption).foregroundStyle(.secondary)
            Spacer()
        }
        .padding(24)
        .frame(maxWidth: .infinity)
    }
}

struct Options: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("整理哪些頁面").font(.headline)
            HStack {
                ForEach(model.homePages) { p in
                    Toggle(p.title, isOn: Binding(get: { model.scope.contains(p.id) }, set: { _ in model.toggle(page: p.id) }))
                        .toggleStyle(.button)
                }
            }
            Text("沒選的頁面保持原樣。Dock 和小工具都不會移動。").font(.caption).foregroundStyle(.secondary)
            Divider()
            Text("分類方式").font(.headline)
            Text("依 App Store 的類型放進資料夾，例如理財、旅遊、社群。").font(.caption).foregroundStyle(.secondary)
            Picker("少於幾個 App 的類型，併進「其他」", selection: $model.minSize) {
                ForEach(1...5, id: \.self) { Text("\($0)").tag($0) }
            }
            .frame(width: 300)
            Divider()
            HStack {
                if model.edited { Text("會取代手動調整").font(.caption).foregroundStyle(.orange) }
                Spacer()
                Button(model.hasNew ? "重新分類" : "產生新排版") { Task { await model.generate() } }
                    .buttonStyle(.borderedProminent).disabled(model.scope.isEmpty || model.busy != nil)
            }
        }
        .padding(16)
        .frame(width: 340)
    }
}

// MARK: - Current layout

struct CurrentLayout: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if model.applied { Success() } else { statsRow; CallToAction() }
                if let dock = model.pages.first {
                    PageSection(title: "Dock", tag: Text("不會改變").foregroundStyle(.secondary)) {
                        AppGrid(cells: dock.tiles.map { Cell(name: $0.name, image: model.icon($0.bundleId)) })
                            .padding(14).background(Card())
                    }
                }
                ForEach(model.homePages) { page in
                    let on = model.scope.contains(page.id)
                    PageSection(title: page.title, tag: model.applied ? nil : AnyView(
                        Button(on ? "要整理" : "保持原樣") { model.toggle(page: page.id) }
                            .buttonStyle(.bordered).controlSize(.mini).tint(on ? .accentColor : .secondary)
                            .help(on ? "這一頁會被重新整理，點一下改成保持原樣" : "這一頁保持原樣，點一下改成要整理"))) {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), spacing: 12, alignment: .top)], alignment: .leading, spacing: 12) {
                            ForEach(cards(page.tiles)) { $0 }
                        }
                    }
                    .opacity(on || model.applied ? 1 : 0.5)
                }
            }
            .padding(24)
        }
    }

    private var statsRow: some View {
        let s = model.stats
        return HStack(spacing: 32) {
            stat("App", s.apps); stat("資料夾", s.folders)
            if s.widgets > 0 { stat("小工具", s.widgets) }
            stat("頁面", s.pages)
        }
    }
    private func stat(_ label: String, _ n: Int) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("\(n)").font(.system(size: 28, weight: .bold)).monospacedDigit()
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
    }

    /// One card per folder, plus cards for loose apps and widgets.
    private func cards(_ tiles: [Tile]) -> [TileCard] {
        let loose = tiles.filter { $0.kind == .app }, widgets = tiles.filter { $0.kind == .widget }
        let sizes = ["small": "小", "medium": "中", "large": "大", "extralarge": "特大"]
        var out: [TileCard] = []
        if !loose.isEmpty { out.append(TileCard(title: "主畫面上的 App", folder: false, cells: loose.map { Cell(name: $0.name, image: model.icon($0.bundleId)) })) }
        for f in tiles where f.kind == .folder {
            out.append(TileCard(title: f.name, folder: true, cells: f.apps.map { Cell(name: $0.name, image: model.icon($0.bundleId)) }))
        }
        if !widgets.isEmpty {
            out.append(TileCard(title: "小工具", folder: false, cells: widgets.map {
                Cell(name: $0.name, image: model.icon($0.bundleId), note: ($0.stack ? "堆疊・" : "") + (sizes[$0.size] ?? "小"))
            }))
        }
        return out
    }
}

struct CallToAction: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: "square.grid.2x2").font(.system(size: 28)).foregroundStyle(Color.accentColor)
            VStack(alignment: .leading, spacing: 2) {
                Text(model.hasNew ? "新排版已經準備好了" : "一鍵依類型整理").font(.headline)
                Text(model.hasNew ? "看一下新排版、拖曳微調，滿意後再套用到 iPhone。"
                     : "依 App Store 類型把 App 放進資料夾。\(model.scopeLabel)套用前可以先預覽和微調。")
                    .font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
            if model.hasNew {
                Button("查看新排版") { model.screen = .new }.buttonStyle(.borderedProminent).controlSize(.large)
            } else {
                Button("選項…") { model.showOptions = true }.buttonStyle(.link)
                Button("依類型分類") { Task { await model.generate() } }
                    .buttonStyle(.borderedProminent).controlSize(.large).disabled(model.scope.isEmpty || model.busy != nil)
            }
        }
        .padding(16)
        .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.accentColor.opacity(0.3)))
    }
}

struct Success: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: "checkmark.circle.fill").font(.system(size: 40)).foregroundStyle(.green)
            VStack(alignment: .leading, spacing: 6) {
                Text("已套用到 iPhone").font(.title2.bold())
                Text("這是手機現在的樣子。不滿意的話，可以點左邊的「還原原本排版」。").foregroundStyle(.secondary)
                Text("這個工具免費使用，覺得有幫助的話歡迎贊助：").font(.caption).foregroundStyle(.secondary).padding(.top, 4)
                Button { model.donate() } label: {
                    if let img = NSImage(named: "bmc-button") {
                        Image(nsImage: img).resizable().scaledToFit().frame(height: 40)
                    } else {
                        Label("請我喝杯咖啡", systemImage: "cup.and.saucer")
                    }
                }
                .buttonStyle(.plain)
                .help("Buy Me a Coffee")
            }
        }
    }
}

struct PageSection<Content: View>: View {
    let title: String
    var tag: AnyView?
    @ViewBuilder var content: Content

    init(title: String, tag: (some View)?, @ViewBuilder content: () -> Content) {
        self.title = title
        self.tag = tag.map { AnyView($0) }
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) { Text(title).font(.headline); tag }
            content
        }
    }
}

struct Card: View {
    var body: some View { RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.primary.opacity(0.04)) }
}

struct TileCard: View, Identifiable {
    let id = UUID()
    let title: String
    let folder: Bool
    let cells: [Cell]
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                if folder { Image(systemName: "folder").foregroundStyle(Color.accentColor) }
                Text(title).font(.subheadline.weight(.semibold))
                Spacer()
                Text("\(cells.count)").font(.caption).foregroundStyle(.tertiary).monospacedDigit()
            }
            AppGrid(cells: cells)
        }
        .padding(14)
        .background(Card())
    }
}

// MARK: - Apps

struct Cell: Identifiable {
    let id = UUID()
    var name: String
    var image: NSImage?
    var note: String?
}

struct AppGrid: View {
    let cells: [Cell]
    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 64), spacing: 6)], alignment: .leading, spacing: 10) {
            ForEach(cells) { AppIcon(name: $0.name, image: $0.image, note: $0.note) }
        }
    }
}

struct AppIcon: View {
    let name: String
    let image: NSImage?
    var note: String?
    private let size: CGFloat = 44

    var body: some View {
        VStack(spacing: 4) {
            Group {
                if let image { Image(nsImage: image).resizable().interpolation(.high) }
                else {
                    Grouping.tint(name).overlay(Text(String(name.first ?? "?")).font(.system(size: 18, weight: .semibold)).foregroundStyle(.white))
                }
            }
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: size * 0.225, style: .continuous))
            Text(name).font(.system(size: 11)).lineLimit(1).truncationMode(.tail).frame(width: 64)
            if let note { Text(note).font(.system(size: 9)).foregroundStyle(.secondary) }
        }
        .help(name)
    }
}

// MARK: - New layout

struct NewLayout: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("依 App Store 類型分類。把 App 拖到其他資料夾，或按右鍵選擇要移到哪裡；資料夾名稱可以直接改。")
                    .font(.callout).foregroundStyle(.secondary)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), spacing: 12, alignment: .top)], alignment: .leading, spacing: 12) {
                    ForEach(Array(model.folders.enumerated()), id: \.element.id) { i, folder in
                        FolderEditor(index: i, folder: folder)
                    }
                    Button { model.addFolder() } label: {
                        Label("新增資料夾", systemImage: "plus").frame(maxWidth: .infinity, minHeight: 80)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .background(RoundedRectangle(cornerRadius: 12).strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [5])).foregroundStyle(.tertiary))
                }
            }
            .padding(24)
        }
    }
}

struct FolderEditor: View {
    @EnvironmentObject var model: AppModel
    let index: Int
    let folder: Folder
    var body: some View {
        let apps = model.appsByKey
        let targeted = model.dropTarget == folder.id
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                TextField("資料夾名稱", text: Binding(get: { folder.name }, set: { model.folders[index].name = $0; model.edited = true }))
                    .textFieldStyle(.plain).font(.subheadline.weight(.semibold))
                Text("\(folder.apps.count)").font(.caption).foregroundStyle(.tertiary).monospacedDigit()
                Button { model.removeFolder(index) } label: { Image(systemName: "trash") }
                    .buttonStyle(.borderless).foregroundStyle(.secondary).help("刪除資料夾")
            }
            if folder.apps.isEmpty {
                Text("把 App 拖到這裡").font(.caption).foregroundStyle(.tertiary).frame(maxWidth: .infinity, minHeight: 60)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 64), spacing: 6)], alignment: .leading, spacing: 10) {
                    ForEach(folder.apps, id: \.self) { key in
                        let a = apps[key]
                        AppIcon(name: a?.name ?? key, image: model.icon(a?.bundleId))
                            .help("\(a?.name ?? key)・\(a?.genre ?? "未知類型")・原本在\(a?.location ?? "")")
                            .draggable(key)
                            .contextMenu {
                                Text("移到…")
                                ForEach(Array(model.folders.enumerated()), id: \.element.id) { j, f in
                                    if j != index { Button(f.name) { model.move(key, to: j); model.notify("已將「\(a?.name ?? key)」移到「\(f.name)」") } }
                                }
                            }
                    }
                }
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(targeted ? Color.accentColor.opacity(0.1) : Color.primary.opacity(0.04)))
        .dropDestination(for: String.self) { keys, _ in
            for k in keys { model.move(k, to: index) }
            return true
        } isTargeted: { model.dropTarget = $0 ? folder.id : (model.dropTarget == folder.id ? nil : model.dropTarget) }
    }
}
