# Grant

<p><img src="Resources/README-icon.svg" width="96" height="96" alt="Grant"></p>

[English](README.md) · [简体中文](README.zh-Hans.md) · [繁體中文](README.zh-Hant.md) · [日本語](README.ja.md) · [한국어](README.ko.md) · [Español](README.es.md)

macOS 관리자 인증을 네이티브 스타일로 보여 주는 실험 도구입니다. 현재0.2.3 로컬 후보이며 설정 앱, Authorization Plug-in, 보호된 시스템 설치 절차를 포함합니다. 데스크톱 앱 설치와 시스템 전체 활성화는 별개입니다.

글꼴 네 개는 별도로 받으며 Google Fonts와 Compact 0.1.1은 해시로 고정됩니다. 최초 다운로드에는 네트워크가 필요합니다. 글꼴을 포함한 제품의 브랜드 및 상표 권리는 검증되지 않았습니다. 소스만 공개가 승인되었으며 서명, 설치 및 실제 시스템 인증은 검증되지 않았습니다.

## 스타일과 조작

Paper Punch, Dot Instrument, Swiss Signal, Hard Edge, Blueprint, Setup Original의6가지 스타일을 제공합니다. 종이와 좁고 긴 제목, 실제 도트 서체, 파랑, 노랑과 그림자, 스텐실, 원래 표 형식을 비교할 수 있습니다. 밝게·어둡게·시스템 외관, Theme·System 글꼴, 영어·简体中文·繁體中文 UI를 지원합니다. 이 한국어 설명 파일이 UI 언어를 추가하는 것은 아닙니다.

일반 카드는440×184pt, 원래 Setup 스타일은560×460pt입니다. 계정 필드를 펼치면36pt 늘어납니다. Return은 제출, Escape는 취소입니다. 미리보기는 암호 입력이 꺼진 합성 예제이며, 실제 인증은 받은 맥락을 쓰고 가짜 작업 정보를 만들지 않습니다.

스타일과 명암별 글꼴 우선순위를 바꾸거나 System을 고를 수 있습니다. 빌드된 앱은 필요한 Doto, Compact, Black Ops One, Saira Stencil One과 원래 고지를 포함하며 글꼴을 자동 설치·다운로드하지 않습니다. 선택적인 개인·시스템 글꼴은 재배포하지 않습니다. [서체 안내](docs/TYPOGRAPHY.md)를 참고하세요.

## 소스 검토

Apple Silicon, macOS27, 호환 Xcode／SDK·actool, Deno2, Python3가 필요합니다. 로컬 소스와 Apple 프레임워크만 컴파일하며 패키지 다운로드, 계정, 네트워크가 필요하지 않습니다.


소스 검사 또는 빌드 전에 `python3 scripts/get_fonts.py`를 실행하여 고정된 글꼴을 모두 받으세요. 압축 파일과 글꼴의 해시를 확인하며, 다른 기존 파일은 보존하고 중단합니다. 재배포 전에 권리를 확인하세요.

```sh
./grant check-source
./grant public-build
./grant public-check
./grant public-prepare
```

내보내기와 빌드는 선택한 인덱스와 작업 파일이 검토된 pin과 일치해야 합니다. 변경 사항을 검토하고 파일을 스테이징한 뒤 `python3 scripts/review_source.py --reviewed`를 실행하고, 변경된 도우미와 pin을 스테이징한 후 `./grant public-check`를 실행하세요. 빌드는 격리 스냅샷을 사용하며 기존 결과를 덮어쓰지 않습니다. 데스크톱 교체 시 후보와 설치된 앱이 같은 지정 요구 사항과 정확한 리프 인증서를 충족해야 합니다. 임시 서명은 거부됩니다.

`check-source`는 고정 글꼴·원래 참조 파일·3개 UI 언어와 순수 맥락／응답, 정책, 모의 셸, 격리 설정을 검사합니다. 실제 인증, sudo, 플러그인 로딩, 앱 실행, 설치는 하지 않습니다. `public-build`는 별도의 서명 없는 후보를 만들고 모든 파일의 모드·해시를 다시 읽습니다. 시스템 설치 런처를 만들거나 서명 후보 포인터를 바꾸지 않습니다. 검증된 인증 구성 요소처럼 설치·실행해서는 안 됩니다.

