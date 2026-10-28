---
title: "설치와 빌드"
description: "StrokeMouse 설치 또는 소스 빌드. macOS 14+, CLI 빌드, Xcode, 코드 서명, 테스트."
keywords: "StrokeMouse 설치,소스 빌드,xcodebuild,코드 서명,macOS 14"
---

# 설치와 빌드

권장 설치 방법은 Homebrew입니다. [다운로드 페이지](/ko/download)에서 **Apple Silicon / Intel** 프로덕션 빌드를 받을 수도 있습니다. 직접 컴파일하려면 아래 소스 빌드 단계를 따르세요.

## 요구 사항

| 항목 | 요구 |
|------|------|
| OS | macOS 14 Sonoma 이상 |
| 개발 빌드 | Xcode 16+ |
| 프로젝트 생성 | [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`) |

## Homebrew(권장)

[프로젝트가 관리하는 Licoy Homebrew Tap](https://github.com/Licoy/homebrew-tap)에서 설치합니다:

```bash
brew install --cask licoy/tap/strokemouse
```

StrokeMouse는 앱 내 업데이트도 지원합니다. Homebrew가 업그레이드를 확인하고 설치하게 하려면:

```bash
brew upgrade --cask --greedy strokemouse
```

제거 시 설정은 기본적으로 남습니다. 설정까지 지우려면 `--zap`을 추가합니다:

```bash
brew uninstall --cask strokemouse
brew uninstall --cask --zap strokemouse
```

Homebrew와 수동 다운로드는 같은 릴리스 패키지를 쓰므로, 아래 첫 실행 Gatekeeper 및 손쉬운 사용 안내가 둘 다에 적용됩니다.

## 클론

```bash
git clone https://github.com/Licoy/StrokeMouse.git
cd StrokeMouse
```

## 권장: CLI 빌드

안정적인 출력 경로 `output/StrokeMouse.app`은 손쉬운 사용 재승인을 줄입니다.  
Debug는 **StrokeMouse Dev**(Bundle ID `com.strokemouse.app.dev`)로 표시되어 정식 **StrokeMouse**와 함께 승인할 수 있습니다:

```bash
./scripts/build.sh           # Debug → output/StrokeMouse.app (손쉬운 사용: StrokeMouse Dev)
./scripts/build.sh --open    # 끝나면 열기
./scripts/build.sh --release # Release (표시 이름 / Bundle ID가 배포 빌드와 같음)
```

`project.yml`을 바꾸거나 소스를 추가·삭제한 뒤:

```bash
./scripts/generate_project.sh
```

## Xcode에서 실행

```bash
./scripts/generate_project.sh
open StrokeMouse.xcodeproj
```

Scheme **StrokeMouse** → Run.

## 코드 서명

| 항목 | 값 |
|------|--------|
| Bundle ID | Release: `com.strokemouse.app`; Debug: `com.strokemouse.app.dev` (표시 이름 StrokeMouse Dev) |
| 개발 신원 | 키체인의 **`StrokeMouse Dev`** (자체 서명; 로컬 빌드) |
| Release 신원 | **`StrokeMouse Release`** 자체 서명 + Hardened Runtime (고정 신원; **사용자는 인증서를 설치하지 않음**) |
| Ad-hoc | `CODE_SIGN_IDENTITY="-" ./scripts/build.sh` 또는 package (스모크 전용; **업데이트 후 손쉬운 사용이 유지되지 않음**) |
| 공증 | 현재 Apple 공증 / Developer ID 없음 |

::: warning
GitHub Release를 처음 실행할 때 Gatekeeper가 막으면 앱을 Control-클릭한 뒤 열기를 선택하거나 시스템 설정 → 개인정보 보호 및 보안 → 계속 열기를 사용하세요.

**손쉬운 사용**: 공식 패키지는 고정 자체 서명 신원을 쓰므로 **같은 인증서로 서명한 앱 내 업데이트는 보통 권한을 유지**합니다. 예전 ad-hoc 빌드에서 옮기거나 인증서를 바꾸면 **한 번** 다시 승인해야 합니다. 최종 사용자는 게시자 인증서를 **설치하지 않습니다**.
:::

## 릴리스 산출물

```bash
SPARKLE_PUBLIC_KEY="..." ARCH=arm64 ./scripts/package-app.sh
SPARKLE_PUBLIC_KEY="..." ARCH=x86_64 ./scripts/package-app.sh
```

각 아키텍처는 ZIP, TAR.GZ, DMG를 만듭니다. ZIP은 Sparkle 앱 내 업데이트에도 쓰입니다. 버전과 태그 릴리스는 저장소 루트의 `RELEASING.md`를 보세요.

## 테스트

```bash
xcodebuild -scheme StrokeMouse -configuration Debug test
```

## 의존성

- [LaunchAtLogin-Modern](https://github.com/sindresorhus/LaunchAtLogin-Modern) — 로그인 시 시작
- [Sparkle](https://github.com/sparkle-project/Sparkle) — 업데이트 서명과 앱 내 설치
- 시스템: `CGEventTap`, 손쉬운 사용, 선택적 Apple Events

## 다음

빌드가 성공하면 [권한](./permissions)과 [빠른 시작](./getting-started)으로 이어가세요.
