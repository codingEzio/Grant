# Dependencies and rights

The local Setup reference is pinned by commit and SHA-256 in
`References/Setup/provenance.json`. Only its Cocoa UI is compiled into the
preview-only `GrantSetupReference.app`; sudo/SSH execution code is retained for
reading, not linked. The shared `Setup Original` live theme adapts that pinned
UI layout in GRGrantView; it reuses Grant's native fields and callbacks, never
the old sudo/SSH execution wrapper. No publication license is inferred. swiftDialog is a
read-only design reference, not a bundled or runtime dependency.

简体中文：Setup 原版按提交和哈希保留，原 UI 继续提供参考预览，布局已适配为共用实际样式；没有引入 swiftDialog
依赖。 繁體中文：Setup 原版依提交與雜湊保留，原 UI 繼續提供參考預覽，佈局已適配為共用實際樣式；未引入
swiftDialog 相依套件。

| Component                                                                     | Source/version                                                                                                                                      | Purpose and distribution                                                                                                                      |
| ----------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------- |
| AppKit, SwiftUI, Security, SecurityInterface, CoreText, SystemConfiguration, libproc | Current Xcode macOS SDK; candidate built for arm64/macOS 27 | Native views, plugin interface, local sudo parent/console identity checks. OS/toolchain APIs; not redistributed. |
| Deno                                                                          | Existing local installation                                                                                                                         | Project CLI, policy planning and checks; separately installed, no packages downloaded.                                                        |
| Python 3 / Xcode clang and swiftc                                             | Existing local toolchain                                                                                                                            | Deterministic bundle/resource metadata and native compilation; separately installed.                                                          |
| Doto variable TTF                                                             | Google Fonts commit `9710da1eacb3be272583c3224dcb70f9da6eadbb`                                                                                      | Bundled display font, actual `wght=800`, `ROND=0`; OFL-1.1.                                                                                   |
| DeparturePixelZh Compact                                                      | Separately obtained from the pinned DeparturePixelZh 0.1.1 desktop release using `python3 scripts/get_compact_font.py`, SHA-256 `3e75e623b1ba2c8d7eb52f2ac3ee71c3fbb5c4e0f1426bd34b3c1e071738288b` | Bundled source-derived CJK/Latin pixel fallback; complete OFL/NOTICE/Licenses/provenance under `Resources/Licenses/DeparturePixelZhCompact/`. |
| Impact; Avenir Next Condensed Heavy; Helvetica Neue Bold; DotoMod800ZhRefined | Existing system/user-installed faces; Doto derivatives owned by `X-FontMod`                                                                         | Optional per-theme preferred faces. Their binaries are not copied or redistributed. Missing faces fall through the configured stack.          |
| Pillow, QA only                                                               | Separately installed Python environment with Pillow; optional QA only                                | Optional numbered contact sheet; not bundled or needed to build/run/render the native app. No automatic install.                              |

Doto is reused byte-for-byte from the verified Y-DullWidget asset. Source URL,
commit, byte count and SHA-256 are in `Resources/Licenses/fonts.json`; the
original OFL notice is included. Font payload SHA-256:
`6f4fe7d37853b91df3698daa84cde2dbe1c9695d88c986e6510134910337d426`.

The source repository excludes Compact; the explicit retrieval command verifies both the desktop ZIP and TTF hashes. Builds require the verified font and bundle it with its notices. Availability and hash identity do not establish rights for every included glyph or logo. Each candidate bundle includes the font and its license. CoreText creates the
display font directly from its bundled file descriptor, with explicit variation
axes; no OS-installed Doto copy or synthesized bold is required. Grant display
roles use theme-specific fonts. Ordered per-glyph fallback now includes
source-derived Compact; Core Text evidence identifies the actual file and
variations. System mode bypasses the theme stack. Functional controls use system
sans, technical values use system monospace; control semantics remain native.
The selected Paper Punch, Dot Instrument, Swiss Signal, Hard Edge and Blueprint
layouts are AppKit drawing and native controls, with no raster UI dependency.
Per-appearance font overrides retain the same fallback and rights boundaries.
See `docs/TYPOGRAPHY.md` for exact names and settings.

Project-owned Grant code/documentation is MIT under LICENSE. The owner separately authorized MIT for exactly the three original `References/Setup/` source files on 2026-10-26; their original source hashes, attribution and subtree LICENSE are retained. Other Setup files/history/data are outside this grant. Only the two original deterministic icon SVGs are CC BY 4.0 under ARTWORK-LICENSE.md. Fonts retain their original licenses. Source-only publication is authorized; font-containing products require separate brand and trademark rights review. Signing, installation and real system authorization remain unverified. No Nothing logos, Apple font binaries or branding license are included.

