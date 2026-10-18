# Homescreen Organizer（主畫面整理）

在 Mac 上透過 USB 自動分類、整理 iPhone 主畫面。原生 SwiftUI App，下載約 1 MB。

下載：https://limcheyyong.github.io/iphone-homescreen-swift/ （英文，預設）・https://limcheyyong.github.io/iphone-homescreen-swift/zh.html （中文）

## 語言
- App 預設英文，系統語言是中文時顯示繁體中文。原始碼裡的字串就是英文 key，中文翻譯在 `Resources/zh-Hant.lproj/Localizable.strings`；寫進手機的資料夾名稱也跟著語言。
- 新增文字時：Text / Button 等 SwiftUI 的字串字面值會自動翻譯；其他字串用 `L("...")`，並把翻譯加進 `Localizable.strings`。

## 需求
- macOS 13 以上（Apple 晶片或 Intel）
- iPhone 用 USB 線接上 Mac、已解鎖，並對這台 Mac 點過「信任」

## 開發
只需要 Command Line Tools，不需要完整的 Xcode。
```bash
swift build                          # 編譯
swift run Homescreen                 # 開啟 App
swift run Homescreen --probe         # 只測連線：讀取並列出主畫面，不改手機
./scripts/package.sh                 # 打包 dist/Homescreen Organizer.app 和 dist/Homescreen-mac.dmg（universal）
```

流程：連接 iPhone → 看目前排版、按「依類型分類」產生新排版並微調 → 套用到 iPhone。讀取時會自動備份到 `~/Library/Application Support/Homescreen Organizer/backups`，隨時能「還原原本排版」。

## 結構
- `Sources/Homescreen/MobileDevice.swift`：USB 連線，透過 Apple 的 MobileDevice.framework（Finder 用的同一套），配對和加密都由系統處理
- `Sources/Homescreen/Layout.swift`：排版邏輯（攤平、依計畫重建、保留指定頁面、小工具依實際佔格分頁，絕不遺漏 icon）
- `Sources/Homescreen/Classify.swift`：用 Apple 公開的 iTunes Lookup API 查類型，依類型分組
- `Sources/Homescreen/Model.swift`：讀取、分類、套用、還原的流程與狀態
- `Sources/Homescreen/Views.swift`、`App.swift`：SwiftUI 介面
- `docs/`：下載頁（GitHub Pages），`index.html` 英文、`zh.html` 中文

## 發佈
1. 修改 `VERSION`，例如 `0.1.1`
2. `git commit -am "v0.1.1" && git tag v0.1.1 && git push && git push --tags`
3. GitHub Actions 會打包 DMG 並發佈到 Releases，下載頁的按鈕會自動指向最新版

目前用的是 ad-hoc 簽章（沒有 Apple Developer ID），使用者第一次打開時要到「系統設定 → 隱私權與安全性」按「強制打開」。

## 已知限制
- 用的是 iOS 與 macOS 的非公開介面，系統改版可能失效
- 小工具（widget）不會移動；Dock 不會改動

## 贊助
這個工具免費使用，覺得有幫助的話歡迎請我喝杯咖啡：

<a href="https://www.buymeacoffee.com/jayden_lim" target="_blank"><img src="https://cdn.buymeacoffee.com/buttons/v2/default-yellow.png" alt="Buy Me a Coffee" style="height: 60px !important;width: 217px !important;" ></a>
