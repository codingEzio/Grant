# Grant

<p><img src="Resources/README-icon.svg" width="96" height="96" alt="Grant"></p>

macOS 原生授权样式。**0.2.3 · 本机候选**。目标是让使用系统授权流程的 App
采用统一样式；本仓库提供设置 App、授权插件及受保护系统安装器的源码。 App
安装与系统启用分开，`grant status` 读取当前状态。

[English](README.md) · [简体中文](README.zh-Hans.md) · [繁體中文](README.zh-Hant.md) · [日本語](README.ja.md) · [한국어](README.ko.md) · [Español](README.es.md)

四个字体文件均须单独获取；Google Fonts 和 Compact 0.1.1 均固定哈希。首次获取需要联网。含字体成品的品牌与商标权利尚未验证。

## 仅源码准备

此纯源码库已获准公开；含字体成品的权利、签名、安装和实际系统授权仍未验证。需要 Apple Silicon、macOS 27、含 macOS 27 SDK／`actool` 的 Xcode、Deno 2、Python 3；导出另需 Git。未签名构建仅使用本机源码和 Apple 框架，取得字体后无需登录账号。


执行源码检查或构建前，先运行 `python3 scripts/get_fonts.py` 获取全部固定版本的字体。程序会校验压缩包及字体哈希；若已有文件不符，会保留并拒绝继续。此源码库不含字体文件，重新分发前须审查其组件权利。

```sh
./grant check-source
./grant public-build
```

导出和构建要求所选暂存内容及工作文件均符合审查 pin。审查变更并暂存具名文件后，运行 `python3 scripts/review_source.py --reviewed`，暂存更新的辅助脚本和 pin 文件，再运行 `./grant public-check`。构建使用独立快照；重复构建会验证现有结果，不覆盖。 桌面替换要求候选与已安装应用满足相同的指定要求和精确叶证书；临时签名会被拒绝。

`check-source` 验证固定字体／参考源码哈希及三语完整性，再执行现有的纯凭证上下文／响应、策略、模拟终端和隔离设置测试。编译／签名分支测试使用记录替身工具。不加载授权插件、不启动 Grant、不请求授权、不执行真实 sudo、不安装终端集成，也不检查已安装账号。

`public-build` 使用 `scripts/build.sh --unsigned`，仅写入已忽略的本机候选，封存至 `Local/public-build/<source-seal>/`。它比对权限、哈希、现有标识符与资源，并确认 Mach-O 不含代码签名。重跑会在隔离环境重建并比对现有候选，不覆盖。中间产物与独立的 `Local/latest-unsigned-build.json` 不会取代签名版 `Local/latest-build.json`。未签名产物不生成系统接入／还原命令入口。这些产物供源码检查，不可作为已验收的授权组件安装或启动。

维护者明确暂存文件后，执行 `./grant public-check`、`./grant public-prepare`，仅审查／导出 `public-source.json` 指定的 Git 暂存内容。不可覆盖的源码收据记录模式、大小和 SHA-256；重跑精确读回。排除 `.git`、签名设置、内部任务／历史及本机证据。导出回归命令为 `deno test --allow-read --allow-write --allow-run=git,deno Tests/public_prepare_test.ts`。有限扫描不能证明全部历史或二进制内容安全；发布前需另行审查。

默认 `./grant build` 仍是独立的签名流程。优先使用 `GRANT_SIGN_IDENTITY`、`GRANT_PLUGIN_SIGN_IDENTITY`；缺少值时读取已忽略 `Local/signing.json` 的 `appIdentity`／`pluginIdentity`。两者均必填，失败不降级为未签名。请在自己的 Mac 配置身份后再使用。本机维护副本在私人设置文件保留原默认值；导出不包含签名身份或密钥。签名、安装、授权及实机验收均不属于本次准备。

自有代码／文档采用 [MIT](LICENSE)；两份原创图标 SVG 采用 [CC BY 4.0](ARTWORK-LICENSE.md)。主人于 2026-10-26 确认三份列明的 `References/Setup/` 参考程序均为自有代码，并授权采用 MIT；保留[来源署名与许可](References/Setup/README.md)。不涵盖 Setup 整库、其他文件、历史或数据。字体保留原始授权和声明，详见[依赖说明](DEPENDENCIES.md)。源码已获准公开；含字体成品的权利、签名、安装及实际系统授权仍未验证。

