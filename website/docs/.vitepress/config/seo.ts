/**
 * Per-page SEO metadata for StrokeMouse (all site locales).
 * Used by transformPageData + transformHead at build time.
 */

import {
  LOCALES,
  X_DEFAULT_LOCALE,
  alternatePaths,
  localeFromPathname,
  localePath,
  pageIdFromPathname,
  parseRelativePath,
  pathFromRelative,
  type LocaleKey,
} from './locales'

export { pathFromRelative }

export const SITE_TITLE = 'StrokeMouse'
export const SITE_URL = 'https://strokemouse.com'
export const SITE_NAME = SITE_TITLE
export const DEFAULT_OG_IMAGE = `${SITE_URL}/app-icon.png`

export interface PageSeo {
  title: string
  description: string
  keywords: string
  ogType?: 'website' | 'article'
}

export interface FaqEntity {
  name: string
  text: string
}

export const PAGE_IDS = [
  'index',
  'download',
  'guide/getting-started',
  'guide/installation',
  'guide/permissions',
  'guide/gestures',
  'guide/actions',
  'guide/settings',
  'guide/config-file',
  'guide/faq',
] as const

export type PageId = (typeof PAGE_IDS)[number] | string

const PAGE_SEO: Record<string, Partial<Record<LocaleKey, PageSeo>>> = {
  index: {
    root: {
      title: 'StrokeMouse',
      description:
        'StrokeMouse 是 macOS 鼠标与触控板手势自定义工具。用鼠标键或单个修饰键绘制轨迹，也可使用实验性多指触控手势，匹配后执行快捷键、窗口操作、媒体键与脚本。',
      keywords:
        'StrokeMouse,macOS 鼠标手势,触控板绘制,触控手势,鼠标与触控板手势,快捷键,Mission Control,辅助功能',
      ogType: 'website',
    },
    en: {
      title: 'StrokeMouse',
      description:
        'StrokeMouse is a macOS mouse and trackpad gesture tool. Draw with a mouse button or one modifier key, or use experimental multi-touch gestures, then run shortcuts, window actions, media keys, or scripts.',
      keywords:
        'StrokeMouse,macOS mouse gestures,trackpad drawing,trackpad gestures,multi-touch gestures,shortcuts,Mission Control,Accessibility',
      ogType: 'website',
    },
    'zh-hant': {
      title: 'StrokeMouse',
      description:
        'StrokeMouse 是 macOS 滑鼠與觸控式軌跡板手勢自訂工具。用滑鼠鍵或單一修飾鍵繪製軌跡，也可使用實驗性多指觸控手勢，比對後執行快捷鍵、視窗操作、媒體鍵與指令碼。',
      keywords:
        'StrokeMouse,macOS 滑鼠手勢,觸控板繪製,觸控手勢,快捷鍵,Mission Control,輔助使用',
      ogType: 'website',
    },
    ko: {
      title: 'StrokeMouse',
      description:
        'StrokeMouse는 macOS 마우스·트랙패드 제스처 도구입니다. 마우스 버튼이나 수정 키 하나로 그리거나 실험적 멀티터치 제스처를 사용한 뒤 단축키, 윈도우 동작, 미디어 키, 스크립트를 실행합니다.',
      keywords:
        'StrokeMouse,macOS 마우스 제스처,트랙패드 그리기,터치 제스처,단축키,Mission Control,손쉬운 사용',
      ogType: 'website',
    },
    ja: {
      title: 'StrokeMouse',
      description:
        'StrokeMouse は macOS のマウス／トラックパッドジェスチャツールです。マウスボタンまたは修飾キー 1 つで軌跡を描くか、実験的なマルチタッチを使い、ショートカットやウインドウ操作、スクリプトを実行します。',
      keywords:
        'StrokeMouse,macOS マウスジェスチャ,トラックパッド描画,タッチジェスチャ,ショートカット,Mission Control,アクセシビリティ',
      ogType: 'website',
    },
    ru: {
      title: 'StrokeMouse',
      description:
        'StrokeMouse — инструмент жестов мыши и трекпада для macOS. Рисуйте кнопкой мыши или одной клавишей-модификатором, либо используйте экспериментальный мультитач, затем запускайте сочетания, окна и скрипты.',
      keywords:
        'StrokeMouse,жесты мыши macOS,рисование на трекпаде,сенсорные жесты,сочетания клавиш,Mission Control,универсальный доступ',
      ogType: 'website',
    },
    fr: {
      title: 'StrokeMouse',
      description:
        'StrokeMouse est un outil de gestes souris et trackpad pour macOS. Dessinez avec un bouton ou une touche de modification, ou utilisez le multitouch expérimental, puis lancez raccourcis, fenêtres et scripts.',
      keywords:
        'StrokeMouse,gestes souris macOS,dessin trackpad,gestes tactiles,raccourcis,Mission Control,Accessibilité',
      ogType: 'website',
    },
  },
  download: {
    root: {
      title: '下载',
      description:
        '下载 StrokeMouse for macOS。提供 Apple Silicon（M 系列）与 Intel 安装包，macOS 14 及以上。免费本地鼠标手势工具。',
      keywords: 'StrokeMouse 下载,macOS 下载,Apple Silicon,Intel,dmg,鼠标手势软件下载',
      ogType: 'website',
    },
    en: {
      title: 'Download',
      description:
        'Download StrokeMouse for macOS. Apple Silicon (M-series) and Intel installers. Requires macOS 14+. Free local mouse gesture utility.',
      keywords: 'StrokeMouse download,macOS download,Apple Silicon,Intel,dmg,mouse gesture app',
      ogType: 'website',
    },
    'zh-hant': {
      title: '下載',
      description:
        '下載 StrokeMouse for macOS。提供 Apple Silicon（M 系列）與 Intel 安裝包，macOS 14 及以上。免費本機滑鼠手勢工具。',
      keywords: 'StrokeMouse 下載,macOS 下載,Apple Silicon,Intel,dmg,滑鼠手勢軟體下載',
      ogType: 'website',
    },
    ko: {
      title: '다운로드',
      description:
        'macOS용 StrokeMouse를 다운로드하세요. Apple Silicon(M 시리즈)과 Intel 설치 패키지, macOS 14 이상. 무료 로컬 마우스 제스처 도구입니다.',
      keywords: 'StrokeMouse 다운로드,macOS 다운로드,Apple Silicon,Intel,dmg,마우스 제스처',
      ogType: 'website',
    },
    ja: {
      title: 'ダウンロード',
      description:
        'macOS 向け StrokeMouse をダウンロード。Apple Silicon（M シリーズ）と Intel 用インストーラ。macOS 14 以降。無料のローカルマウスジェスチャツールです。',
      keywords: 'StrokeMouse ダウンロード,macOS ダウンロード,Apple Silicon,Intel,dmg,マウスジェスチャ',
      ogType: 'website',
    },
    ru: {
      title: 'Скачать',
      description:
        'Скачайте StrokeMouse для macOS. Сборки для Apple Silicon (серия M) и Intel, macOS 14+. Бесплатный локальный инструмент жестов мыши.',
      keywords: 'скачать StrokeMouse,загрузка macOS,Apple Silicon,Intel,dmg,жесты мыши',
      ogType: 'website',
    },
    fr: {
      title: 'Télécharger',
      description:
        'Téléchargez StrokeMouse pour macOS. Installateurs Apple Silicon (série M) et Intel. macOS 14+. Utilitaire local de gestes souris, gratuit.',
      keywords: 'télécharger StrokeMouse,téléchargement macOS,Apple Silicon,Intel,dmg,gestes souris',
      ogType: 'website',
    },
  },
  'guide/getting-started': {
    root: {
      title: '快速开始',
      description:
        'StrokeMouse 快速开始：安装后授权辅助功能、启用手势、按住右键画出第一笔轨迹。三分钟上手 macOS 鼠标手势。',
      keywords: 'StrokeMouse 教程,快速开始,鼠标手势入门,辅助功能授权',
      ogType: 'article',
    },
    en: {
      title: 'Quick start',
      description:
        'Get started with StrokeMouse: grant Accessibility, enable gestures, and draw your first stroke with the right button in minutes.',
      keywords: 'StrokeMouse tutorial,quick start,mouse gestures,Accessibility',
      ogType: 'article',
    },
    'zh-hant': {
      title: '快速開始',
      description:
        'StrokeMouse 快速開始：安裝後授權輔助使用、啟用手勢、按住右鍵畫出第一筆軌跡。三分鐘上手 macOS 滑鼠手勢。',
      keywords: 'StrokeMouse 教學,快速開始,滑鼠手勢入門,輔助使用授權',
      ogType: 'article',
    },
    ko: {
      title: '빠른 시작',
      description:
        'StrokeMouse 빠른 시작: 손쉬운 사용을 허용하고 제스처를 켠 뒤 오른쪽 버튼으로 첫 궤적을 그립니다.',
      keywords: 'StrokeMouse 튜토리얼,빠른 시작,마우스 제스처,손쉬운 사용',
      ogType: 'article',
    },
    ja: {
      title: 'クイックスタート',
      description:
        'StrokeMouse の始め方。アクセシビリティを許可し、ジェスチャを有効にして、右ボタンで最初の軌跡を描きます。',
      keywords: 'StrokeMouse チュートリアル,クイックスタート,マウスジェスチャ,アクセシビリティ',
      ogType: 'article',
    },
    ru: {
      title: 'Быстрый старт',
      description:
        'Быстрый старт StrokeMouse: выдайте Универсальный доступ, включите жесты и нарисуйте первую траекторию правой кнопкой.',
      keywords: 'учебник StrokeMouse,быстрый старт,жесты мыши,универсальный доступ',
      ogType: 'article',
    },
    fr: {
      title: 'Démarrage rapide',
      description:
        'Démarrez StrokeMouse : accordez l’Accessibilité, activez les gestes et dessinez votre première trajectoire avec le bouton droit.',
      keywords: 'tutoriel StrokeMouse,démarrage rapide,gestes souris,Accessibilité',
      ogType: 'article',
    },
  },
  'guide/installation': {
    root: {
      title: '安装与构建',
      description:
        'StrokeMouse 安装与源码构建说明：系统要求 macOS 14+、命令行构建、Xcode 运行、签名与测试。',
      keywords: 'StrokeMouse 安装,源码构建,xcodebuild,签名,macOS 14',
      ogType: 'article',
    },
    en: {
      title: 'Install & build',
      description:
        'Install StrokeMouse or build from source. macOS 14+, CLI build, Xcode, code signing, and tests.',
      keywords: 'StrokeMouse install,build from source,xcodebuild,code signing,macOS 14',
      ogType: 'article',
    },
    'zh-hant': {
      title: '安裝與建置',
      description:
        'StrokeMouse 安裝與原始碼建置說明：系統要求 macOS 14+、命令列建置、Xcode 執行、簽署與測試。',
      keywords: 'StrokeMouse 安裝,原始碼建置,xcodebuild,簽署,macOS 14',
      ogType: 'article',
    },
    ko: {
      title: '설치와 빌드',
      description:
        'StrokeMouse 설치와 소스 빌드: macOS 14+, CLI 빌드, Xcode, 코드 서명, 테스트.',
      keywords: 'StrokeMouse 설치,소스 빌드,xcodebuild,코드 서명,macOS 14',
      ogType: 'article',
    },
    ja: {
      title: 'インストールとビルド',
      description:
        'StrokeMouse のインストールとソースビルド。macOS 14+、CLI ビルド、Xcode、コード署名、テスト。',
      keywords: 'StrokeMouse インストール,ソースビルド,xcodebuild,コード署名,macOS 14',
      ogType: 'article',
    },
    ru: {
      title: 'Установка и сборка',
      description:
        'Установка StrokeMouse и сборка из исходников: macOS 14+, CLI, Xcode, подпись и тесты.',
      keywords: 'установка StrokeMouse,сборка из исходников,xcodebuild,подпись,macOS 14',
      ogType: 'article',
    },
    fr: {
      title: 'Installation et compilation',
      description:
        'Installer StrokeMouse ou compiler depuis les sources. macOS 14+, CLI, Xcode, signature et tests.',
      keywords: 'installer StrokeMouse,compiler depuis les sources,xcodebuild,signature,macOS 14',
      ogType: 'article',
    },
  },
  'guide/permissions': {
    root: {
      title: '权限说明',
      description:
        'StrokeMouse 权限说明：辅助功能（Accessibility）用于全局鼠标监听，自动化（Automation）用于 AppleScript。授权失败排查指南。',
      keywords: 'StrokeMouse 权限,辅助功能,Accessibility,Automation,AppleScript',
      ogType: 'article',
    },
    en: {
      title: 'Permissions',
      description:
        'StrokeMouse permissions: Accessibility for global mouse listening, Automation for AppleScript. Troubleshooting failed authorization.',
      keywords: 'StrokeMouse permissions,Accessibility,Automation,AppleScript,macOS privacy',
      ogType: 'article',
    },
    'zh-hant': {
      title: '權限說明',
      description:
        'StrokeMouse 權限說明：輔助使用（Accessibility）用於全域滑鼠監聽，自動化（Automation）用於 AppleScript。授權失敗排查指南。',
      keywords: 'StrokeMouse 權限,輔助使用,Accessibility,Automation,AppleScript',
      ogType: 'article',
    },
    ko: {
      title: '권한',
      description:
        'StrokeMouse 권한: 손쉬운 사용은 전역 마우스 감시, 자동화는 AppleScript용입니다. 승인 실패 점검.',
      keywords: 'StrokeMouse 권한,손쉬운 사용,Accessibility,Automation,AppleScript',
      ogType: 'article',
    },
    ja: {
      title: '権限',
      description:
        'StrokeMouse の権限。アクセシビリティはグローバルマウス監視、自動化は AppleScript 用です。承認失敗の切り分け。',
      keywords: 'StrokeMouse 権限,アクセシビリティ,Automation,AppleScript',
      ogType: 'article',
    },
    ru: {
      title: 'Доступ',
      description:
        'Доступ StrokeMouse: Универсальный доступ для глобального перехвата мыши, Автоматизация для AppleScript. Диагностика отказа.',
      keywords: 'доступ StrokeMouse,универсальный доступ,Accessibility,Automation,AppleScript',
      ogType: 'article',
    },
    fr: {
      title: 'Autorisations',
      description:
        'Autorisations StrokeMouse : Accessibilité pour l’écoute souris globale, Automatisation pour AppleScript. Dépannage des refus.',
      keywords: 'autorisations StrokeMouse,Accessibilité,Automatisation,AppleScript',
      ogType: 'article',
    },
  },
  'guide/gestures': {
    root: {
      title: '手势系统',
      description:
        'StrokeMouse 手势系统：触发键、短按回放、自由轨迹匹配、App 作用域与默认手势示例。学习如何稳定自定义鼠标手势。',
      keywords: '鼠标手势,触发键,freePath,轨迹匹配,App 作用域,默认手势',
      ogType: 'article',
    },
    en: {
      title: 'Gestures',
      description:
        'StrokeMouse gesture system: triggers, short-click replay, free-path matching, app scope, and default gesture examples.',
      keywords: 'mouse gestures,trigger button,free-path matching,app scope,default gestures',
      ogType: 'article',
    },
    'zh-hant': {
      title: '手勢系統',
      description:
        'StrokeMouse 手勢系統：觸發鍵、短按回放、自由軌跡比對、App 範圍與預設手勢範例。學習如何穩定自訂滑鼠手勢。',
      keywords: '滑鼠手勢,觸發鍵,freePath,軌跡比對,App 範圍,預設手勢',
      ogType: 'article',
    },
    ko: {
      title: '제스처',
      description:
        'StrokeMouse 제스처 시스템: 트리거, 짧은 클릭 재생, 자유 경로 일치, 앱 범위, 기본 제스처 예제.',
      keywords: '마우스 제스처,트리거,freePath,경로 일치,앱 범위,기본 제스처',
      ogType: 'article',
    },
    ja: {
      title: 'ジェスチャ',
      description:
        'StrokeMouse のジェスチャ。トリガー、短押し再生、自由軌跡マッチング、App 範囲、デフォルト例。',
      keywords: 'マウスジェスチャ,トリガー,freePath,軌跡マッチング,App 範囲',
      ogType: 'article',
    },
    ru: {
      title: 'Жесты',
      description:
        'Система жестов StrokeMouse: триггеры, повтор короткого щелчка, свободная траектория, область приложения и примеры.',
      keywords: 'жесты мыши,триггер,freePath,сопоставление траектории,область приложения',
      ogType: 'article',
    },
    fr: {
      title: 'Gestes',
      description:
        'Système de gestes StrokeMouse : déclencheurs, rejeu du clic court, correspondance libre, portée d’app et exemples par défaut.',
      keywords: 'gestes souris,déclencheur,freePath,correspondance,portée d’application',
      ogType: 'article',
    },
  },
  'guide/actions': {
    root: {
      title: '动作类型',
      description:
        'StrokeMouse 支持的动作：快捷键、打开 App、URL、媒体键、窗口操作、Shell 与 AppleScript。了解如何绑定手势到动作。',
      keywords: '手势动作,快捷键,Shell,AppleScript,窗口操作,媒体键',
      ogType: 'article',
    },
    en: {
      title: 'Actions',
      description:
        'StrokeMouse actions: shortcuts, open app, URL, media keys, window commands, Shell, and AppleScript.',
      keywords: 'gesture actions,shortcuts,Shell,AppleScript,window actions,media keys',
      ogType: 'article',
    },
    'zh-hant': {
      title: '動作類型',
      description:
        'StrokeMouse 支援的動作：快捷鍵、開啟 App、URL、媒體鍵、視窗操作、Shell 與 AppleScript。了解如何把手勢綁到動作。',
      keywords: '手勢動作,快捷鍵,Shell,AppleScript,視窗操作,媒體鍵',
      ogType: 'article',
    },
    ko: {
      title: '동작',
      description:
        'StrokeMouse 동작: 단축키, 앱 열기, URL, 미디어 키, 윈도우 명령, Shell, AppleScript.',
      keywords: '제스처 동작,단축키,Shell,AppleScript,윈도우 동작,미디어 키',
      ogType: 'article',
    },
    ja: {
      title: 'アクション',
      description:
        'StrokeMouse のアクション。ショートカット、App を開く、URL、メディアキー、ウインドウ操作、Shell、AppleScript。',
      keywords: 'ジェスチャアクション,ショートカット,Shell,AppleScript,ウインドウ操作',
      ogType: 'article',
    },
    ru: {
      title: 'Действия',
      description:
        'Действия StrokeMouse: сочетания клавиш, открытие App, URL, медиа, окна, Shell и AppleScript.',
      keywords: 'действия жестов,сочетания клавиш,Shell,AppleScript,окна,медиа',
      ogType: 'article',
    },
    fr: {
      title: 'Actions',
      description:
        'Actions StrokeMouse : raccourcis, ouvrir une app, URL, touches média, fenêtres, Shell et AppleScript.',
      keywords: 'actions de geste,raccourcis,Shell,AppleScript,fenêtres,touches média',
      ogType: 'article',
    },
  },
  'guide/settings': {
    root: {
      title: '设置与菜单栏',
      description:
        'StrokeMouse 设置与菜单栏：启停手势、手势列表、编辑器、主题、登录启动与权限入口说明。',
      keywords: 'StrokeMouse 设置,菜单栏,登录启动,手势编辑器,主题',
      ogType: 'article',
    },
    en: {
      title: 'Settings & menu bar',
      description:
        'StrokeMouse settings and menu bar: start/stop gestures, gesture list, editor, appearance, launch at login, and permissions.',
      keywords: 'StrokeMouse settings,menu bar,launch at login,gesture editor,theme',
      ogType: 'article',
    },
    'zh-hant': {
      title: '設定與選單列',
      description:
        'StrokeMouse 設定與選單列：啟停手勢、手勢清單、編輯器、主題、登入時啟動與權限入口說明。',
      keywords: 'StrokeMouse 設定,選單列,登入時啟動,手勢編輯器,主題',
      ogType: 'article',
    },
    ko: {
      title: '설정과 메뉴 막대',
      description:
        'StrokeMouse 설정과 메뉴 막대: 제스처 켜기/끄기, 목록, 편집기, 모양, 로그인 시 시작, 권한.',
      keywords: 'StrokeMouse 설정,메뉴 막대,로그인 시 시작,제스처 편집기,테마',
      ogType: 'article',
    },
    ja: {
      title: '設定とメニューバー',
      description:
        'StrokeMouse の設定とメニューバー。ジェスチャの開始／停止、一覧、エディタ、外観、ログイン時に開く、権限。',
      keywords: 'StrokeMouse 設定,メニューバー,ログイン時に開く,ジェスチャエディタ,テーマ',
      ogType: 'article',
    },
    ru: {
      title: 'Настройки и строка меню',
      description:
        'Настройки StrokeMouse и строка меню: вкл/выкл жестов, список, редактор, оформление, запуск при входе и доступ.',
      keywords: 'настройки StrokeMouse,строка меню,запуск при входе,редактор жестов,тема',
      ogType: 'article',
    },
    fr: {
      title: 'Réglages et barre des menus',
      description:
        'Réglages StrokeMouse et barre des menus : activer/arrêter les gestes, liste, éditeur, apparence, ouverture de session et autorisations.',
      keywords: 'réglages StrokeMouse,barre des menus,ouverture de session,éditeur de gestes,thème',
      ogType: 'article',
    },
  },
  'guide/config-file': {
    root: {
      title: '配置文件',
      description:
        'StrokeMouse 配置文件路径与备份：~/Library/Application Support/StrokeMouse/gestures.json。JSON 结构说明与迁移建议。',
      keywords: 'gestures.json,配置备份,Application Support,StrokeMouse 配置',
      ogType: 'article',
    },
    en: {
      title: 'Config file',
      description:
        'StrokeMouse config path and backup: ~/Library/Application Support/StrokeMouse/gestures.json. Structure and migration tips.',
      keywords: 'gestures.json,config backup,Application Support,StrokeMouse config',
      ogType: 'article',
    },
    'zh-hant': {
      title: '設定檔',
      description:
        'StrokeMouse 設定檔路徑與備份：~/Library/Application Support/StrokeMouse/gestures.json。JSON 結構說明與遷移建議。',
      keywords: 'gestures.json,設定備份,Application Support,StrokeMouse 設定',
      ogType: 'article',
    },
    ko: {
      title: '구성 파일',
      description:
        'StrokeMouse 구성 경로와 백업: ~/Library/Application Support/StrokeMouse/gestures.json. 구조와 이전 팁.',
      keywords: 'gestures.json,구성 백업,Application Support,StrokeMouse 구성',
      ogType: 'article',
    },
    ja: {
      title: '設定ファイル',
      description:
        'StrokeMouse の設定パスとバックアップ。~/Library/Application Support/StrokeMouse/gestures.json。構造と移行のヒント。',
      keywords: 'gestures.json,設定バックアップ,Application Support,StrokeMouse 設定',
      ogType: 'article',
    },
    ru: {
      title: 'Файл конфигурации',
      description:
        'Путь и резервная копия StrokeMouse: ~/Library/Application Support/StrokeMouse/gestures.json. Структура и перенос.',
      keywords: 'gestures.json,резервная копия,Application Support,конфигурация StrokeMouse',
      ogType: 'article',
    },
    fr: {
      title: 'Fichier de config',
      description:
        'Chemin et sauvegarde StrokeMouse : ~/Library/Application Support/StrokeMouse/gestures.json. Structure et migration.',
      keywords: 'gestures.json,sauvegarde config,Application Support,config StrokeMouse',
      ogType: 'article',
    },
  },
  'guide/faq': {
    root: {
      title: '常见问题 FAQ',
      description:
        'StrokeMouse 常见问题：手势无反应、右键菜单、误触发、权限、登录启动、配置备份与鼠标要求等解答。',
      keywords: 'StrokeMouse FAQ,手势不工作,右键菜单,故障排除',
      ogType: 'article',
    },
    en: {
      title: 'FAQ',
      description:
        'StrokeMouse FAQ: gestures not working, right-click menu, false matches, permissions, login items, backups, and mouse requirements.',
      keywords: 'StrokeMouse FAQ,troubleshooting,right-click menu,permissions',
      ogType: 'article',
    },
    'zh-hant': {
      title: '常見問題 FAQ',
      description:
        'StrokeMouse 常見問題：手勢無反應、右鍵選單、誤觸發、權限、登入時啟動、設定備份與滑鼠需求等解答。',
      keywords: 'StrokeMouse FAQ,手勢不工作,右鍵選單,疑難排解',
      ogType: 'article',
    },
    ko: {
      title: 'FAQ',
      description:
        'StrokeMouse FAQ: 제스처 무반응, 우클릭 메뉴, 오인식, 권한, 로그인 항목, 백업, 마우스 요구 사항.',
      keywords: 'StrokeMouse FAQ,문제 해결,우클릭 메뉴,권한',
      ogType: 'article',
    },
    ja: {
      title: 'FAQ',
      description:
        'StrokeMouse FAQ。ジェスチャが動かない、右クリックメニュー、誤認識、権限、ログイン項目、バックアップ、マウス要件。',
      keywords: 'StrokeMouse FAQ,トラブルシューティング,右クリックメニュー,権限',
      ogType: 'article',
    },
    ru: {
      title: 'FAQ',
      description:
        'FAQ StrokeMouse: жесты не работают, меню правой кнопки, ложные срабатывания, доступ, вход в систему, резервные копии.',
      keywords: 'StrokeMouse FAQ,устранение неполадок,меню правой кнопки,доступ',
      ogType: 'article',
    },
    fr: {
      title: 'FAQ',
      description:
        'FAQ StrokeMouse : gestes inactifs, menu clic droit, faux positifs, autorisations, ouverture de session, sauvegardes.',
      keywords: 'FAQ StrokeMouse,dépannage,menu clic droit,autorisations',
      ogType: 'article',
    },
  },
}

