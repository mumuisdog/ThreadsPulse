# ThreadsPulse

[English](README.md) | **繁體中文**

Threads（`com.burbn.barcelona`）的 iOS 增強插件。目前版本：**1.20.2**

不需要越獄：用 GitHub Actions 就能編譯出注入好的 Threads IPA，再用自己的簽名工具安裝。

## 功能

| 分類 | 功能 | 說明 |
|---|---|---|
| 廣告與隱私 | 去除廣告 | 隱藏動態裡的贊助串文 |
| | 停用截圖偵測 | 截圖或錄影時，Threads 不會偵測到 |
| | 阻擋分析回傳 | 不讓 Threads 回傳你看了什麼、停留多久、點了什麼等使用紀錄。推薦內容可能會變得比較不準（預設關閉） |
| | 移除網址追蹤碼 | 複製／分享／開啟連結時清除 `xmt`、`igshid`、`utm_*` 等參數，並解開 `l.threads.com` 跳轉 |
| 下載 | 下載按鈕 | 串文右上角 ↓：點一下下載整則串文的圖片和影片；長按可選只下載圖片或只下載影片 |
| | 下載原始尺寸圖片 | 從 threads.com 網頁版取得原始解析度；WebP 會轉成 JPEG 存入照片 |
| | 下載原始尺寸大頭貼 | 在個人檔案長按大頭貼，或點開全螢幕後按 ↓ |
| 影片 | 停用自動播放 | 滑動態時影片不會自動播放，點一下才開始播放 |
| | 預設播放速度 | 1x／1.25x／1.5x／2x |
| 首頁動態 | 保留動態位置 | 從背景回到 Threads 時，首頁不重新整理、不跳回最上方；保留時間可選 10 分鐘／30 分鐘／不限時間 |
| | 停用下拉重新整理 | 在首頁最上方往下拉不會重新整理 |
| | 點首頁標籤：不捲回頂端 | 滑到首頁下方時點首頁標籤，停在原本的位置 |
| | 點首頁標籤：不重新整理 | 已在首頁最上方時點首頁標籤，不會載入新串文 |
| 隱藏項目 | 隱藏追蹤對象建議 | 不再自動跳出「追蹤對象建議」視窗 |
| | 隱藏 Instagram 按鈕 | 隱藏個人檔案上方的 Instagram 按鈕 |
| | 隱藏動態裡的推薦帳號 | 隱藏動態裡的推薦帳號卡片，以及個人檔案頁和追蹤某人後出現的「為你推薦」 |
| 連結 | 偵測剪貼簿連結 | 回到 Threads 或切換帳號時，偵測剪貼簿裡的 Threads 連結並開啟該串文 |
| | 偵測到連結時 | 「詢問」顯示提示（可選上方／中間／下方）；「自動開啟」直接跳轉 |
| | 使用外部瀏覽器開啟連結 | 串文和個人簡介裡的連結改用 Safari（或你的預設瀏覽器）開啟，不用 App 內建瀏覽器。Threads 的連結仍在 App 裡開啟 |
| 介面與互動 | 主題配色 | 插件的主題色：珊瑚／海洋／薄荷／薰衣草／櫻花／琥珀 |
| | 按讚確認 | 按愛心前先確認，避免誤按 |
| | 串文時間格式 | 相對時間／日期時間／含秒 |
| | 固定底部標籤列 | 滑動時底部功能標籤列不會自動隱藏 |
| | 複製個人檔案資訊 | 在個人檔案長按姓名、用戶名稱、個人簡介或大頭貼，可複製姓名、用戶名稱或個人簡介 |
| | 長按首頁標籤開啟設定 | 長按底部的首頁標籤時，改為開啟 ThreadsPulse 設定（預設關閉） |
| 備份 | 匯出／匯入設定 | JSON 檔 |
| 進階 | 除錯提示 | 功能有在運作時顯示 `[TP]` 提示，Threads 更新後可判斷哪一項失效 |
| | 側載相容修正 | 重新簽名後保持登入，並讓 App 群組資料正常讀寫；用原本簽名（越獄）時自動停用 |

**設定入口**：Threads「設定」頁右上角「〰 Pulse」，任何畫面三指長按 1 秒，或（開啟「長按首頁標籤開啟設定」後）長按首頁標籤。

---

## 用 GitHub Actions 自己編譯 IPA（免越獄，推薦）

### 事前準備

