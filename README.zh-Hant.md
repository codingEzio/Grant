# Grant

<p><img src="Resources/README-icon.svg" width="96" height="96" alt="Grant"></p>

macOS 原生授權樣式。**0.2.3 · 本機候選**。目標是讓使用系統授權流程的 App
採用統一樣式；本庫提供設定 App、授權外掛及受保護系統安裝器的原始碼。 App
安裝與系統啟用分開，`grant status` 讀取目前狀態。

[English](README.md) · [简体中文](README.zh-Hans.md) · [繁體中文](README.zh-Hant.md) · [日本語](README.ja.md) · [한국어](README.ko.md) · [Español](README.es.md)

四個字型檔均須另行取得；Google Fonts 與 Compact 0.1.1 均固定雜湊。首次取得需要網路。含字型成品的品牌與商標權利尚未驗證。

## 僅原始碼準備

此純來源庫已獲准公開；含字型成品的權利、簽署、安裝及實際系統授權仍未驗證。需要 Apple Silicon、macOS 27、含 macOS 27 SDK／`actool` 的 Xcode、Deno 2、Python 3；匯出另需 Git。未簽署建置僅使用本機來源與 Apple 框架，取得字型後不需登入帳號。


執行來源檢查或建置前，先執行 `python3 scripts/get_fonts.py` 取得全部固定版本的字型。程式會校驗壓縮檔及字型雜湊；若既有檔案不符，會保留並拒絕繼續。此來源庫不含字型檔，重新散布前須審查其元件權利。

```sh
./grant check-source
./grant public-build
```

匯出與建置要求所選暫存內容及工作檔均符合審查 pin。審查變更並暫存具名檔案後，執行 `python3 scripts/review_source.py --reviewed`，暫存更新的輔助腳本及 pin 檔，再執行 `./grant public-check`。建置使用隔離快照；重跑會驗證現有結果，不覆寫。 桌面替換要求候選與已安裝 App 符合相同的指定要求及精確葉憑證；臨時簽署會被拒絕。

`check-source` 驗證固定的字型／參考來源雜湊及三語完整性，再執行既有的純憑證上下文／回應、策略、模擬終端與隔離設定測試。編譯／簽名分支測試使用記錄替身工具。不載入授權外掛、不啟動 Grant、不請求授權、不執行真實 sudo、不安裝終端整合，也不檢查已安裝帳號。

`public-build` 使用 `scripts/build.sh --unsigned`，僅寫入已忽略的本機候選，封存至 `Local/public-build/<source-seal>/`。它比對權限、雜湊、既有識別碼與資源，並確認 Mach-O 不含程式簽章。重跑會在隔離環境重建並比對現有候選，不覆寫。中間產物與獨立的 `Local/latest-unsigned-build.json` 不會取代簽署版 `Local/latest-build.json`。未簽署產物不產生系統接入／還原命令入口。這些產物供來源檢查，不可當作已驗收的授權元件安裝或啟動。

維護者明確暫存檔案後，執行 `./grant public-check`、`./grant public-prepare`，僅審查／匯出 `public-source.json` 指定的 Git 暫存內容。不可覆寫的來源收據記錄模式、大小及 SHA-256；重跑精確讀回。排除 `.git`、簽署設定、內部任務／歷史及本機證據。匯出回歸指令為 `deno test --allow-read --allow-write --allow-run=git,deno Tests/public_prepare_test.ts`。有限掃描不證明全部歷史或二進位內容安全；發布前需另行審查。

預設 `./grant build` 仍為獨立的簽署流程。優先使用 `GRANT_SIGN_IDENTITY`、`GRANT_PLUGIN_SIGN_IDENTITY`；缺少值時讀取已忽略 `Local/signing.json` 的 `appIdentity`／`pluginIdentity`。兩者皆必填，失敗不降級為未簽署。請在自己的 Mac 設定身分後再使用。本機維護副本在私人設定檔保留原預設；匯出不包含簽署身分或金鑰。簽署、安裝、授權及實機驗收皆不屬本次準備。

自有程式碼／文件採 [MIT](LICENSE)；兩份原創圖示 SVG 採 [CC BY 4.0](ARTWORK-LICENSE.md)。主人於 2026-10-26 確認三份列名的 `References/Setup/` 參考程式均為自有程式碼，並授權採 MIT；保留[來源署名與授權](References/Setup/README.md)。不涵蓋 Setup 整庫、其他檔案、歷史或資料。字型保留原始授權與通知，詳見[相依說明](DEPENDENCIES.md)。來源已獲准公開；含字型成品的權利、簽署、安裝及實際系統授權仍未驗證。