const FALLBACK: Record<LocaleKey, PageSeo> = {
  root: {
    title: SITE_TITLE,
    description:
      'StrokeMouse 是 macOS 鼠标与触控板手势自定义工具。用鼠标键或单个修饰键绘制轨迹，匹配后执行动作。',
    keywords: 'StrokeMouse,macOS,鼠标手势,触控板绘制,触控手势',
    ogType: 'website',
  },
  en: {
    title: SITE_TITLE,
    description:
      'StrokeMouse is a custom mouse and trackpad gesture tool for macOS. Draw with a mouse button or one modifier key, then run actions.',
    keywords: 'StrokeMouse,macOS,mouse gestures,trackpad drawing,trackpad gestures',
    ogType: 'website',
  },
  'zh-hant': {
    title: SITE_TITLE,
    description:
      'StrokeMouse 是 macOS 滑鼠與觸控式軌跡板手勢自訂工具。用滑鼠鍵或單一修飾鍵繪製軌跡，比對後執行動作。',
    keywords: 'StrokeMouse,macOS,滑鼠手勢,觸控板繪製,觸控手勢',
    ogType: 'website',
  },
  ko: {
    title: SITE_TITLE,
    description:
      'StrokeMouse는 macOS용 마우스·트랙패드 제스처 도구입니다. 마우스 버튼이나 수정 키 하나로 그린 뒤 동작을 실행합니다.',
    keywords: 'StrokeMouse,macOS,마우스 제스처,트랙패드 그리기,터치 제스처',
    ogType: 'website',
  },
  ja: {
    title: SITE_TITLE,
    description:
      'StrokeMouse は macOS 向けのマウス／トラックパッドジェスチャツールです。マウスボタンまたは修飾キー 1 つで描き、アクションを実行します。',
    keywords: 'StrokeMouse,macOS,マウスジェスチャ,トラックパッド描画,タッチジェスチャ',
    ogType: 'website',
  },
  ru: {
    title: SITE_TITLE,
    description:
      'StrokeMouse — инструмент жестов мыши и трекпада для macOS. Рисуйте кнопкой мыши или одной клавишей-модификатором, затем запускайте действия.',
    keywords: 'StrokeMouse,macOS,жесты мыши,рисование на трекпаде,сенсорные жесты',
    ogType: 'website',
  },
  fr: {
    title: SITE_TITLE,
    description:
      'StrokeMouse est un outil de gestes souris et trackpad pour macOS. Dessinez avec un bouton ou une touche de modification, puis lancez des actions.',
    keywords: 'StrokeMouse,macOS,gestes souris,dessin trackpad,gestes tactiles',
    ogType: 'website',
  },
}

