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
                return Alert(title: Text("Apply the new layout to your iPhone?"),
                             message: Text(L("Creates %ld folders and organizes %ld apps.", model.folderCount, model.movedCount) + " "
                                           + (model.keepPages.isEmpty ? L("The Dock will not change.") : L("Unselected pages and the Dock will not change."))
                                           + "\n" + L("Your original layout is backed up and can be restored anytime.")),
                             primaryButton: .default(Text("Apply")) { Task { await model.apply() } },
                             secondaryButton: .cancel(Text("Cancel")))
            case .restore:
                return Alert(title: Text("Restore the original layout?"),
                             message: Text("Your iPhone goes back to how it was when you first read it in this session. Changes made on the phone since then will be overwritten."),
                             primaryButton: .default(Text("Restore")) { Task { await model.restore() } },
                             secondaryButton: .cancel(Text("Cancel")))
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
                    Label(model.detected == nil ? L("Not connected") : L("Connected via USB"), systemImage: "circle.fill")
                        .labelStyle(StatusLabel(on: model.detected != nil))
                }
            }
            VStack(alignment: .leading, spacing: 10) {
                step(1, L("Connect iPhone"), done: model.isRead, current: !model.isRead)
                step(2, L("Organize Home Screen"), done: model.applied, current: model.isRead && !model.applied)
                step(3, L("Apply to iPhone"), done: model.applied, current: false)
            }
            Spacer()
            if model.isRead {
                Button { Task { await model.read() } } label: { Label("Read iPhone Again", systemImage: "arrow.clockwise") }
                Button { model.confirm = .restore } label: { Label("Restore Original Layout", systemImage: "arrow.uturn.backward") }
            }
            Button { model.donate() } label: { Label("Buy Me a Coffee", systemImage: "cup.and.saucer") }
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
        .navigationTitle(model.isRead ? L("Home Screen") : L("Homescreen Organizer"))
        .navigationSubtitle(subtitle)
        .toolbar { if model.isRead { toolbar } }
        .overlay(alignment: .top) { if model.busy != nil { ProgressView().progressViewStyle(.linear).frame(height: 2) } }
    }

    private var subtitle: String {
        if let busy = model.busy { return busy }
        guard model.isRead else { return "" }
        if model.screen == .new { return L("%ld folders, %ld apps", model.folderCount, model.movedCount) + (model.edited ? L(", including manual changes") : "") }
        return model.applied ? L("New layout applied") : L("Original layout backed up")
    }

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            Picker("View", selection: $model.screen) {
                Text("Current").tag(AppModel.Screen.current)
                Text("New Layout").tag(AppModel.Screen.new).disabled(!model.hasNew)
            }
            .pickerStyle(.segmented).frame(width: 160)
        }
        ToolbarItemGroup(placement: .primaryAction) {
            Button { model.showOptions.toggle() } label: { Label("Sort Options", systemImage: "slider.horizontal.3") }
                .help("Sort Options")
                .popover(isPresented: $model.showOptions, arrowEdge: .bottom) { Options().environmentObject(model) }
            if model.hasNew {
                Button("Apply to iPhone…") { model.confirm = .apply }.buttonStyle(.borderedProminent)
            } else {
                Button("Sort by Category") { Task { await model.generate() } }.buttonStyle(.borderedProminent).disabled(model.scope.isEmpty)
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
            Button("Close") { model.error = nil }.controlSize(.small)
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
            Text("Connect your iPhone with a USB cable").font(.title.bold())
            Text("Unlock your phone. The first time, your iPhone asks whether to trust this computer: tap “Trust”. Reading only backs up and shows your current layout. Nothing on the phone changes.")
                .multilineTextAlignment(.center).foregroundStyle(.secondary).frame(maxWidth: 420)
            Button { Task { await model.read() } } label: { Text("Read iPhone").padding(.horizontal, 12) }
                .buttonStyle(.borderedProminent).controlSize(.large).disabled(model.busy != nil || model.detected == nil)
            Text(model.detected == nil ? L("Waiting for iPhone…") : L("iPhone detected")).font(.caption).foregroundStyle(.secondary)
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
            Text("Pages to organize").font(.headline)
            HStack {
                ForEach(model.homePages) { p in
                    Toggle(p.title, isOn: Binding(get: { model.scope.contains(p.id) }, set: { _ in model.toggle(page: p.id) }))
                        .toggleStyle(.button)
                }
            }
            Text("Unselected pages stay as they are. The Dock and widgets never move.").font(.caption).foregroundStyle(.secondary)
            Divider()
            Text("Grouping").font(.headline)
            Text("Apps go into folders by App Store category, such as Finance, Travel and Social.").font(.caption).foregroundStyle(.secondary)
            Picker("Merge smaller categories into “Other” below", selection: $model.minSize) {
                ForEach(1...5, id: \.self) { Text("\($0)").tag($0) }
            }
            .frame(width: 300)
            Divider()
            HStack {
                if model.edited { Text("Replaces your manual changes").font(.caption).foregroundStyle(.orange) }
                Spacer()
                Button(model.hasNew ? L("Sort Again") : L("Create New Layout")) { Task { await model.generate() } }
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
                    PageSection(title: "Dock", tag: Text("Never changes").foregroundStyle(.secondary)) {
                        AppGrid(cells: dock.tiles.map { Cell(name: $0.name, image: model.icon($0.bundleId)) })
                            .padding(14).background(Card())
                    }
                }
                ForEach(model.homePages) { page in
                    let on = model.scope.contains(page.id)
                    PageSection(title: page.title, tag: model.applied ? nil : AnyView(
                        Button(on ? L("Organize") : L("Keep As Is")) { model.toggle(page: page.id) }
                            .buttonStyle(.bordered).controlSize(.mini).tint(on ? .accentColor : .secondary)
                            .help(on ? L("This page will be reorganized. Click to keep it as is.") : L("This page stays as is. Click to organize it.")))) {
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
            stat(L("Apps"), s.apps); stat(L("Folders"), s.folders)
            if s.widgets > 0 { stat(L("Widgets"), s.widgets) }
            stat(L("Pages"), s.pages)
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
        let sizes = ["small": L("Small"), "medium": L("Medium"), "large": L("Large"), "extralarge": L("Extra Large")]
        var out: [TileCard] = []
        if !loose.isEmpty { out.append(TileCard(title: L("Apps on Home Screen"), folder: false, cells: loose.map { Cell(name: $0.name, image: model.icon($0.bundleId)) })) }
        for f in tiles where f.kind == .folder {
            out.append(TileCard(title: f.name, folder: true, cells: f.apps.map { Cell(name: $0.name, image: model.icon($0.bundleId)) }))
        }
        if !widgets.isEmpty {
            out.append(TileCard(title: L("Widgets"), folder: false, cells: widgets.map {
                Cell(name: $0.name, image: model.icon($0.bundleId), note: ($0.stack ? L("Stack") + " · " : "") + (sizes[$0.size] ?? L("Small")))
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
                Text(model.hasNew ? L("Your new layout is ready") : L("Sort by category in one click")).font(.headline)
                Text(model.hasNew ? L("Review the new layout, drag to fine-tune, then apply it to your iPhone.")
                     : L("Puts apps into folders by App Store category. %@ You can preview and fine-tune before applying.", model.scopeLabel))
                    .font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
            if model.hasNew {
                Button("View New Layout") { model.screen = .new }.buttonStyle(.borderedProminent).controlSize(.large)
            } else {
                Button("Options…") { model.showOptions = true }.buttonStyle(.link)
                Button("Sort by Category") { Task { await model.generate() } }
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
                Text("Applied to your iPhone").font(.title2.bold())
                Text("This is how your phone looks now. Not happy? Click “Restore Original Layout” in the sidebar.").foregroundStyle(.secondary)
                Text("This app is free. If it helped, consider supporting it:").font(.caption).foregroundStyle(.secondary).padding(.top, 4)
                Button { model.donate() } label: {
                    if let img = NSImage(named: "bmc-button") {
                        Image(nsImage: img).resizable().scaledToFit().frame(height: 40)
                    } else {
                        Label("Buy Me a Coffee", systemImage: "cup.and.saucer")
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
                Text("Sorted by App Store category. Drag apps to another folder, or right-click to choose where they go. Click a folder name to rename it.")
                    .font(.callout).foregroundStyle(.secondary)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), spacing: 12, alignment: .top)], alignment: .leading, spacing: 12) {
                    ForEach(Array(model.folders.enumerated()), id: \.element.id) { i, folder in
                        FolderEditor(index: i, folder: folder)
                    }
                    Button { model.addFolder() } label: {
                        Label("New Folder", systemImage: "plus").frame(maxWidth: .infinity, minHeight: 80)
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
                TextField("Folder name", text: Binding(get: { folder.name }, set: { model.folders[index].name = $0; model.edited = true }))
                    .textFieldStyle(.plain).font(.subheadline.weight(.semibold))
                Text("\(folder.apps.count)").font(.caption).foregroundStyle(.tertiary).monospacedDigit()
                Button { model.removeFolder(index) } label: { Image(systemName: "trash") }
                    .buttonStyle(.borderless).foregroundStyle(.secondary).help("Delete folder")
            }
            if folder.apps.isEmpty {
                Text("Drag apps here").font(.caption).foregroundStyle(.tertiary).frame(maxWidth: .infinity, minHeight: 60)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 64), spacing: 6)], alignment: .leading, spacing: 10) {
                    ForEach(folder.apps, id: \.self) { key in
                        let a = apps[key]
                        AppIcon(name: a?.name ?? key, image: model.icon(a?.bundleId))
                            .help(L("%@ · %@ · was on %@", a?.name ?? key, a?.genre ?? L("Unknown category"), a?.location ?? ""))
                            .draggable(key)
                            .contextMenu {
                                Text("Move to…")
                                ForEach(Array(model.folders.enumerated()), id: \.element.id) { j, f in
                                    if j != index { Button(f.name) { model.move(key, to: j); model.notify(L("Moved “%@” to “%@”", a?.name ?? key, f.name)) } }
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
