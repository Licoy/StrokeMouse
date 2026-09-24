[English](./README.md) · [简体中文](./README_zh-Hans.md) · [繁體中文](./README_zh-Hant.md) · **한국어** · [日本語](./README_ja.md) · [Русский](./README_ru.md) · [Français](./README_fr.md)

<div align="center">
  <img src="design/logo/stroke-mouse-app-icon.png" width="128" alt="StrokeMouse" />
  <h1>StrokeMouse</h1>
  <p>
    <a href="./LICENSE"><img alt="License: AGPL-3.0" src="https://img.shields.io/badge/License-AGPL%20v3-blue.svg" /></a>
  </p>
</div>

macOS용 마우스·트랙패드 제스처 사용자 설정 도구입니다. 마우스 버튼을 누른 채 궤적을 그리거나, 수정 키 하나를 누른 채 트랙패드 그리기를 하거나, 실험적인 여러 손가락 터치 제스처를 사용할 수 있습니다. 일치하면 단축키, 앱 열기, 윈도우 조작, 미디어 키, Shell / AppleScript 등을 실행합니다. **전역 또는 특정 App**에만 적용할 수 있고, 제스처 구성은 **가져오기/내보내기**가 가능하며, 로컬에서 실행되고 메뉴 막대에 상주합니다.

## 화면 미리보기

| 제스처 구성 목록 | 제스처 테스트 |
|:---:|:---:|
| <img src="website/docs/public/screenshots/1.png" width="400" alt="제스처 구성 목록" /> | <img src="website/docs/public/screenshots/2.png" width="400" alt="제스처 테스트" /> |

| 일반 설정 | 권한 및 엔진 상태 |
|:---:|:---:|
| <img src="website/docs/public/screenshots/3.png" width="400" alt="일반 설정" /> | <img src="website/docs/public/screenshots/4.png" width="400" alt="권한 및 엔진 상태" /> |

| 새 제스처 · 궤적 녹음 | 앱 범위 |
|:---:|:---:|
| <img src="website/docs/public/screenshots/5.png" width="400" alt="새 제스처 · 궤적 녹음" /> | <img src="website/docs/public/screenshots/6.png" width="400" alt="앱 범위" /> |

## 기능

- **메뉴 막대 상주**: 제스처 켜기/끄기, 설정 열기, 종료; 아이콘이 상태(정상 / 일시 정지 / 권한 필요)에 따라 색이 바뀜; **메뉴 막대 아이콘 숨기기** 가능(Dock도 숨기면 재확인; 숨긴 뒤에는 Dock을 클릭하거나 앱을 다시 열어 설정으로 진입)
- **제스처 라이브러리**: 사이드바를 **전역 / 앱별**로 구성(새로 만들 때 범위 미리 채움); 검색 / 필터 / 정렬; 다중 선택 일괄 켜기·끄기·삭제; **JSON 가져오기/내보내기**(중복 항목은 건너뛰거나 강제 가져오기)
- **마우스 그리기**: 제스처마다 오른쪽, 가운데 또는 측면 버튼을 독립적으로 선택; 활성화된 구성이 쓰는 버튼만 감시
- **트랙패드 그리기**: Fn / Control / Option / Shift / Command 중 하나(기본값 Fn)를 누른 채 포인터를 이동해 그림; 지원되는 추가 수정 키를 누르면 이번 인식이 취소됨
- **실험적 터치 제스처**: 내장 트랙패드는 3–5손가락 탭 / 이중 탭 / 네 방향 스와이프와 2–5손가락 핀치 / 펼치기 / 시계·반시계 회전 등 34종을 지원
- **터치 제스처 마스터 스위치**: 이미 구성한 제스처를 삭제하지 않고 터치 제스처 채널만 끌 수 있음; 비공개 백엔드 장애는 터치 채널만 저하시키고 마우스·트랙패드 그리기는 유지
- **스크롤 향상**: 마우스 휠과 트랙패드 / Magic Mouse의 세로·가로를 따로 반전하고, 일반 휠은 부드러운 스크롤(부드럽게 / 표준 / 민감, 또는 속도·시간·가속 사용자 지정)을 켤 수 있음. 제외 목록은 전면 앱 기준이며 설정은 이 Mac에만 남고 백업 동기화에 들어가지 않음. 다른 스크롤 도구와 함께 쓰면 두 번 처리될 수 있고, 정수 줄만 읽는 앱(일부 게임, VM, 원격 데스크톱)은 제외 목록에 넣는 것이 좋음
- **제스처별 대상**: 트리거를 누른 순간의 전면 앱 또는 포인터 아래 앱을 선택; 일반 윈도우가 있으면 해당 윈도우도 고정하고, 앱 범위 판정과 대상 관련 동작은 항상 그 대상을 재사용
- **자유 경로 인식**: 호 길이 재샘플링 + 1D/2D 정규화 + 제한된 회전; 뚜렷한 꺾임 구조 게이트; 일반 설정에서 전역 일치 임계값 조정 가능; 트리거를 누르는 동안 실시간 궤적 HUD
- **App 범위**: 전역, 또는 설치된 앱에서 아이콘으로 추가(검색 / `.app` 찾아보기)
- **다양한 동작**: 단축키, 앱 열기/전환, URL, 미디어 키, 윈도우 동작, Shell / AppleScript(구문 강조; AppleScript는 잠자기, 화면 잠금, 휴지통 비우기 등 프리셋과 사용자 정의)
- **사용성**: 영어, 중국어 간체, 중국어 번체, 한국어, 일본어, 러시아어, 프랑스어 UI(또는 시스템 언어 따르기), 라이트/다크(시스템 / 강제), 로그인 시 시작, Dock / 메뉴 막대 아이콘 숨기기, Sparkle 앱 내 업데이트(실패 시 GitHub Releases로 대체)