export const FAQ_LD: Record<LocaleKey, FaqEntity[]> = {
  root: [
    {
      name: '手势完全没反应？',
      text: '请检查辅助功能是否授权当前 App、菜单栏状态、手势是否启用、是否按住正确触发键，以及滑动是否足够长。',
    },
    {
      name: '右键菜单没了？',
      text: '短按右键仍可弹出菜单；长距离滑动仅用于手势。也可把手势改到中键/侧键。',
    },
  ],
  en: [
    {
      name: 'Gestures do nothing?',
      text: 'Check Accessibility for this app, menu bar status, that the gesture is enabled, you hold the configured trigger, and the stroke is long enough.',
    },
    {
      name: 'Right-click menu gone?',
      text: 'A short right-click still opens the menu. Long strokes are gesture-only. Or bind gestures to middle/side buttons.',
    },
  ],
  'zh-hant': [
    {
      name: '手勢完全沒反應？',
      text: '請檢查輔助使用是否授權目前 App、選單列狀態、手勢是否啟用、是否按住正確觸發鍵，以及滑動是否足夠長。',
    },
    {
      name: '右鍵選單沒了？',
      text: '短按右鍵仍可跳出選單；長距離滑動僅用於手勢。也可把手勢改到中鍵／側鍵。',
    },
  ],
  ko: [
    {
      name: '제스처가 전혀 반응하지 않나요?',
      text: '이 앱의 손쉬운 사용 권한, 메뉴 막대 상태, 제스처 활성화, 올바른 트리거 유지, 충분한 이동 거리를 확인하세요.',
    },
    {
      name: '우클릭 메뉴가 사라졌나요?',
      text: '짧게 우클릭하면 메뉴가 열립니다. 긴 궤적은 제스처 전용입니다. 가운데/측면 버튼에 제스처를 둘 수도 있습니다.',
    },
  ],
  ja: [
    {
      name: 'ジェスチャが全く反応しない？',
      text: 'この App のアクセシビリティ、メニューバーの状態、ジェスチャが有効か、正しいトリガーを押しているか、軌跡が十分長いかを確認してください。',
    },
    {
      name: '右クリックメニューが出ない？',
      text: '短い右クリックならメニューは開きます。長い軌跡はジェスチャ専用です。中ボタンやサイドボタンに割り当てることもできます。',
    },
  ],
  ru: [
    {
      name: 'Жесты совсем не срабатывают?',
      text: 'Проверьте Универсальный доступ для этого приложения, строку меню, включён ли жест, удерживаете ли нужный триггер и достаточно ли длинная траектория.',
    },
    {
      name: 'Пропало меню правой кнопки?',
      text: 'Короткий щелчок правой кнопкой по-прежнему открывает меню. Длинные движения только для жестов. Можно назначить жесты на среднюю или боковые кнопки.',
    },
  ],
  fr: [
    {
      name: 'Les gestes ne font rien ?',
      text: 'Vérifiez l’Accessibilité pour cette app, l’état de la barre des menus, que le geste est activé, que vous maintenez le bon déclencheur et que le trait est assez long.',
    },
    {
      name: 'Le menu clic droit a disparu ?',
      text: 'Un clic droit court ouvre encore le menu. Un long trait est réservé au geste. Vous pouvez aussi lier les gestes aux boutons du milieu ou latéraux.',
    },
  ],
}

