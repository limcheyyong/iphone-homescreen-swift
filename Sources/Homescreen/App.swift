import SwiftUI

@main
enum Entry {
    static func main() {
        if CommandLine.arguments.contains("--probe") { Probe.run() } else { HomescreenApp.main() }
    }
}

struct HomescreenApp: App {
    @NSApplicationDelegateAdaptor private var delegate: AppDelegate
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup("主畫面整理") {
            ContentView().environmentObject(model).frame(minWidth: 900, minHeight: 600)
        }
        .defaultSize(width: 1200, height: 800)
        .commands { CommandGroup(replacing: .newItem) {} }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)  // also when run unbundled with `swift run`
        NSApp.activate(ignoringOtherApps: true)
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

/// `Homescreen --probe`: read the phone and print the home screen, without changing anything.
enum Probe {
    static func run() {
        DeviceWatcher.shared.start()
        CFRunLoopRunInMode(.defaultMode, 2, false)  // let device notifications arrive
        guard let ref = DeviceWatcher.shared.devices.values.first else { print("沒偵測到 iPhone：請用 USB 線連接並解鎖手機"); exit(1) }
        Task {
            do {
                let (st, name) = try await Device.session(ref) { d in (try d.iconState(), d.name) }
                print("裝置：\(name ?? "?")")
                for p in Layout.pages(st) {
                    print("\n\(p.title)")
                    for t in p.tiles {
                        switch t.kind {
                        case .folder: print("  [\(t.name)] " + t.apps.map(\.name).joined(separator: "、"))
                        case .widget: print("  〔小工具・\(t.size)〕\(t.name)")
                        case .app: print("  \(t.name)")
                        }
                    }
                }
                exit(0)
            } catch {
                print("錯誤：\(error.localizedDescription)")
                exit(1)
            }
        }
        RunLoop.main.run()
    }
}
