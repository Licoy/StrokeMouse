---
layout: home
title: "StrokeMouse"
titleTemplate: "macOS 鼠标手势"
description: "StrokeMouse 是 macOS 鼠标手势自定义工具。按住触发键绘制轨迹，执行快捷键与脚本；支持 App 作用域、手势导入导出与菜单栏常驻。"
---

<div class="sm-home">

<GeekHero
  title="用鼠标轨迹驱动 macOS"
  tagline="按住触发键画轨迹，匹配后执行快捷键、窗口操作或脚本。"
  primary-text="立即下载"
  primary-link="/download"
  secondary-text="阅读文档"
  secondary-link="/guide/getting-started"
  image-src="/screenshots/1.png"
  image-alt="手势配置列表"
  hud-label="轨迹捕获"
/>

<ProofStrip
  :items="['本地运行', '无遥测', '开源 AGPL', 'macOS 14+']"
/>

<HowItWorks
  heading="三步完成第一次手势"
  :steps="[
    { title: '下载', desc: '安装 Apple Silicon 或 Intel 版本。' },
    { title: '授权', desc: '在系统设置中开启辅助功能。' },
    { title: '画第一笔', desc: '按住右键上滑，触发 Mission Control。' },
  ]"
/>

<FeatureBento
  heading="为效率党准备的能力"
  lead="菜单栏常驻，轨迹匹配可控，动作覆盖从快捷键到脚本。"
  :items="[
    { icon: 'sparkles', title: '自由轨迹匹配', desc: '归一化、有限旋转与转折结构门控，拒绝胡乱近邻匹配。', size: 'large', image: '/screenshots/5.png', imageAlt: '录制轨迹' },
    { icon: 'menu', title: '菜单栏常驻', desc: '启停手势、打开设置；图标随暂停或缺权限变色。' },
    { icon: 'mouse', title: '独立触发键', desc: '默认右键，也可中键或侧键；只监听已启用按键。' },
    { title: '通用设置', desc: '匹配阈值、外观与引擎选项。', size: 'media', image: '/screenshots/3.png', imageAlt: '通用设置' },
    { icon: 'window', title: 'App 作用域', desc: '全局或按应用生效；侧栏按作用域组织手势。' },
    { icon: 'zap', title: '动作与导入导出', desc: '快捷键、窗口、媒体、Shell 与 AppleScript；JSON 批量管理。' },
  ]"
/>

<GestureTiles
  heading="开箱默认手势"
  lead="装好即可用的常用轨迹，也可全部自定义。"
/>

<ScreenshotCarousel
  heading="产品界面"
  description="手势库、测试、设置与权限，所见即所得。"
  :shots="[
    { src: '/screenshots/1.png', alt: '手势配置列表' },
    { src: '/screenshots/2.png', alt: '手势测试' },
    { src: '/screenshots/3.png', alt: '通用设置' },
    { src: '/screenshots/4.png', alt: '权限与引擎状态' },
    { src: '/screenshots/5.png', alt: '新建手势 · 录制轨迹' },
    { src: '/screenshots/6.png', alt: '应用范围' },
  ]"
/>

<HomeCta
  heading="开始使用 StrokeMouse"
  lead="本地运行，配置可导入导出。"
  :steps="['下载并安装对应芯片版本', '授权辅助功能', '画第一笔手势']"
  primary-text="立即下载"
  primary-link="/download"
  secondary-text="阅读文档"
  secondary-link="/guide/getting-started"
/>

</div>
