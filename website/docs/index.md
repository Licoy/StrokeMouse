---
layout: home
title: "StrokeMouse"
titleTemplate: "macOS 鼠标与触控板手势"
description: "StrokeMouse 是 macOS 鼠标与触控板手势自定义工具。用鼠标键或单个修饰键绘制轨迹，也可使用实验性多指触控手势；匹配后执行快捷键、窗口操作与脚本。"
---

<div class="sm-home">

<GeekHero
  title="用鼠标与触控板手势驱动 macOS"
  tagline="按住鼠标键或单个修饰键绘制轨迹，也可使用实验性多指触控手势；匹配后执行快捷键、窗口操作或脚本。"
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
    { title: '选择输入方式', desc: '鼠标绘制、触控板绘制或触控手势。' },
  ]"
/>

<FeatureBento
  heading="为效率党准备的能力"
  lead="三种输入方式，共用动作与 App 作用域；绘制轨迹使用可控匹配。"
  :items="[
    { icon: 'sparkles', title: '自由轨迹匹配', desc: '归一化、有限旋转与转折结构门控，拒绝胡乱近邻匹配。', size: 'large', image: '/screenshots/5.png', imageAlt: '录制轨迹' },
    { icon: 'menu', title: '菜单栏常驻', desc: '启停手势、打开设置；图标随暂停或缺权限变色。' },
    { icon: 'mouse', title: '鼠标绘制', desc: '右键、中键或侧键触发；只监听已启用配置用到的按钮。' },
    { icon: 'sparkles', title: '触控板绘制', desc: '按住一个 Fn、Control、Option、Shift 或 Command，移动指针绘制轨迹；可复用鼠标绘制规则。' },
    { icon: 'zap', title: '实验性触控手势', desc: '34 类多指轻触、滑动、捏合、张开与旋转；系统手势可能同时发生。' },
    { title: '通用设置', desc: '匹配阈值、外观与触控手势总开关。', size: 'media', image: '/screenshots/3.png', imageAlt: '通用设置' },
    { icon: 'window', title: 'App 作用域', desc: '全局或按应用生效；侧栏按作用域组织手势。' },
    { icon: 'import', title: '动作与导入导出', desc: '快捷键、窗口、媒体、Shell 与 AppleScript；JSON 批量管理。' },
  ]"
/>

<GestureTiles
  heading="开箱默认鼠标绘制"
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
  lead="本地运行，三种输入方式共享动作与 App 作用域，配置可导入导出。"
  :steps="['下载并安装对应芯片版本', '授权辅助功能', '选择输入方式并配置第一条手势']"
  primary-text="立即下载"
  primary-link="/download"
  secondary-text="阅读文档"
  secondary-link="/guide/getting-started"
/>

</div>
