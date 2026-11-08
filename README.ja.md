# Grant

<p><img src="Resources/README-icon.svg" width="96" height="96" alt="Grant"></p>

[English](README.md) · [简体中文](README.zh-Hans.md) · [繁體中文](README.zh-Hant.md) · [日本語](README.ja.md) · [한국어](README.ko.md) · [Español](README.es.md)

macOS の管理者認証をネイティブな外観で表示する実験的ツールです。現在は0.2.3のローカル候補で、設定アプリ、Authorization Plug-in、保護されたシステム導入手順を含みます。デスクトップアプリの導入とシステム全体での有効化は別です。

4つのフォントは別途取得し、Google Fonts と Compact 0.1.1 のハッシュを固定しています。初回取得にはネットワークが必要です。フォントを含む製品のブランド・商標権は未検証です。

## 外観と操作

Paper Punch、Dot Instrument、Swiss Signal、Hard Edge、Blueprint、Setup Original の6スタイルがあります。紙と縦長見出し、実際のドット書体、青、黄と影、ステンシル、従来の表形式を比較できます。明暗／システム外観、Theme／System フォント、英語・简体中文・繁體中文のUIに対応します。この日本語ファイルは製品説明で、UI言語を追加するものではありません。

通常のカードは440×184pt、元の Setup スタイルは560×460pt。アカウント欄を展開すると36pt増えます。Return で送信、Escape でキャンセルします。プレビューはパスワード入力を無効にした合成例です。実際の認証は得られたコンテキストを使い、架空の操作情報を作りません。

フォントはスタイル／明暗別に優先順を変更し、System モードへ切り替えられます。ビルド済みアプリには必要なDoto、Compact、Black Ops One、Saira Stencil Oneと元の通知を同梱し、フォントを自動導入・取得しません。任意の個人／システム書体は再配布しません。[タイポグラフィ](docs/TYPOGRAPHY.md)を参照してください。

## ソースを確認する

Apple Silicon、macOS27、対応Xcode／SDK・actool、Deno2、Python3が必要です。コンパイルはローカルソースとAppleのフレームワークを使い、パッケージ取得、アカウント、ネットワークは不要です。


ソース検証やビルドの前に `python3 scripts/get_fonts.py` を実行し、固定版フォントをすべて取得してください。アーカイブとフォントのハッシュを検証し、不一致の既存ファイルは保持して処理を中止します。再配布前に権利を確認してください。

```sh
./grant check-source
./grant public-build
./grant public-check
./grant public-prepare
```

エクスポートとビルドは、選択したインデックスと作業ファイルがレビュー済み pin に一致する必要があります。変更をレビューして対象をステージし、`python3 scripts/review_source.py --reviewed` を実行後、更新された補助スクリプトと pin をステージして `./grant public-check` を実行します。ビルドは隔離スナップショットを使い、既存出力を上書きしません。 デスクトップ版の置換には、候補と既存アプリが同じ指定要件と正確な leaf 証明書を満たす必要があります。アドホック署名は拒否されます。 pin 更新では以前のファイルを `scripts/.grant-review-previous-*` に保持し、名前を表示します。中断時は表示されたファイルを確認し、別ファイルを上書きせず欠けた出力を復元してから再実行します。

`check-source` は固定フォント・元参照ファイル・3言語UI、純粋なコンテキスト／応答、ポリシー、模擬シェルと隔離設定を検査します。実際の認証、sudo、プラグイン読み込み、アプリ起動、インストールは行いません。`public-build` は署名なしの別候補を作り、全ファイルのモードとハッシュを読み戻します。システム導入用ランチャーを生成せず、署名済み候補ポインターも変えません。これを認証済みコンポーネントとして導入・起動してはいけません。

`public-check`／`public-prepare` は対象を名前でステージした後に実行し、`public-source.json` の正確なGitインデックスを使います。差のある既存出力を上書きしません。Git履歴、個人署名設定、内部記録は含みません。限定検査は全履歴／バイナリーの安全証明ではありません。

## 署名とシステム導入

署名ビルドは別の `./grant build` です。`GRANT_SIGN_IDENTITY` と `GRANT_PLUGIN_SIGN_IDENTITY`、または個人用 `Local/signing.json` の両識別子が必要です。未設定なら失敗し、署名なしへ黙って切り替えません。`./grant install-app` は所有者用候補を `~/Applications/Grant.app` と `~/.local/bin/grant` に導入します。設定を開く場合は `grant settings`、状態確認は `grant status` です。

システム有効化は別の管理者操作です。先に[導入・復旧手順](docs/INTEGRATION.md)を確認します。インストーラーは正確なApple標準ポリシーを戻し、無効な自前プラグイン／隔離プローブを置き換え、実際の隔離認証が成功して初めて共通ルールを有効にします。キャンセル・失敗は標準ポリシーのままで、以前のGrantルールへ戻したとは主張しません。復旧は発行されたレシートIDを使います。ローカルプレビューは実際の認証や全アプリ対応を証明しません。

## ターミナルのsudo

任意の別ブリッジで、PAM／sudoersの変更やデーモンは追加しません。設定の `terminalSudo` と、利用者が導入したアプリの `grant_shell.zsh` を使います。ローカル・対話的・入出力が端末の呼び出しだけが対象です。明示的な -A／-S／-n、既存SUDO_ASKPASS、未知のオプション、SSH、tmux／screen、スクリプトは通常経路を維持し、`command sudo`／`/usr/bin/sudo` でも回避できます。sudoが検証、再試行、実行、キャッシュを所有します。

ヘルパーは呼び出し元のsudo／開始時刻／コンソール／パイプを確認し、応答を親のパイプへ直接送ります。キャンセルは0バイト。対応はNUL／CR／LFなしの1–255 UTF-8バイトです。可変バッファ以外のAppKitコピーすべてを消去する保証はありません。ログイン、FileVault、Keychain、LocalAuthenticationは別経路で、実機の再試行やTouch IDは別確認です。

## データとライセンス

外観は有効化前は `~/Library/Application Support/Grant/`、有効化後は共有の `/Library/Application Support/Grant/Preferences/settings.json` にあります。見た目だけを保存し、パスワードは保存・記録しません。プラグインは毎回読み、設定が壊れてもAppleの認証を迂回しません。ローカルビルド・検証の出力は除外されたLocalにあります。インストールしたCLI／設定ランチャーはDenoとチェックアウトを使うため、移動時は再導入が必要です。

独自コード・文書は [MIT](LICENSE)。所有者は2026-10-26に3つの元 `References/Setup/` ファイルの著作権を確認し、Grant内でMITを許可しました。[元の出所とライセンス](References/Setup/README.md)を保持します。Setup全体、別ファイル、履歴、データは含みません。2つの独自アイコンSVGは [CC BY4.0](ARTWORK-LICENSE.md)、フォントは元の条件です。候補はソフトウェア／参照元／図稿の通知を同梱します。[依存関係](DEPENDENCIES.md)。ソースのみの公開は承認済みです。フォントを含む製品の権利、署名、インストール、実際のシステム認証は未検証です。