1. **已解密的 Threads IPA**：這個專案**不提供** Threads 本體，請自行準備。App Store 下載的版本是加密的，不能直接用；必須是已解密的 IPA。
2. **IPA 的直接下載網址**：把 IPA 放到可以直接下載的地方（例如 Dropbox 連結結尾改成 `?dl=1`），用瀏覽器開啟網址時要直接開始下載，而不是顯示網頁。
3. **簽名工具**：用來把產出的 IPA 安裝到手機，決定你要選哪個版本（見下方）。

### 兩種版本

| 版本 | 適合 | 內容 |
|---|---|---|
| **sideload** | 證書簽名：ESign、Feather、Sideloadly＋付費開發者帳號等 | 保留 Threads 原本的延伸功能（小工具、分享等），並加入「Open in Threads」Safari 延伸功能 |
| **noplugins** | SideStore、AltStore 等**免費 Apple ID** | 移除所有延伸功能。免費帳號無法簽名延伸功能，App ID 數量也有限制 |

**「Open in Threads」Safari 延伸功能**：側載的 Threads 收不到通用連結，在 Safari 點 threads.com 連結只會停在網頁。這個延伸功能會把 threads.com／threads.net 的網址轉成 Threads App 的連結並自動開啟：串文開到該串文、個人檔案開到該個人檔案。
安裝後到 **設定 › App › Safari › 延伸功能**（iOS 17 以前是 **設定 › Safari › 延伸功能**）打開「Open in Threads」，並允許它在 threads.com 上執行。

### 準備你自己的 repo（二選一）

| 方式 | 優點 | 缺點 |
|---|---|---|
| **Fork**（最簡單） | 一鍵建立；有新版時按 **Sync fork** 就能同步 | Fork 一定是**公開**的 |
| **Import repository**（私人） | 可以設成**私人**，做出來的 IPA 只有你拿得到 | 有新版時要重新匯入一次 |

- **Fork**：在本專案頁面右上角按 **Fork** → **Create fork**。
  > **公開 repo 的 Artifacts，任何登入 GitHub 的人都能下載**，而做出來的 IPA 含有 Threads 本體。用 Fork 的話，請把 IPA 網址存成 Secret（見下方），並在下載完 IPA 後，到該次執行頁面刪除 Artifact。
- **Import repository**：GitHub 右上角 **＋** → **Import repository**，**Your old repository's clone URL** 貼上本專案網址，**Privacy** 選 **Private** → **Begin import**。
  > 私人 repo 的 Actions 有每月免費分鐘數限制（macOS 機器分鐘數以 10 倍計算），一次編譯大約 5～10 分鐘。

### 編譯步驟

1. 進入你的 repo → **Actions** 分頁。Fork 的 repo 要先按「I understand my workflows, go ahead and enable them」。
2. （建議）把 IPA 網址存成 Secret：**Settings → Secrets and variables → Actions → New repository secret**，名稱填 `DECRYPTED_IPA_URL`，值填 IPA 網址。
3. 左側選 **Build IPA** → 右側 **Run workflow**：
   - **ipa_url**：IPA 網址。已設定 Secret 就留空。
   - **variant**：`both`（兩種都產出，預設）、`sideload`、`noplugins`。
4. 按 **Run workflow**，約 5～10 分鐘完成。
5. 點進該次執行，頁面最下方 **Artifacts** 下載 `Threads_<版本>_Pulse_<版本>_sideload` 或 `…_noplugins`，解壓後就是 IPA。
6. 用你的簽名工具安裝。Artifact 會在 3 天後自動刪除。

**常見錯誤**

| 錯誤訊息 | 原因 |
|---|---|
| 下載的檔案不是 IPA | 網址開啟的是網頁，不是直接下載 |
| 這個 IPA 尚未解密 | 用的是 App Store 加密版本，請換成已解密的 IPA |
| 執行檔的 header 空間不足 | 極少見；請回報 Threads 版本 |

> 請不要把產出的 IPA 上傳到公開的 Release 或任何公開位置。

---

## 其他編譯方式

### GitHub Actions：只編譯插件（Build）

推送到 `main`／`master`、開 Pull Request，或在 Actions 選 **Build** → **Run workflow**，會產出：

