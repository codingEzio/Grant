# Existing Setup authorization implementation

Two source files are byte-identical snapshots of the original Setup tool. The reference-only admin_authorize.m generalizes one SSH example account label; provenance.json records both hashes.
`provenance.json` records source commit, clean-path status and SHA-256.
Setup remains the owner of the installed `admin_authorize` tool.

`admin_authorize.m` is reference source only. Its local/remote sudo command runner
is not linked into Grant's reference app. Its included/excluded rows describe
the requested change; they do not sandbox the command's possible effects.

`Sources/App/SetupReference.m` compiles the original UI unchanged, always calls
it with `preview=YES`, supplies synthetic original-format request rows, and
disables password entry before presenting the window. For offscreen rendering,
only window ordering/activation is substituted. The historical English copy is
retained; Grant's entry-point copy is translated in all three languages.

```sh
./grant build
./grant original          # actual native UI; no command runner
./grant render-original   # light/dark native renders without showing a window
```

The owner confirmed authorship and authorized MIT on 2026-10-26 for exactly the
three source files listed in provenance.json. Keep their original source/hash
attribution and the included [MIT license](LICENSE). This does not license the
Setup repository, its other files, history or data, and does not authorize an
upload or system activation. No Setup migration is implied.

For source-only compilation use `./grant public-build`; the preview commands above require a separately signed candidate and are not exercised by public preparation.

简体中文：保留 Setup 原码与来源哈希；仅 UI 编译到预览，禁用密码输入。
原版命令执行代码仅供阅读；未替换正在使用的 Setup 工具。

繁體中文：保留 Setup 原始碼與來源雜湊；僅 UI 編譯至預覽，停用密碼輸入。
原版命令執行程式碼僅供閱讀；未取代正在使用的 Setup 工具。