`public-check`／`public-prepare`는 파일을 이름으로 스테이징한 뒤 `public-source.json`의 정확한 Git 인덱스를 사용합니다. 다른 기존 출력은 덮어쓰지 않습니다. Git 이력, 개인 서명 설정, 내부 기록은 제외합니다. 제한 검사는 모든 이력·바이너리의 안전 증명이 아닙니다.

## 서명과 시스템 설치

서명 빌드는 별도 `./grant build`입니다. `GRANT_SIGN_IDENTITY`·`GRANT_PLUGIN_SIGN_IDENTITY` 또는 개인 `Local/signing.json`의 두 식별자가 필요합니다. 없으면 실패하며 몰래 서명 없는 방식으로 전환하지 않습니다. `./grant install-app`은 소유자 후보를 `~/Applications/Grant.app`과 `~/.local/bin/grant`에 설치합니다. 설정은 `grant settings`, 상태 확인은 `grant status`입니다.

시스템 활성화는 별도 관리자 작업입니다. 먼저 [설치·복구 안내](docs/INTEGRATION.md)를 검토합니다. 설치기는 정확한 Apple 기본 정책을 복원하고 비활성 자체 플러그인·격리 프로브를 교체합니다. 실제 격리 인증이 성공해야만 공통 규칙을 켭니다. 취소·실패하면 기본 정책을 유지하며 이전 Grant 규칙을 되살렸다고 주장하지 않습니다. 복구에는 발급된 영수증 ID를 씁니다. 로컬 미리보기는 실제 인증이나 모든 앱 지원을 증명하지 않습니다.

## 터미널 sudo

선택적인 별도 브리지이며 PAM／sudoers 변경이나 데몬을 추가하지 않습니다. `terminalSudo` 설정과 사용자가 설치한 앱의 `grant_shell.zsh`를 씁니다. 로컬·대화형·입출력이 터미널인 호출만 대상입니다. 명시적 -A／-S／-n, 기존SUDO_ASKPASS, 알 수 없는 옵션, SSH, tmux／screen, 스크립트는 원래 경로를 유지하며 `command sudo`／`/usr/bin/sudo`로도 우회합니다. 검증·재시도·실행·캐시는 sudo의 책임입니다.

헬퍼는 실제 sudo 부모·시작 시각·콘솔·파이프를 확인하고 부모 파이프에 직접 응답합니다. 취소는0바이트입니다. NUL／CR／LF 없는1–255 UTF-8바이트를 지원합니다. 가변 버퍼를 지우지만 모든 AppKit 복사본까지 지우는 보장은 없습니다. 로그인, FileVault, Keychain, LocalAuthentication은 별개이며 실제 재시도·Touch ID도 따로 검증해야 합니다.

## 데이터와 라이선스

외관은 활성화 전 `~/Library/Application Support/Grant/`, 활성화 뒤 공유 `/Library/Application Support/Grant/Preferences/settings.json`에 있습니다. 외관만 저장하며 암호는 저장·기록하지 않습니다. 플러그인은 매 요청 읽고 설정 오류로 Apple 인증을 우회하지 않습니다. 로컬 빌드·검증 출력은 Git 제외 Local에 있습니다. 설치된 CLI／설정 런처는 Deno와 체크아웃을 사용하므로 이동할 때 다시 설치해야 합니다.

자체 코드·문서는 [MIT](LICENSE)입니다. 소유자는2026-10-26에 원래 `References/Setup/`의3개 파일이 자기 코드임을 확인하고 Grant 안에서 MIT를 허용했습니다. [출처와 라이선스](References/Setup/README.md)를 유지하며 Setup 전체, 다른 파일, 이력, 데이터는 포함하지 않습니다. 자체 아이콘SVG 두 개는 [CC BY4.0](ARTWORK-LICENSE.md), 글꼴은 원래 조건입니다. 후보에 소프트웨어·참조 코드·그림 고지를 넣습니다. [의존성](DEPENDENCIES.md)을 확인하세요. 빌드와 라이선스 결정만으로 게시·서명·실제 인증·시스템 활성화를 승인하지 않습니다.