| 檔案 | 用途 |
|---|---|
| `ThreadsPulse_TrollFools_<版本>.zip` | TrollFools 或自行注入用：`ThreadsPulse.dylib`、`ThreadsPulse.bundle`（Safari 延伸功能只放在 sideload 版 IPA） |
| `ThreadsPulse_rootless_<版本>.deb` | 無根越獄（Dopamine／palera1n rootless） |
| `ThreadsPulse_rootful_<版本>.deb` | 有根越獄 |
| `ThreadsPulse_roothide_<版本>.deb` | Roothide 越獄（Dopamine roothide、Bootstrap） |

推送 `v` 開頭的標籤會自動建立 Release 並附上這四個檔案（不含 Threads 本體）：

```bash
git tag v1.20.2
git push origin v1.20.2
```

### 本機編譯

需要 [Theos](https://theos.dev)（macOS 或 Linux 皆可）。

```bash
export THEOS=~/theos
make FINALPACKAGE=1            # 只產生 dylib：.theos/obj/ThreadsPulse.dylib
make package FINALPACKAGE=1    # 產生 .deb（越獄用）
make -C OpenThreadsSafariExtension FINALPACKAGE=1   # Safari 延伸功能 → OpenThreadsSafariExtension/.theos/obj/

# 注入已解密的 IPA（只需要 Python 3 與 zip / unzip）
BUNDLE="layout/Library/Application Support/ThreadsPulse/ThreadsPulse.bundle"
# sideload 版
python3 scripts/inject_ipa.py -i Threads.ipa -d .theos/obj/ThreadsPulse.dylib -b "$BUNDLE" \
  --appex OpenThreadsSafariExtension/.theos/obj/OpenThreadsSafariExtension.appex -o sideload.ipa
# noplugins 版
python3 scripts/inject_ipa.py -i Threads.ipa -d .theos/obj/ThreadsPulse.dylib -b "$BUNDLE" \
  --no-plugins -o noplugins.ipa
```

- 無根越獄：把 `Makefile` 裡 `THEOS_PACKAGE_SCHEME = rootless` 取消註解。
- 使用 Logos `internal` generator，以 ObjC runtime 直接 hook，**不依賴 CydiaSubstrate／ElleKit**，注入 IPA 時不需要另外附上。
- 版本號只在 `TPVersion.h` 定義（`ThreadsPulse.bundle/Info.plist` 請一併更新）；編譯用的 iOS SDK 與最低支援版本在 workflow 的 `SDK_VERSION`、`MIN_IOS`。

### `inject_ipa.py` 做了什麼

1. 解開 IPA，把 `ThreadsPulse.dylib` 放進 `Threads.app/Frameworks/`、`ThreadsPulse.bundle` 放進 `Threads.app/`。
2. 在 Threads 主程式加入一個 `LC_LOAD_DYLIB` 載入指令（`@executable_path/Frameworks/ThreadsPulse.dylib`），已經有就略過。
3. 檢查是否已解密（`LC_ENCRYPTION_INFO_64` 的 `cryptid`），未解密會直接停止。
4. `--appex`：把延伸功能放進 `PlugIns/`（會去掉裡面原有的簽名資料）；`--no-plugins`：移除 `PlugIns/`、`Extensions/`、`Watch/`。
5. 重新壓成**未簽名**的 IPA，由你的簽名工具簽名。

只用 Python 標準函式庫，不需要安裝其他套件。

---

## 專案結構

```
ThreadsPulse/
├── Makefile
├── control                         套件資訊
├── ThreadsPulse.plist              注入目標（com.burbn.barcelona）
├── Tweak.x                         所有 hook（Logos）
├── TPPrefs.h/.m                    設定存取、預設值、匯出匯入
├── TPURLCleaner.h/.m               移除網址追蹤碼
├── TPDownloader.h/.m               網址選擇、下載、WebP→JPEG、診斷報告
├── TPHUD.h/.m                      進度視窗、toast、提示橫幅
├── TPUI.h/.m                       圓形毛玻璃按鈕、長按選單、觸覺回饋
├── TPSettingsViewController.h/.m   設定頁（資料模型在 TP_MODEL_BEGIN～TP_MODEL_END 之間）
├── TPLocalization.h/.m             TPL() 多語系
├── TPSideloadFix.h/.m              側載相容修正（鑰匙圈、App 群組）
├── TPVersion.h                     版本號（只在這裡改）
├── scripts/inject_ipa.py           把插件注入 IPA
├── OpenThreadsSafariExtension/     「Open in Threads」Safari 延伸功能（只放進 sideload 版）
│   ├── OpenInThreadsHandler.m      原生端（只負責讓延伸功能能被載入）
│   └── Resources/                  content.js（網址轉換與跳轉）、manifest.json、圖示
├── .github/
│   ├── actions/setup-theos/        共用：安裝 Theos 與 iOS SDK
│   └── workflows/
│       ├── build.yml               編譯插件（zip／deb）
│       └── build-ipa.yml           編譯並注入 IPA
└── layout/Library/Application Support/ThreadsPulse/ThreadsPulse.bundle/
    ├── Info.plist
    ├── en.lproj/Localizable.strings
    └── zh-Hant.lproj/Localizable.strings
```

## 語系

- 程式裡一律用 `TPL(@"English text")`，**英文原文就是 key**；找不到翻譯時直接顯示英文。
- 依系統語言切換：繁體中文用 `zh-Hant`，其他語言用 `en`。
- 新增語言：複製 `en.lproj` 改名（例如 `ja.lproj`）並翻譯，再到 `Info.plist` 的 `CFBundleLocalizations` 加上語言代碼。

## 實作重點

- **Swift 類別**：以 mangled name hook（例如 `_TtC6BCNUFI12BCNUFIButton`），透過 runtime 讀取 ivar；讀取 Swift enum 記憶體前會先驗證指標與類別，避免閃退。
- **批次下載**：從輪播 cell 的資料模型（`BCNFeedMediaViewModel` → `IGPhoto`／`IGVideo`）讀取全部項目，不受 cell 重用影響。
- **原始圖片／大頭貼**：抓 `https://www.threads.com/t/<code>` 或 `/@<username>` 頁面，從 JSON 候選網址中以檔名比對出最大尺寸。
- **剪貼簿**：先用 `detectPatternsForPatterns:` 判斷有沒有網址（不會跳出貼上詢問），使用者點「開啟」或設為自動開啟時才讀取內容；以 `NSUserActivity`（BrowsingWeb）交給 Threads 自己處理跳轉。
- **切換帳號**：hook `IGAccountSwitcher`，最後一次切換事件後 1.5 秒檢查剪貼簿；從其他 App 回到 Threads 則是 0.8 秒。
- **保留動態位置**：讓 `applicationWillWarmStartWithTimeIntervalSinceBackgrounded:`（首頁與 `BCNAppViewController`）收到 0 秒、回前景前把首頁的 `lastBgTime` 設為現在，並把 `IGFeedRefreshInstructionsStore` 的伺服器門檻拉高到保留時間。
- **下拉重新整理**：在首頁的 `scrollViewDidScroll:` 裡，使用者拖動時不讓位置超過頂端，下拉元件就不會觸發。
- **點首頁標籤**：新版分頁列（`BCNLucentTabBarCoordinator`）重複點選同一分頁時，先判斷首頁是否在頂端，再依開關決定是否讓 Threads 處理這次點擊（`tabBarController:shouldSelectTab:`、`didSelectTab:previousTab:`、`handleTabBarDoubleTap:`）。舊版分頁列（`BCNLegacyTabBarController`）的判斷在 Swift 裡攔不到，改成記下點擊時間，1 秒內攔截首頁的往上捲動與重新整理；這組備援 hook 只在第一次點舊版分頁列時才啟用。
- **固定底部標籤列**：不讓 `BCNLucentTabBarCoordinator` 收到 `scrollViewDidScroll:`／`scrollViewDidEndScrolling:`，並把 iOS 26 的 `tabBarMinimizeBehavior` 設為 never。
- **側載相容修正**：載入時存一筆測試資料到鑰匙圈，讀回系統實際指派的存取群組；Team ID 不是 Meta 的（`MH9GU9K5PX`）才啟用。改寫 App 本身各映像檔（主程式與 `Frameworks/`）符號指標表裡的 `SecItemAdd`／`CopyMatching`／`Update`／`Delete`，把 Threads 指定的群組換成實際可用的群組；`containerURLForSecurityApplicationGroupIdentifier:` 回傳 nil 時改用 `Library/ThreadsPulseAppGroups/<群組>`。Threads 沒有用 iCloud，所以不處理 CloudKit。
- **複製個人檔案資訊**：可複製姓名（`fullNameLabel`）、用戶名稱（`usernameLabel`，不含 `@`）或個人簡介。在 `BCNProfileHeaderView` 的大頭貼、`fullNameLabel`、`usernameLabel`、`IGProfileBioView` 加上長按手勢；個人簡介全文取自 `_fullCollapsibleBioString`（收合時）或 `_stringForView`。功能關閉時手勢不會啟動，Threads 原本的長按照常運作。
- **隱藏 Instagram 按鈕**：在 `BCNProfileViewController` 的 `viewDidLayoutSubviews` 隱藏 `$__lazy_storage_$_appSwitcherButton`（切換到 Instagram 的按鈕），連同只包著它的外層容器一起隱藏。在 stack view 裡會自動靠攏；不在的話，把同一排的其他按鈕用 transform 移過去補位。
- **使用外部瀏覽器開啟連結**：攔截 `BCNLinkHandlerImpl` 的兩個 `handleLinkWithURL:` 方法（ObjC 協定，呼叫走 ObjC 派送）。先解開 `l.threads.com` 跳轉包裝；`threads.net`／`threads.com` 和非網頁連結維持原本行為，其他一律用 `-[UIApplication openURL:]` 開啟（開啟「移除網址追蹤碼」時會一併清掉追蹤參數）。
- **長按首頁標籤開啟設定**：攔截 `-[BCNLucentTabBarCoordinator handleTabBarLongPress:]`。長按一開始落在第一個（首頁）標籤按鈕上時，開啟 ThreadsPulse 設定並吃掉這次手勢的後續；長按其他標籤（例如個人檔案標籤切換帳號）照常運作。
- **阻擋分析回傳**：使用紀錄在收集階段就丟掉（`-[FBAnalyticsCoreLogger _captureAnalyticsEvent:]`、`_captureAnalyticsEventForBatchUpload:`，`_shouldStreamEvent:` 回傳 NO）；之前已存著的紀錄上傳時，改用 Meta 自己的 `FBAnalyticsNoOpNetworkConfigurator` 取代 `IGAnalyticsNetworkConfigurator`，不會發出網路要求。登入、發文、載入動態等正常 API 不經過這裡。
- **停用自動播放**：動態裡的影片滑進畫面時（`-[IGFNFVideoPlayer playWithReason:callsiteContext:]`，原因代碼 1），照常讓 Threads 走完播放流程，介面（包括聲音圖示）才會正常出現，但把底層的 `FNFPlayer` 按住：第一次 `play` 以音量 0 試播，讓 Threads 走到「開始播放」並顯示聲音圖示，接著在第一格暫停（`videoPlayerDidInitialPlay:`）；之後的 `play` / `playWithContext:` 一律忽略。點一下影片（手指幾乎沒移動，所以滑動不算）才放開並讓 `FNFPlayer` 開始播放。其他原因（例如全螢幕）和不在動態裡的影片照常播放。開始播放後同一個播放器不再按住，直到它被停止。單支影片下載改成先從附近的資料物件找網址，沒播放過的影片也能下載。
- **隱藏追蹤對象建議**：`BCNUserRecommendationsViewController` 以彈出方式出現時攔截 `presentViewController:`；推入的頁面不受影響。

## 注意事項

Threads 更新後，部分功能可能會暫時失效（不會閃退）。打開「除錯提示」可以看出是哪一項，歡迎回報。

## 免責聲明

1. 本專案為獨立開發之非官方軟體，與 Meta Platforms, Inc.（以下簡稱「Meta」）及 Apple Inc. 無任何隸屬、合作、授權或背書關係。「Threads」及其相關標誌為 Meta 之商標，本專案使用該名稱僅用於說明相容對象。
2. 本專案不包含、亦不散布 Threads 應用程式或其任何組成部分。使用者應自行合法取得所需檔案，且不得公開散布經修改之應用程式。
3. 修改第三方應用程式可能違反該服務之使用條款，並可能導致帳號遭限制、停用或其他後果，相關風險由使用者自行評估及承擔。
4. 透過本專案下載之內容，其著作權歸原權利人所有。使用者僅得於法律允許之範圍內作個人用途使用，不得侵害他人權利。
5. 本專案依「現狀」提供，不附帶任何明示或默示之擔保。對於因使用或無法使用本專案所生之任何直接、間接、附帶或衍生損害，作者概不負責。
6. 使用者下載、編譯或使用本專案，即視為已閱讀、理解並同意本聲明之全部內容。

## 作者

h4x_0x30vm · [Ko-fi](https://ko-fi.com/mumuisdog)

© 2026 h4x_0x30vm，保留所有權利。
