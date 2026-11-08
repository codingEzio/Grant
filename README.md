# Grant

<p><img src="Resources/README-icon.svg" width="96" height="96" alt="Grant"></p>

Native macOS authorization styles. **0.2.3 — local candidate.** The goal is to
style administrator authorization across participating applications. This
revision provides a signed settings app, an Authorization Plug-in and a guarded
system installer. Desktop installation and system activation are separate;
`grant status` reads the current state.

[English](README.md) · [简体中文](README.zh-Hans.md) · [繁體中文](README.zh-Hant.md) · [日本語](README.ja.md) · [한국어](README.ko.md) · [Español](README.es.md)

All four font binaries are obtained separately; Google Fonts inputs and Compact 0.1.1 are hash-pinned. A network connection is required for the initial fetch. Brand and trademark rights for font-containing products remain unverified.

## Source-only preparation

This source-only repository is approved for publication; font-containing products, signing, installation and real system authorization remain unverified. Requires Apple Silicon, macOS 27, Xcode with the macOS 27 SDK and `actool`, Deno 2, Python 3 and Git for export. Compilation uses local sources and Apple frameworks; after the font inputs are fetched, no account is needed for this unsigned path.


Before source checks or builds, run `python3 scripts/get_fonts.py` to fetch all pinned font inputs. The archive and font hashes are checked; an existing mismatched file is retained and rejected. The font binaries are not included in this source repository. Review its component rights before redistribution.

```sh
./grant check-source
./grant public-build
```

`check-source` verifies pinned fonts/reference bytes and three locales, then runs existing pure credential-context/response, policy and mocked shell/settings checks. Compiler/signing branch tests use recorder tools. It does not load the authorization plugin, launch Grant, request authorization, run real sudo, install shell integration or check an installed account.

`public-build` uses `scripts/build.sh --unsigned`, writes only ignored local candidates, and copies a sealed bundle set under `Local/public-build/<source-seal>/`. It verifies modes/hashes, unchanged identities, resources and the absence of Mach-O code signatures. Repeating it validates the existing candidate without rebuilding or overwriting it. Unsigned intermediates and their separate `Local/latest-unsigned-build.json` cannot replace the signed `Local/latest-build.json` pointer. Generated system setup/restore command launchers are omitted from unsigned artifacts. These artifacts are for source inspection; do not install or launch them as accepted authorization components.

To review/export only the explicit Git index selection in `public-source.json`, stage the intended named files, then run `./grant public-check` and `./grant public-prepare`. The immutable source receipt records each file's mode, size and SHA-256. Repeat to read back exact contents. `.git`, signing configuration, internal task/history records and local evidence are excluded. Export regression: `deno test --allow-read --allow-write --allow-run=git,deno Tests/public_prepare_test.ts`. Existing history needs a separate review before publication; bounded scans do not certify all history or binary contents.

Default `./grant build` remains the separate signed workflow. It reads `GRANT_SIGN_IDENTITY` and `GRANT_PLUGIN_SIGN_IDENTITY` first; a missing value falls back to `appIdentity` / `pluginIdentity` in ignored `Local/signing.json`. Both are required and failure never falls back to unsigned signing. Configure identities on your own Mac before using that workflow. The maintained local checkout retains its prior defaults in that private file; no signing identity or key is distributed. App/plugin signing, installation, authorization and live acceptance are separate from this preparation.

Project-owned code/documentation uses [MIT](LICENSE). The two original icon SVGs use [CC BY 4.0](ARTWORK-LICENSE.md). The owner also authorized MIT for the three listed original `References/Setup/` source files on 2026-10-26; retain their [source attribution and license](References/Setup/README.md). This does not license the Setup repository or its other contents. Fonts retain their original licenses and notices. See [dependencies](DEPENDENCIES.md). Source export and successful compilation cover their stated checks; source-only publication is approved; distributing built products requires separate rights review.

Five selected visual families are available: **Paper Punch** has a tall
condensed title and warm paper/charcoal surfaces; **Dot Instrument** uses
authentic dot type, a thin outline and a small red signal; **Swiss Signal** uses
broad heavy type, square geometry and cobalt. **Hard Edge** adds
yellow/charcoal, a rigid frame and an offset black shadow; **Blueprint** adds
stencil type, chamfered outlines, corner brackets and an orange action. The
credential card has one meaningful operation title, one useful context line, the
password field and its actions. Titles fit their actual glyph metrics on one
line. Each supports light, dark and system appearance, English, Simplified
Chinese and Traditional Chinese. The credential card is 440 × 184pt. The
272 × 28pt password bar includes a trailing Return submit button. Focus uses
the theme accent; the title keeps its existing type and geometry.
Cancel is a small corner icon with Escape support. Style, appearance, language
and typography live in Settings (the small sliders button or Cmd+,); Fonts opens
from Settings. Controls remain native. Palettes and ordered font stacks live in
`Resources/Styles/`. Grant is not affiliated with Nothing or Apple.