已有五套选定构图：**Paper Punch** 使用高挑窄体大标题与暖白／炭黑表面； **Dot
Instrument** 使用真实点阵字体、细边框与小红色信号；**Swiss Signal**
使用宽厚字体、方正轮廓与钴蓝色。**Hard Edge** 使用黄黑／炭黑表面、硬边框与
错位黑色阴影；**Blueprint**
使用模板切割字体、切角边框、括号角与橙色按钮。卡片保留明确操作标题、一行有用上下文、密码框
与操作。标题按实际字形尺寸适配单行。五套均支持系统、浅色、深色，以及简体中文、
繁体中文和英文。凭证卡片为440 × 184pt，272 × 28pt 密码条右端提供回车提交
按钮。焦点使用主题强调色，标题字体和布局保留。取消收为角落小图标，保留 Escape。样式、外观、语言与
字体模式移至「设置」（底部小滑杆或 Cmd+,），「字体」从设置进入。
配色与字体回退顺序位于 `Resources/Styles/`。 Grant 与 Nothing、Apple
均无隶属关系。

凭证卡片右下角的小滑杆提供六套主题、系统／浅色／深色、主题／系统字体模式
和三种语言。快捷选择由已安装的用户 App 保存并读回，再更新当前卡片；凭证
不会传给设置 App。字体及全部设置进入完整 App，真实菜单文字明确提示先结束
本次请求。完整设置包含受保护的 Apple 恢复／接入流程。Setup 原版已加入实际样式，原始参考实现仍保留。

## 终端 sudo 与 Setup 原版

`Setup 原版` 是第六套可选的实际授权样式，保留旧 Setup 的页头、七行表格、原生密码框与继续／取消按钮。尺寸为 560 × 460pt；系统账户框展开时增加 36pt。另外五套仍保持紧凑尺寸。原始参考实现继续保留。实际授权展示真实认证上下文，不编造 Setup 操作信息。Grant 全局启用时，系统插件须先更新至至少 0.2.3 才能选择原版，避免旧插件收到不支持的样式。

设置中的「终端 sudo 使用 Grant」保存为 `terminalSudo`，默认 true。Setup 的 zsh 启动配置加载已安装 App 内的 `grant_shell.zsh`。已有标签页运行 `source ~/.zshrc`，或新开标签页。本机交互式 zsh 且输入／输出均连接终端时，函数才添加 sudo 官方 `-A`／`SUDO_ASKPASS` 接口。明确指定 `-A`、`-S`、`-n`，已有 `SUDO_ASKPASS`、未知选项、SSH、tmux/screen、脚本保持原认证方式；`command sudo` 与 `/usr/bin/sudo` 直接绕过函数。调用账户必须是当前本机控制台用户。验证、重试、命令执行和密码缓存仍由 sudo 控制；缓存有效或 NOPASSWD 时不会弹密码框。

`grant request-sudo` 为一次无害的 `/usr/bin/true` 请求忽略已有缓存，专门检查真实窗口。助手将一条密码响应直接交给真正 sudo 父进程的管道，取消输出零字节，CLI 不接收或保存密码。支持 1–255 个 UTF-8 字节，不含 NUL／回车／换行；仅显式擦除自己的可变传输缓冲区，不承诺擦除 AppKit 的所有内部副本。不支持的输入请使用原认证方式。助手在提交前复查普通用户身份、控制台用户、sudo 父进程路径／启动时间与输出管道；父进程退出或用户会话变化时取消。

这是可关闭的终端接入，不修改 PAM／sudoers，也不新增常驻服务。登录、FileVault、Keychain 和 LocalAuthentication 仍是独立路径。实际 iTerm2 验收、系统插件版本与安装状态见工作记录及 `grant status`；渲染夹具不能证明密码认证或命令执行成功。

## 安装与切换

```sh
./grant build
./grant install-app
grant settings
grant theme blueprint
grant theme hard-edge
grant status
```

安装位置为 `~/Applications/Grant.app`，短命令位于 `~/.local/bin/grant`。 用
Spotlight 或 Finder 打开 Grant 即进入设置，或直接运行主题短命令。
设置自动保存读回，CLI 修改会刷新已打开的 App。界面示例仍禁用密码输入。
不会新增登录启动项或后台常驻服务。

在设置中点「接入系统授权…」，或运行 `grant install-system`。Terminal 请求管理员
授权后，安装器先恢复精确的原始系统策略，再替换未启用的自有插件与隔离探测项，
并发起真实隔离授权请求。只有请求成功才启用共用规则；取消或失败时维持原始系统
策略，不声称恢复先前的 Grant 规则。收据会显示 `grant restore-system <id>`。

