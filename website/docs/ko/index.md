---
layout: home
title: "StrokeMouse"
titleTemplate: "macOS 마우스와 트랙패드 제스처"
description: "StrokeMouse는 macOS 마우스·트랙패드 제스처 도구입니다. 마우스 버튼이나 수정 키 하나로 그리거나 실험적 멀티터치 제스처를 사용한 뒤 단축키, 윈도우 동작, 스크립트를 실행합니다. 휠은 축마다 반전하고 일반 휠은 부드럽게 할 수 있습니다."
---

<div class="sm-home">

<GeekHero
  title="마우스와 트랙패드 제스처로 macOS를 움직이세요"
  tagline="마우스 버튼이나 수정 키 하나를 누른 채 궤적을 그리거나, 실험적 멀티터치 제스처를 사용하세요. 일치하면 단축키, 윈도우 동작, 스크립트를 실행합니다."
  primary-text="다운로드"
  primary-link="/ko/download"
  secondary-text="문서 읽기"
  secondary-link="/ko/guide/getting-started"
  image-src="/screenshots/1.png"
  image-alt="제스처 구성 목록"
  hud-label="궤적 캡처"
/>

<ProofStrip
  :items="['로컬 실행', '원격 측정 없음', '오픈 소스 AGPL', 'macOS 14+']"
/>

<ScreenshotCarousel
  heading="제품 화면"
  description="제스처 라이브러리, 테스트, 설정, 권한."
  :shots="[
    { src: '/screenshots/1.png', alt: '제스처 구성 목록' },
    { src: '/screenshots/2.png', alt: '제스처 테스트' },
    { src: '/screenshots/3.png', alt: '일반 설정' },
    { src: '/screenshots/4.png', alt: '권한' },
    { src: '/screenshots/5.png', alt: '궤적 녹음' },
    { src: '/screenshots/6.png', alt: '앱 범위' },
  ]"
/>

<HowItWorks
  heading="세 단계로 첫 제스처"
  :steps="[
    { title: '다운로드', desc: 'Apple Silicon 또는 Intel 빌드를 설치합니다.' },
    { title: '권한 허용', desc: '시스템 설정에서 손쉬운 사용을 켭니다.' },
    { title: '입력 방식 선택', desc: '마우스 그리기, 트랙패드 그리기 또는 터치 제스처.' },
  ]"
/>

<FeatureBento
  heading="파워 유저를 위한 기능"
  lead="세 가지 입력 방식이 동작과 앱 범위를 공유합니다. 그린 경로는 제어 가능한 일치를 사용합니다. 스크롤 향상은 따로 설정하며 이 Mac에만 남습니다."
  :items="[
    { icon: 'sparkles', title: '자유 경로 일치', desc: '정규화, 제한된 회전, 꺾임 구조 게이트로 대충 비슷한 궤적은 거절합니다.', size: 'large', image: '/screenshots/5.png', imageAlt: '궤적 녹음' },
    { icon: 'menu', title: '메뉴 막대 상주', desc: '제스처를 켜거나 끄고 설정을 엽니다. 일시 정지이거나 권한이 없으면 아이콘 색이 바뀝니다.' },
    { icon: 'mouse', title: '마우스 그리기', desc: '오른쪽, 가운데 또는 측면 버튼으로 트리거합니다. 활성화된 버튼만 감시합니다.' },
    { icon: 'sparkles', title: '트랙패드 그리기', desc: 'Fn, Control, Option, Shift, Command 중 하나를 누른 채 포인터를 움직입니다. 마우스 그리기 규칙을 재사용할 수 있습니다.' },
    { icon: 'zap', title: '실험적 터치 제스처', desc: '34종의 여러 손가락 탭, 스와이프, 핀치, 펼치기, 회전. 시스템 제스처가 동시에 일어날 수 있습니다.' },
    { icon: 'mouse', title: '스크롤 향상', desc: '마우스 휠과 트랙패드를 축마다 반전하고 일반 휠을 부드럽게 합니다. 제스처 백업에는 들어가지 않습니다.', href: '/guide/settings#scroll-enhancement' },
    { title: '일반 설정', desc: '일치 임계값, 모양, 터치 제스처 마스터 스위치.', size: 'media', image: '/screenshots/3.png', imageAlt: '일반 설정' },
    { icon: 'window', title: '앱 범위', desc: '전역 또는 앱별로 적용됩니다. 사이드바가 범위별로 제스처를 묶습니다.' },
    { icon: 'import', title: '동작과 가져오기', desc: '단축키, 윈도우, 미디어, Shell과 AppleScript. JSON으로 일괄 관리합니다.' },
  ]"
/>

<GestureTiles
  heading="기본 마우스 그리기 제스처"
  lead="설치 직후 바로 쓰는 궤적, 전부 직접 바꿀 수 있습니다."
/>

<HomeCta
  heading="StrokeMouse 시작하기"
  lead="로컬에서 실행됩니다. 세 입력 방식이 동작과 앱 범위를 공유하고, 구성은 JSON으로 가져오고 내보냅니다."
  :steps="['칩에 맞는 빌드를 다운로드합니다', '손쉬운 사용을 허용합니다', '입력을 고르고 첫 제스처를 구성합니다']"
  primary-text="다운로드"
  primary-link="/ko/download"
  secondary-text="문서 읽기"
  secondary-link="/ko/guide/getting-started"
/>

</div>