已有五套選定構圖：**Paper Punch** 使用高挑窄體大標題與暖白／炭黑表面； **Dot
Instrument** 使用真實點陣字體、細邊框與小紅色訊號；**Swiss Signal**
使用寬厚字體、方正輪廓與鈷藍色。**Hard Edge** 使用黃黑／炭黑表面、硬邊框與
錯位黑色陰影；**Blueprint**
使用鏤空字體、切角邊框、括號角與橙色按鈕。卡片保留明確操作標題、一行有用上下文、密碼欄位
與操作。標題依實際字形尺寸適配單行。五套均支援系統、淺色、深色，以及簡體中文、
繁體中文和英文。憑證卡片為440 × 184pt，272 × 28pt 密碼列右端提供 Return 送出
按鈕。焦點使用主題強調色，標題字體和版面保留。取消收為角落小圖示，保留 Escape。樣式、外觀、語言與
字體模式移至「設定」（底部小滑桿或 Cmd+,），「字體」從設定進入。
配色與後備字體順序位於 `Resources/Styles/`。 Grant 與 Nothing、Apple
均無隸屬關係。

憑證卡片右下角的小滑桿提供六套主題、系統／淺色／深色、主題／系統字體模式
和三種語言。快捷選擇由已安裝的使用者 App 儲存並讀回，再更新目前卡片；憑證
不會傳給設定 App。字體及全部設定進入完整 App，實際選單文字明確提示先結束
本次請求。完整設定包含受保護的 Apple 復原／接入流程。Setup 原版已加入實際樣式，原始參考實作仍保留。

## 終端機 sudo 與 Setup 原版

`Setup 原版` 是第六套可選的實際授權樣式，保留舊 Setup 的頁首、七列表格、原生密碼框及繼續／取消按鈕。尺寸為 560 × 460pt；系統帳號框展開時增加 36pt。另外五套仍維持緊湊尺寸。原始參考實作繼續保留。實際授權顯示真實驗證情境，不編造 Setup 操作資訊。Grant 全域啟用時，系統外掛須先更新至至少 0.2.3 才能選擇原版，避免舊外掛收到不支援的樣式。

設定中的「終端機 sudo 使用 Grant」儲存為 `terminalSudo`，預設 true。Setup 的 zsh 啟動設定載入已安裝 App 內的 `grant_shell.zsh`。既有分頁執行 `source ~/.zshrc`，或開啟新分頁。本機互動式 zsh 且輸入／輸出均連接終端機時，函式才加入 sudo 官方 `-A`／`SUDO_ASKPASS` 介面。明確指定 `-A`、`-S`、`-n`，既有 `SUDO_ASKPASS`、未知選項、SSH、tmux/screen、腳本維持原驗證方式；`command sudo` 與 `/usr/bin/sudo` 直接繞過函式。呼叫帳號必須是目前本機控制台使用者。驗證、重試、命令執行及密碼快取仍由 sudo 控制；快取有效或 NOPASSWD 時不會彈出密碼框。

`grant request-sudo` 為一次無害的 `/usr/bin/true` 請求忽略既有快取，專門檢查真實視窗。助手將一條密碼回應直接交給真正 sudo 父行程的管道，取消輸出零位元組，CLI 不接收或儲存密碼。支援 1–255 個 UTF-8 位元組，不含 NUL／歸位／換行；僅明確擦除自己的可變傳輸緩衝區，不承諾擦除 AppKit 的所有內部副本。不支援的輸入請使用原驗證方式。助手在送出前複查一般使用者身分、控制台使用者、sudo 父行程路徑／啟動時間及輸出管道；父行程退出或使用者工作階段變動時取消。

這是可關閉的終端機接入，不修改 PAM／sudoers，也不新增常駐服務。登入、FileVault、Keychain 及 LocalAuthentication 仍是獨立路徑。實際 iTerm2 驗收、系統外掛版本及安裝狀態見工作記錄與 `grant status`；算繪測試圖不能證明密碼驗證或命令執行成功。

## 安裝與切換

```sh
./grant build
./grant install-app
grant settings
grant theme blueprint
grant theme hard-edge
grant status
```

安裝位置為 `~/Applications/Grant.app`，短命令位於 `~/.local/bin/grant`。 用
Spotlight 或 Finder 開啟 Grant 即進入設定，或直接執行主題短命令。
設定自動儲存讀回，CLI 修改會更新已開啟的 App。介面範例仍停用密碼輸入。
不會新增登入啟動項目或背景常駐服務。

在設定中按「接入系統授權…」，或執行 `grant install-system`。Terminal 請求管理員
授權後，安裝器先還原精確的原始系統策略，再替換未啟用的自有外掛與隔離探測項，
並發起真實隔離授權請求。只有請求成功才啟用共用規則；取消或失敗時維持原始系統
策略，不宣稱已還原先前的 Grant 規則。收據會顯示 `grant restore-system <id>`。