For a QA board, use `./grant contacts /absolute/path/to/python3` with the
existing Python-with-Pillow runtime returned by Codex workspace dependencies.
The default shell Python is not assumed to contain Pillow. Original native PNGs
are retained.

相依与授权：Doto 来自固定版本的 Google Fonts，随附原始 OFL-1.1
许可证与散列记录。 字体从候选 App/插件自身的文件加载，Compact
提供中文回退。主题可选本机个人字体，
缺失时按顺序回退；操作控件保留系统字体。构建和预览不联网。自有代码采用 MIT；三份指定参考源码已获 MIT 授权；仅源码获准公开，含字体成品的品牌及商标权利尚未验证。

相依與授權：Doto 來自固定版本的 Google Fonts，隨附原始 OFL-1.1 授權與雜湊記錄。
字體由候選 App/外掛自己的檔案載入，Compact 提供中文後備。主題可選本機個人字體，
缺少時依序使用後備；操作控制項保留系統字體。建置與預覽不連網。自有程式採 MIT；三份指定參考來源已獲 MIT 授權；僅來源獲准公開，含字型成品的品牌及商標權利尚未驗證。

Hard Edge bundles `BlackOpsOne-Regular.ttf` and Blueprint bundles
`SairaStencilOne-Regular.ttf`, copied byte-for-byte from official Google Fonts
commit `b7c8331cf620346575487ef8db0e2c729f014675`. Their original OFL-1.1
notices are under Resources/Licenses; exact URLs, lengths and SHA-256 values are
in Resources/Licenses/fonts.json. They load from the bundle directly, need no
font installation or runtime network, and can be overridden with the existing
ordered font settings. Blueprint’s CJK fallback is the existing bundled Compact
face.

The installed Grant.app embeds the signed UI-only Setup reference. Its generated
GrantSystemSetup.command and GrantSystemRestore.command launch the existing
absolute Deno executable and this local project checkout; the installed native
Settings UI itself runs without Deno. No Deno binary, packages, privileged daemon
or network dependency is bundled. Moving the checkout or Deno requires rebuilding
and reinstalling these local command entries.

已安装 App 随附签署的 Setup UI 参考。系统安装／还原入口依赖现有 Deno 与本机
项目路径；移动路径后须重建安装。设置界面本身不依赖 Deno，不新增常驻提权服务。
已安裝 App 隨附簽署的 Setup UI 參考。系統安裝／還原入口依賴現有 Deno 與本機
專案路徑；移動路徑後須重建安裝。設定介面本身不依賴 Deno，不新增常駐提權服務。

Grant 0.2.0 retains the original deterministic SVG artwork in
Resources/Grant.icon;
Xcode actool compiles its Default/Dark/Mono resources before signing. No external
artwork or new runtime library. At16px its recognition contract is an open lock
with an approval check, distinguished by the warm monochrome field/red accent.
Signed builds require GRANT_PLUGIN_SIGN_IDENTITY and GRANT_SIGN_IDENTITY or their documented fallback in ignored Local/signing.json. The source-only --unsigned branch does not read that file or sign artifacts. No
private key is bundled, exported or uploaded; no signing capability is purchased.

## Source-only tooling and boundaries

`./grant check-source` uses existing Deno policy/mock tests, native context/response fixtures, Python 3 recorder-tool build tests, and read-only pinned-asset/locale checks. No external packages are added. `./grant public-build` reuses the local Xcode clang/swiftc/actool pipeline with identity and ad-hoc code signing disabled. It reads bundle plist/Mach-O metadata and compares resources without loading the plugin or executing the built app. The signed candidate pointer and installed system remain outside this path. Apple Silicon/macOS 27 and an appropriate SDK are required; no Linux build acceptance is claimed.

`Local/signing.json` is private configuration with `appIdentity` and `pluginIdentity` string fields. Explicit corresponding environment values take precedence per field; absence/empty values fail visibly for signed builds. The maintained private checkout preserves its prior configured identities. Source exports do not include that file, private keys, local evidence, author history or credentials.

The source repository excludes all font binaries. Run `python3 scripts/get_fonts.py` to retrieve and verify the pinned inputs before checks or builds; initial retrieval requires network access.