接入前，外观保存在 `~/Library/Application Support/Grant/`；接入后，App 与 CLI
共用
`/Library/Application Support/Grant/Preferences/settings.json`。文件由你拥有，
供系统宿主读取，仅含外观，绝不含凭证。每次授权重新读取；外观文件损坏或无法读取
时使用 root 配置／随附默认值，不绕过实际认证。设置 App 原生运行；本机安装入口和
CLI 依赖当前 Deno 与项目目录，移动项目后需重新安装入口。

## 本机预览

需要 macOS 27、Apple Silicon、Xcode、Deno、Python 3。预览无需联网、账号、
服务、登录启动项或真实凭证，也不会下载套件。

```sh
./grant build
./grant check
./grant preview
./grant render
./grant plan
```

`script/build_and_run.sh` 与 Codex Run 按钮先构建、校验，再重开候选。产物留在
已忽略的 `Local/`。签名身份采用上文的环境变量／私人配置，不分发身份，失败不会暗中回退。开发签名不证明公证或系统加载。
预览禁用凭证输入，仅保存样式、外观、标题字体与语言，保存后读回核对。
授权、取消按钮显示明确的模拟结果，详情弹层展示示例 Setup 请求的上下文；
Return、Escape 对应相同的预览操作。旧 `nothing` 偏好先备份原始文件，再迁移到
Paper Punch，旧 `module` 迁移为 Dot Instrument，旧 `dots` 模式迁移为主题模式，
保留字体、外观和语言选择。预览 CLI 路径是示例资料，不会冒充真实系统请求的来源。

## 主题字体与回退

「字体」面板可设置主题通用、仅浅色、仅深色的首选字体与有序回退。
此外观的独立设置优先，重置后恢复继承；Theme／System 模式、缺失字体与实际 Core
Text 字形来源会明确显示。完整名称见[字体说明](docs/TYPOGRAPHY.zh-Hans.md)。

- Paper Punch：`Impact` → `AvenirNextCondensed-Heavy` → `@system-condensed`。
- Dot Instrument：本机可选的 `DotoMod800ZhRefined` → 随附 `Doto` 800 → 随附
  `DeparturePixelZhCompact-Regular` → `@system-mono`。
- Swiss Signal：`HelveticaNeue-Bold` → `@system`。
- Hard Edge：`BlackOpsOne-Regular` → `Impact` → `@system-condensed`。
- Blueprint：`SairaStencilOne-Regular` → `DeparturePixelZhCompact-Regular` →
  `@system-condensed`。

各栈始终保留系统最终回退，包含平台中文和 Emoji。缺失字体或字形会继续尝试后续
选择。可选个人／系统字体文件未打包，App 运行时不会下载或安装字体。构建后随附的 Compact 包含
完整来源与许可，Doto 随附 OFL 许可。

Black Ops One 与 Saira Stencil One 随附固定版本的官方字体文件及原始 OFL 许可，
无需安装字体。

## 真实授权

现有 [Setup 原版源码](References/Setup/README.md) 已保留。`./grant original` 或
候选预览的「打开现有 Setup 界面」可查看原生原版，使用示例请求并禁用密码输入；
`./grant render-original` 可生成浅、深色原生图。原版英文保留用于对照。
命令执行代码仅供阅读；未替换正在使用的 Setup 工具。
swiftDialog 仅用于设计参考，未随附其代码或运行依赖。

授权插件通过 Apple 公开接口运行于非特权进程，并自行显示紧凑的无边框 `NSPanel`，
不嵌入 Apple 外层窗口的系统视图。凭证视图为 440 × 184pt，密码框取得焦点，
Return 提交、Escape 取消；更改账户时，面板按需增高 36pt。若调用方提供用户名，
优先用作账户；控制台账户仅作可编辑的便捷预填。提示文字可能缺失，因此使用通用
管理员访问标题，不编造电源设置等操作。密码作为不可提取凭证交给 Apple 特权验证器；
Grant 不保存或记录密码。预览不会发起授权请求。

安装前阅读[接入与恢复说明](docs/INTEGRATION.zh-Hans.md)。当前候选先恢复精确的原始
系统策略，再替换未启用的插件与隔离探测项；只有真实隔离授权成功才启用共用规则。
0.2.3 原版样式与终端接入须各自验收；登录、FileVault、Keychain 与 Touch ID 不由构建结果推断覆盖。

`grant request` 请求 macOS 评估 `system.privilege.admin`，不执行特权操作，可取消；
`grant probe` 请求隔离测试规则，`grant preview` 是禁用输入的演示夹具。0.2.3 新增路径须单独完成实机验收。历史 0.1.1 内嵌视图与 394 点宿主尺寸记录仅描述旧实现，
不能当作当前面板的验收结果。用 `grant status` 查看已安装策略；参与 App、错误密码
重试与 Touch ID 仍需分别验收。