The bottom-right slider opens six styles, System/Light/Dark, theme/system
typography and three languages. Quick choices are saved and read back by the
installed owner app, then applied to the current card without sending credentials
to the app. Fonts and All settings open the full app; live labels explicitly end
the current request first. Full settings includes the guarded Apple restore/setup
flow. Setup Original is now a live style; the immutable Setup reference remains available.

## Terminal sudo and Setup Original

`Setup Original` is a sixth selectable live style, using the original Setup
header, seven-row table, native secure field and Continue/Cancel buttons. It is
560 × 460pt (plus 36pt when the system account field is expanded); the other five
styles keep their compact geometry. The immutable reference remains available.
Live rows use the actual authentication context rather than fabricated Setup
operation metadata. Selecting Original requires a system plugin at least 0.2.3
when Grant is globally active, so an older reader cannot receive an unsupported style.

The Settings toggle **Use Grant for local terminal sudo** is persisted as
`terminalSudo` (default true). Setup's zsh startup sources the installed app's
`grant_shell.zsh`. Reload existing tabs with `source ~/.zshrc`, or open a new tab.
The function adds sudo's supported `-A`/`SUDO_ASKPASS` route only for local,
interactive, input/output-terminal calls. Explicit `-A`, `-S`, `-n`, an existing
`SUDO_ASKPASS`, unknown flags, SSH, tmux/screen and scripts retain their native
route; `command sudo` and `/usr/bin/sudo` bypass the function. The invoking user's
active console session must match. Sudo still owns validation, retries, command
execution and timestamp caching. A cached/NOPASSWD request needs no password
window; this route does not force a new challenge on every command.

`grant request-sudo` deliberately ignores cached credentials for one harmless
`/usr/bin/true` request so the real UI can be checked. No password is sent through
the CLI or saved: the helper sends one newline-terminated response directly to
its actual sudo parent's pipe. Cancellation sends zero bytes. The transport
supports 1–255 UTF-8 bytes without NUL/CR/LF; only its mutable buffer is explicitly
wiped, not all AppKit/runtime copies. Use the native route for unsupported input.
The helper checks its nonroot identity, active console, direct sudo parent/start
time and pipe again before releasing a response; parent/session loss cancels it.

This is an opt-in terminal bridge, separate from Authorization Services. It adds
no PAM/sudoers modification or daemon. Login, FileVault, Keychain and
LocalAuthentication prompts remain separate. Live iTerm2 acceptance, system
plugin version and installation state must be read from the work record and
`grant status`; renderer fixtures are not evidence of an authenticated command.

## Install and switch

```sh
./grant build
./grant install-app
grant settings
grant theme blueprint
grant theme hard-edge
grant status
```

`install-app` installs `~/Applications/Grant.app` and `~/.local/bin/grant`; it
preserves an earlier owned app under Local/DesktopBackups. Open Grant through
Spotlight or Finder for Settings, or use the short theme command. Preferences
are saved/read back and a running app refreshes after CLI changes. The UI
specimen remains credential-readonly. No login item or background daemon is
added.

Choose **Set up system authorization…** in Settings, or run
`grant install-system`. The terminal requests administrator authority. The
installer restores the exact original stock policy before replacing the inactive
owned plugin and isolated probe, then requests a real isolated Grant
authorization. It activates the shared rule only after that request succeeds.
Cancellation or failure leaves the stock policy in place; it does not claim to
restore the previous Grant rule. The receipt prints `grant restore-system <id>`.

Before system setup, appearance lives in `~/Library/Application Support/Grant/`.
After setup, App and CLI share
`/Library/Application Support/Grant/Preferences/settings.json`. This
user-owned/readable file contains cosmetic preferences only, never credentials.
The plugin reads it on each request. Invalid or unavailable appearance
preferences fall back to root-owned/bundled defaults; authentication still
follows Apple’s unchanged validators.

The settings app runs natively. Its local setup entry and CLI use the existing
Deno runtime and this project checkout; moving/removing the checkout requires
reinstalling those launchers. Recovery baselines remain in root-owned receipts.