export function resolvePageSeo(relativePath: string): PageSeo {
  const { locale, pageId } = parseRelativePath(relativePath)
  return PAGE_SEO[pageId]?.[locale] ?? FALLBACK[locale]
}

export function resolveLocale(relativePath: string): LocaleKey {
  return parseRelativePath(relativePath).locale
}

export function localeHomeUrl(locale: LocaleKey): string {
  return absoluteUrl(localePath(locale, '/'))
}

export function localeDownloadUrl(locale: LocaleKey): string {
  return absoluteUrl(localePath(locale, '/download'))
}

export function hreflangTags(pathname: string): { hreflang: string; href: string }[] {
  const alts = alternatePaths(pathname)
  const tags = (Object.keys(LOCALES) as LocaleKey[]).map((key) => ({
    hreflang: LOCALES[key].hreflang,
    href: canonicalUrl(alts[key]),
  }))
  tags.push({
    hreflang: 'x-default',
    href: canonicalUrl(alts[X_DEFAULT_LOCALE]),
  })
  return tags
}

export function canonicalUrl(pathname: string): string {
  const locale = localeFromPathname(pathname)
  const pageId = pageIdFromPathname(pathname)
  if (pageId === 'index') return absoluteUrl(localePath(locale, '/'))
  return absoluteUrl(localePath(locale, `/${pageId}`))
}

export function absoluteUrl(pathname: string): string {
  if (pathname === '/') return `${SITE_URL}/`
  const p = pathname.startsWith('/') ? pathname : `/${pathname}`
  return `${SITE_URL}${p}`
}

/** @deprecated use alternatePaths; kept for older call sites */
export function alternatePath(pathname: string): { zh: string; en: string } {
  const alts = alternatePaths(pathname)
  return { zh: alts.root, en: alts.en }
}
