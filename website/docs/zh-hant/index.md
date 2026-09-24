---
layout: home
title: "StrokeMouse"
titleTemplate: "macOS 滑鼠與觸控式軌跡板手勢"
description: "StrokeMouse 是 macOS 滑鼠與觸控式軌跡板手勢自訂工具。用滑鼠鍵或單一修飾鍵繪製軌跡，也可使用實驗性多指觸控手勢；比對後執行快捷鍵、視窗操作與指令碼。滑鼠滾輪還可分軸反向並平滑。"
---

<div class="sm-home">

<GeekHero
  title="用滑鼠與觸控式軌跡板手勢驅動 macOS"
  tagline="按住滑鼠鍵或單一修飾鍵繪製軌跡，也可使用實驗性多指觸控手勢；比對後執行快捷鍵、視窗操作或指令碼。"
  primary-text="立即下載"
  primary-link="/zh-hant/download"
  secondary-text="閱讀文件"
  secondary-link="/zh-hant/guide/getting-started"
  image-src="/screenshots/1.png"
  image-alt="手勢設定列表"
  hud-label="軌跡擷取"
/>

<ProofStrip
  :items="['本機執行', '無遙測', '開源 AGPL', 'macOS 14+']"
/>

<ScreenshotCarousel
  heading="產品介面"
  description="手勢庫、測試、設定與權限，所見即所得。"
  :shots="[
    { src: '/screenshots/1.png', alt: '手勢設定列表' },
    { src: '/screenshots/2.png', alt: '手勢測試' },
    { src: '/screenshots/3.png', alt: '一般設定' },
    { src: '/screenshots/4.png', alt: '權限與引擎狀態' },
    { src: '/screenshots/5.png', alt: '新增手勢 · 錄製軌跡' },
    { src: '/screenshots/6.png', alt: '應用範圍' },
  ]"
/>

<HowItWorks
  heading="三步完成第一次手勢"
  :steps="[
    { title: '下載', desc: '安裝 Apple Silicon 或 Intel 版本。' },
    { title: '授權', desc: '在系統設定中開啟輔助使用。' },
    { title: '選擇輸入方式', desc: '滑鼠繪製、觸控板繪製或觸控手勢。' },
  ]"
/>

<FeatureBento
  heading="為效率使用者準備的能力"
  lead="三種輸入方式，共用動作與 App 範圍；繪製軌跡使用可控比對。捲動增強單獨設定，只留在本機。"
  :items="[
    { icon: 'sparkles', title: '自由軌跡比對', desc: '正規化、有限旋轉與轉折結構門檻，拒絕胡亂近鄰比對。', size: 'large', image: '/screenshots/5.png', imageAlt: '錄製軌跡' },
    { icon: 'menu', title: '選單列常駐', desc: '啟停手勢、開啟設定；圖示隨暫停或缺權限變色。' },
    { icon: 'mouse', title: '滑鼠繪製', desc: '右鍵、中鍵或側鍵觸發；只監聽已啟用設定用到的按鈕。' },
    { icon: 'sparkles', title: '觸控板繪製', desc: '按住一個 Fn、Control、Option、Shift 或 Command，移動指標繪製軌跡；可複用滑鼠繪製規則。' },
    { icon: 'zap', title: '實驗性觸控手勢', desc: '34 類多指輕點、滑動、雙指開合與旋轉；系統手勢可能同時發生。' },
    { icon: 'mouse', title: '捲動增強', desc: '滑鼠滾輪與觸控板分軸反向，一般滾輪可平滑；不進手勢備份。', href: '/guide/settings#scroll-enhancement' },
    { title: '一般設定', desc: '比對門檻、外觀與觸控手勢總開關。', size: 'media', image: '/screenshots/3.png', imageAlt: '一般設定' },
    { icon: 'window', title: 'App 範圍', desc: '全域或按應用程式生效；側邊欄依範圍組織手勢。' },
    { icon: 'import', title: '動作與匯入匯出', desc: '快捷鍵、視窗、媒體、Shell 與 AppleScript；JSON 批次管理。' },
  ]"
/>

<GestureTiles
  heading="開箱預設滑鼠繪製"
  lead="裝好即可用的常用軌跡，也可全部自訂。"
/>

<HomeCta
  heading="開始使用 StrokeMouse"
  lead="本機執行，三種輸入方式共享動作與 App 範圍，設定可匯入匯出。"
  :steps="['下載並安裝對應晶片版本', '授權輔助使用', '選擇輸入方式並設定第一條手勢']"
  primary-text="立即下載"
  primary-link="/zh-hant/download"
  secondary-text="閱讀文件"
  secondary-link="/zh-hant/guide/getting-started"
/>

</div>