## Try locally

Requires macOS 27, Apple Silicon, Xcode, Deno and Python 3. No package
downloads, network access, account, server, login item or credentials are needed
for preview.

```sh
./grant build
./grant check
./grant preview
./grant render
./grant plan
```

`script/build_and_run.sh` and the Codex Run action build/verify before
relaunching the candidate. Outputs stay under ignored `Local/`. Signing identities use the explicit environment/private configuration described above; no signer is distributed and no silent fallback is used. Signing is development evidence, not
notarization or system-host loading proof. The preview disables all credential
entry and saves only style, appearance, display typography and language
preferences, with readback. Authorize and Cancel show explicit simulated
results; Details opens the synthetic Setup request's context. Return and Escape
use the same preview actions. Existing `nothing` preferences migrate to Paper
Punch, `module` to Dot Instrument and `dots` to Theme after preserving the
original settings file; font overrides, appearance and language selections are
retained. The CLI path in preview is an illustrative fixture; it is never
presented as the source of a real system request.

## Theme fonts and fallbacks

The Fonts panel edits the selected theme's preferred font and ordered fallbacks
for **both appearances**, **light only**, or **dark only**. A scoped override
wins over the theme stack; removing it restores inheritance. Theme and System
are separate modes, with names, missing faces and actual Core Text providers
disclosed in the panel and [typography guide](docs/TYPOGRAPHY.md).

- Paper Punch: `Impact` → `AvenirNextCondensed-Heavy` → `@system-condensed`.
- Dot Instrument: optional installed `DotoMod800ZhRefined` → bundled `Doto` at
  800 → bundled `DeparturePixelZhCompact-Regular` → `@system-mono`.
- Swiss Signal: `HelveticaNeue-Bold` → `@system`.
- Hard Edge: bundled `BlackOpsOne-Regular` → optional `Impact` →
  `@system-condensed`.
- Blueprint: bundled `SairaStencilOne-Regular` → bundled
  `DeparturePixelZhCompact-Regular` → `@system-condensed`.

Each stack retains a system last resort, including platform Chinese/emoji
fallback. Missing faces and missing glyphs advance to later choices. Optional
personal and system font binaries are not bundled. The app does not download or install fonts at runtime. Bundled Compact includes its complete licenses/provenance; Doto
includes its OFL notice. Black Ops One and Saira Stencil One are bundled from
pinned official Google Fonts sources with their original OFL notices. No font
installation is needed.

## Actual authorization

The existing [Setup implementation](References/Setup/README.md) is preserved.
Run `./grant original`, or use the preview's existing-interface button, to view
its native UI with synthetic request details and password entry disabled.
`./grant render-original` renders light/dark appearances offscreen. The command
runner is reference source only; the installed Setup tool is not replaced. The
historical English UI is retained.
swiftDialog was a design reference only; no swiftDialog code or runtime dependency is bundled.

The public Authorization Plug-in runs in an unprivileged host and owns Grant's
compact borderless `NSPanel`; it does not embed an `SFAuthorizationPluginView` in
Apple's dialog. The shared credential view is 440 × 184pt, focuses the password
field, submits on Return and cancels on Escape. Changing the account expands the
panel by 36pt when needed. A public username context value is preferred; the
console account is only an editable convenience prefill. Caller-supplied prompt
text may be absent, so the interface uses a generic administrator-access title
instead of inventing a power-settings operation. Passwords are passed to Apple's
privileged verifier as nonextractable credentials; Grant does not persist or log
them. The preview never requests authorization.

Review the [integration and recovery guide](docs/INTEGRATION.md) before system
installation. The installer restores the exact original stock policy, replaces the
inactive owned plugin and isolated probe, then activates the shared rule only
after a successful real probe. A failed or cancelled probe leaves stock policy
active; it does not claim to restore the prior Grant rule.
Exact participating-app coverage, wrong-password/retry and Touch ID behavior
need their own live acceptance; they are not implied by a successful build.
Terminal sudo now has the explicit opt-in bridge described above. Login, FileVault
and Keychain prompts are separate paths. A local preview is not proof of global coverage or authentication
success.

Real authorization: `grant request` asks macOS to evaluate
`system.privilege.admin`; it executes no privileged operation and can be
cancelled. `grant probe` exercises the separately installed isolated UI;
`grant preview` is a disabled-input fixture. Actual installed behavior must be verified separately for the intended artifact and host. Check
`grant status` for installed policy state; participating apps, retry behavior
and Touch ID paths need separate acceptance.