## 시스템 요구 사항

- macOS 14 Sonoma 이상
- Xcode 16+(개발 빌드)
- 마우스 또는 트랙패드로 그리기 제스처를 수행할 수 있음; 직접 멀티터치는 주로 Mac 내장 트랙패드를 대상으로 함
- 외장 Magic Trackpad는 best-effort 지원이며 기종이나 시스템 버전에 따라 다를 수 있음

## 설치

### Homebrew(권장)

StrokeMouse 프로젝트가 유지하는 [Licoy Homebrew Tap](https://github.com/Licoy/homebrew-tap)으로 설치합니다.

```bash
brew install --cask licoy/tap/strokemouse
```

StrokeMouse는 앱 내 업데이트도 지원합니다. Homebrew로 강제로 확인하고 업그레이드하려면:

```bash
brew upgrade --cask --greedy strokemouse
```

제거 시 설정은 기본적으로 유지됩니다. 설정도 지우려면 `--zap`을 추가하세요.

```bash
brew uninstall --cask strokemouse
brew uninstall --cask --zap strokemouse
```

[공식 다운로드 페이지](https://strokemouse.com/ko/download)에서 해당 아키텍처 DMG를 받을 수도 있습니다. 현재 릴리스는 고정 자체 서명 코드 서명을 사용하며 Apple 공증을 받지 않았습니다. 첫 실행이 Gatekeeper에 막히면 앱을 Control-클릭한 뒤 「열기」를 선택하거나 「시스템 설정 → 개인정보 보호 및 보안」에서 「계속 열기」를 선택하세요.

## 권한

| 권한 | 용도 |
|------|------|
| **손쉬운 사용(Accessibility)** | 전역 마우스 / 수정 키 / 스크롤 이벤트 감시(`CGEventTap`), 단축키 주입, 윈도우 AX 조작 |
| **자동화(Automation)** | 선택 사항; AppleScript가 다른 앱을 제어할 때 필요 |

첫 실행 또는 **설정 → 권한**에서 앱 내 **안내 승인**을 사용할 수 있습니다. 시스템 설정을 열고 StrokeMouse를 목록에 끌어다 놓아 스위치를 켭니다. 신뢰되지 않으면 엔진은 감시 중인 척하지 않습니다.

### 실험적 터치 제스처

터치 제스처는 런타임 `dlopen` / `dlsym`으로 Apple의 비공개 `MultitouchSupport`를 로드하며 해당 프레임워크를 정적으로 링크하지 않습니다. macOS 업데이트 후 동작이 멈출 수 있습니다. 프레임워크, 심볼, 장치 누락이나 장치 시작 실패는 터치 채널 장애로 표시되며, 마우스와 트랙패드 그리기는 계속 사용할 수 있고 가짜 대체나 조용한 재시도는 하지 않습니다.

StrokeMouse는 트랙패드 네이티브 이벤트를 가로채지 않으므로 시스템 제스처가 바인딩된 동작과 동시에 일어날 수 있습니다. 원시 터치 궤적도 저장하거나 기록하지 않습니다. 활성화된 터치 제스처 구성을 처음 저장·활성화·가져올 때 실험 위험 확인이 표시되며, 이후 마스터 스위치로 구성을 삭제하지 않고 터치 제스처를 일시 중지할 수 있습니다.

지원하는 터치 제스처 34종:

| 종류 | 손가락 수 | 변형 | 개수 |
|------|-----------|------|------|
| 탭 | 셋 / 넷 / 다섯 | 한 번, 두 번 | 6 |
| 스와이프 | 셋 / 넷 / 다섯 | 위, 아래, 왼쪽, 오른쪽 | 12 |
| 확대/축소 | 둘 / 셋 / 넷 / 다섯 | 핀치, 펼치기 | 8 |
| 회전 | 둘 / 셋 / 넷 / 다섯 | 반시계, 시계 | 8 |
| **합계** |  |  | **34** |

첫 버전은 두 손가락 탭 / 스와이프, 수정 키 조합, 특정 손가락 식별, 연속 반복 동작, 사용자가 조절하는 인식 임계값을 지원하지 않습니다.

## 빌드 및 실행

### 의존성

```bash
brew install xcodegen
```

### 프로젝트 생성 후 열기

```bash
./scripts/generate_project.sh
open StrokeMouse.xcodeproj
```

또는 Xcode에서 바로 **Run**(Scheme: `StrokeMouse`).

### CLI 빌드(권장)

저장소의 `output/StrokeMouse.app`에 고정 경로로 출력해 손쉬운 사용 재승인을 줄입니다.  
Debug 표시 이름은 **StrokeMouse Dev**(Bundle ID `com.strokemouse.app.dev`)이며, 정식판 **StrokeMouse**와 손쉬운 사용에서 따로 승인할 수 있습니다.

```bash
./scripts/build.sh           # Debug → output/StrokeMouse.app (손쉬운 사용: StrokeMouse Dev)
./scripts/build.sh --open    # 빌드 후 자동으로 열기
./scripts/build.sh --release # Release (표시 이름 / Bundle ID가 정식 패키지와 동일)
```

### 릴리스 패키징

아키텍처별로 ZIP, TAR.GZ, DMG를 만들고 서명, entitlements, 산출물 무결성을 검증합니다(기본값은 고정 자체 서명 신원 **`StrokeMouse Release`**, Sparkle 업데이트 후에도 손쉬운 사용 권한이 유지되도록).

```bash
# 처음 로컬: ./scripts/generate-codesign-cert.sh --import
SPARKLE_PUBLIC_KEY="..." ARCH=arm64 ./scripts/package-app.sh
SPARKLE_PUBLIC_KEY="..." ARCH=x86_64 ./scripts/package-app.sh
```

릴리스와 CI secrets는 `RELEASING.md` / `certs/README.md`를 보세요.

버전 릴리스는 `./bump.sh -v x.y.z [-p]`; 같은 버전을 다시 태그하고 푸시하려면 `./bump.sh -v x.y.z --force`.

### 테스트

```bash
xcodebuild -scheme StrokeMouse -configuration Debug test
```

## 사용 방법

1. 앱을 실행하면 메뉴 막대에 마우스 아이콘이 나타납니다  
2. **손쉬운 사용** 권한을 부여한 뒤 메뉴 막대에서 제스처를 켭니다  
3. **설정 → 제스처**에서 기본 제스처를 보거나 새로 만듭니다  
4. 입력 방식을 고릅니다: 마우스 트리거를 누른 채 그리기, 수정 키 하나를 누른 채 트랙패드 그리기, 또는 구성한 터치 제스처 수행
5. 일치하면 바인딩된 동작이 실행됩니다  

> **짧은 클릭 vs 제스처**: 트리거의 누름/뗌은 엔진이 잠시 가로챕니다. 「최소 이동 거리」에 도달하기 전에 떼면 일반 클릭으로 재생되어 컨텍스트 메뉴를 쓸 수 있습니다. 그리기가 시작되면 드래그는 시스템 커서와 궤적 HUD를 움직이지만, 전면 앱은 짝이 맞는 누름/뗌을 받지 않으므로 컨텍스트 메뉴가 열리거나 선택되지 않습니다. 왼쪽 버튼과 트리거로 설정되지 않은 버튼은 항상 통과합니다.

> **트랙패드 그리기**: 수정 키 감시는 listen-only이며 키보드 이벤트를 삼키지 않습니다. 짧은 경로는 동작을 실행하지 않습니다. 경로는 시스템 포인터를 따르므로 트랙패드나 마우스로 움직일 수 있습니다. StrokeMouse는 수정 키 자체의 현재 앱 효과를 막지 않습니다.

> 단축키는 먼저 고정된 앱을 활성화하고, 정확한 윈도우가 잡혀 있으면 그 윈도우도 앞으로 가져오므로 포커스나 Space가 바뀔 수 있습니다. Finder 데스크탑처럼 일반 윈도우가 없는 위치에서도 단축키와 **앱 가리기**는 실행할 수 있습니다. 닫기, 최소화, 확대/축소, 전체 화면, 가운데 정렬은 정확한 윈도우가 필요합니다. 짧은 클릭은 대상을 활성화하지 않습니다.

기본 제스처 예(기본값은 오른쪽 버튼; 제스처마다 다른 버튼을 쓸 수 있음):

| 제스처 | 동작 |
|--------|------|
| ↑ | Mission Control (⌃↑) |
| ↓ | 응용 프로그램 윈도우 (⌃↓) |
| ↓← | 윈도우 최소화 |
| ↓→ | 윈도우 닫기 |
| ↑→ | Safari 열기 |
| →← | 재생 / 일시 정지 |
| ↑← | GitHub 열기 |

## 구성 파일

경로:

```text
~/Library/Application Support/StrokeMouse/gestures.json
```

일상적으로는 **설정 → 제스처**에서 여러 항목을 선택한 뒤 JSON 패키지를 내보내거나 가져옵니다. 전체 라이브러리 백업은 위 파일을 복사하거나 직접 편집하세요(구조는 유효해야 함). 설정에서 **Finder에서 보기**를 할 수 있습니다.

## 기술 스택

- Swift / SwiftUI (macOS 14+)
- 가벼운 MVVM + Service
- 전역 마우스 / 수정 키 이벤트용 `CGEventTap`
- 실험적 터치 제스처를 위한 `MultitouchSupport`의 런타임 `dlopen` / `dlsym` 로드(정적 링크 없음)
- JSON 구성 유지
- 로그인 시 시작용 [LaunchAtLogin-Modern](https://github.com/sindresorhus/LaunchAtLogin-Modern)
- 서명된 앱 내 업데이트용 [Sparkle](https://github.com/sparkle-project/Sparkle)
- Xcode 프로젝트용 XcodeGen

## 라이선스 및 면책

이 프로젝트는 [GNU Affero General Public License v3.0 (AGPL-3.0)](./LICENSE)로 라이선스됩니다.

로컬 유틸리티입니다. 전역 이벤트 감시와 스크립트 동작은 강력합니다. 신뢰하는 Shell / AppleScript만 추가하세요. 작성자는 오용이나 실수로 인한 손해에 대해 책임지지 않습니다.