接入前，外觀儲存在 `~/Library/Application Support/Grant/`；接入後，App 與 CLI
共用
`/Library/Application Support/Grant/Preferences/settings.json`。檔案由你擁有，
供系統宿主讀取，僅含外觀，絕不含憑證。每次授權重新讀取；外觀檔案損壞或無法讀取
時使用 root 設定／隨附預設值，不繞過實際認證。設定 App 原生執行；本機安裝入口與
CLI 依賴目前 Deno 和專案目錄，移動專案後需重新安裝入口。

## 本機預覽

需要 macOS 27、Apple Silicon、Xcode、Deno、Python 3。預覽無需連網、帳號、
服務、登入啟動項或真實憑證，也不會下載套件。

```sh
./grant build
./grant check
./grant preview
./grant render
./grant plan
```

`script/build_and_run.sh` 與 Codex Run 按鈕先建置、驗證，再重開候選。產物留在
已忽略的 `Local/`。簽署身分採上文的環境變數／私人設定，不散布身分，失敗不會暗中回退。開發簽署不證明公證或系統載入。
預覽停用憑證輸入，僅儲存樣式、外觀、標題字體與語言，儲存後讀回核對。
授權、取消按鈕顯示明確的模擬結果，詳情彈層展示範例 Setup 請求的上下文；
Return、Escape 對應相同的預覽操作。舊 `nothing` 偏好先備份原始檔案，再遷移至
Paper Punch，舊 `module` 遷移為 Dot Instrument，舊 `dots` 模式遷移為主題模式，
保留字體、外觀和語言選擇。預覽 CLI 路徑是範例資料，不會冒充真實系統請求的來源。

## 主題字體與後備

「字體」面板可設定主題通用、僅淺色、僅深色的首選字體與有序後備。
此外觀的獨立設定優先，重設後恢復繼承；Theme／System 模式、缺少字體與實際 Core
Text 字形來源會明確顯示。完整名稱見[字體說明](docs/TYPOGRAPHY.zh-Hant.md)。

- Paper Punch：`Impact` → `AvenirNextCondensed-Heavy` → `@system-condensed`。
- Dot Instrument：本機可選的 `DotoMod800ZhRefined` → 隨附 `Doto` 800 → 隨附
  `DeparturePixelZhCompact-Regular` → `@system-mono`。
- Swiss Signal：`HelveticaNeue-Bold` → `@system`。
- Hard Edge：`BlackOpsOne-Regular` → `Impact` → `@system-condensed`。
- Blueprint：`SairaStencilOne-Regular` → `DeparturePixelZhCompact-Regular` →
  `@system-condensed`。

各順序始終保留系統最終後備，包含平台中文和 Emoji。缺少字體或字形會繼續嘗試後續
選擇。可選個人／系統字體檔案未打包，App 執行時不會下載或安裝字體。建置後隨附的 Compact 包含
完整來源與授權，Doto 隨附 OFL 授權。

Black Ops One 與 Saira Stencil One 隨附固定版本的官方字體檔案及原始 OFL 授權，
無需安裝字體。

## 真實授權

既有 [Setup 原版原始碼](References/Setup/README.md) 已保留。`./grant original`
或 候選預覽的「開啟現有 Setup 介面」可檢視原生原版，使用範例請求並停用密碼輸入；
`./grant render-original` 可產生淺、深色原生圖。原版英文保留供對照。
命令執行程式碼僅供閱讀；未取代正在使用的 Setup 工具。
swiftDialog 僅用於設計參考，未隨附其程式碼或執行相依套件。

授權外掛透過 Apple 公開介面執行於非特權程序，並自行顯示精簡的無邊框 `NSPanel`，
不嵌入 Apple 外層視窗的系統檢視。憑證檢視為 440 × 184pt，密碼欄位取得焦點，
Return 送出、Escape 取消；更改帳號時，面板視需要增高 36pt。若呼叫端提供使用者名稱，
優先用作帳號；主控台帳號僅作可編輯的便利預填。提示文字可能缺少，因此使用通用
管理員存取標題，不編造電源設定等操作。密碼作為不可擷取憑證交給 Apple 特權驗證器；
Grant 不儲存或記錄密碼。預覽不會發起授權請求。

安裝前閱讀[接入與復原說明](docs/INTEGRATION.zh-Hant.md)。目前候選先還原精確的原始
系統策略，再替換未啟用的外掛與隔離探測項；只有真實隔離授權成功才啟用共用規則。
0.2.3 原版樣式及終端機接入須各自驗收；登入、FileVault、Keychain 與 Touch ID 不由建置結果推斷涵蓋。

`grant request` 請求 macOS 評估 `system.privilege.admin`，不執行特權操作，可以取消；
`grant probe` 請求隔離測試規則，`grant preview` 是停用輸入的展示夾具。0.2.3 新增路徑須單獨完成實機驗收。歷史 0.1.1 內嵌檢視與 394 點宿主尺寸紀錄僅描述舊實作，
不能當作目前面板的驗收結果。使用 `grant status` 檢視已安裝策略；參與 App、錯誤密碼
重試與 Touch ID 仍需分別驗收。
