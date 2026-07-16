---
layout: home
title: "StrokeMouse"
titleTemplate: "macOS 鼠标手势"
description: "StrokeMouse 是 macOS 鼠标手势自定义工具。按住触发键绘制轨迹，匹配后执行快捷键、窗口操作与脚本。"
---

<div class="sm-home">

<GeekHero
  title="StrokeMouse"
  title-accent="画轨迹，跑动作"
  tagline="按住触发键绘制鼠标轨迹，匹配配置后执行快捷键、打开应用、窗口操作、媒体键或 Shell / AppleScript。本地运行，菜单栏常驻，极客可配。"
  primary-text="立即下载"
  primary-link="/download"
  secondary-text="阅读文档"
  secondary-link="/guide/getting-started"
  hud-label="轨迹捕获 · 实时"
/>

<TerminalBlock
  title="快速开始"
  :lines="[
    'open StrokeMouse.app',
    '# 设置 → 权限 → 开启辅助功能',
    '# 按住右键，画一条向上的线，松开',
    '# → Mission Control',
  ]"
/>

<FeatureGrid
  subheading="能力"
  heading="为效率党准备的能力"
  :items="[
    { icon: 'menu', title: '菜单栏常驻', desc: '启停手势、打开设置、权限状态一目了然，退出也在这里。' },
    { icon: 'sparkles', title: '自由轨迹匹配', desc: '有序弧长重采样 + 归一化 + 有限旋转；转折结构门控，拒绝胡乱匹配。' },
    { icon: 'mouse', title: '每条手势独立触发键', desc: '默认右键，也可中键 / 侧键；只监听你真正启用的按键集合。' },
    { icon: 'window', title: 'App 作用域', desc: '全局生效，或限定到指定应用的 bundle identifier。' },
    { icon: 'zap', title: '多种动作', desc: '快捷键、打开 App、URL、媒体键、窗口操作、Shell、AppleScript。' },
    { icon: 'languages', title: '中英界面', desc: 'String Catalog 双语；跟随系统或强制深浅色主题。' },
  ]"
/>

<DefaultGestures subheading="默认手势" heading="开箱默认手势" />

<section class="sm-cta">
  <p class="sm-cta__kicker">立即开始使用</p>
  <h2 class="sm-cta__title">三步上手 StrokeMouse</h2>
  <ol class="sm-cta__steps">
    <li>
      <span class="sm-cta__num">1</span>
      <span class="sm-cta__text"><strong>下载安装</strong> — 选择 Apple Silicon 或 Intel 安装包</span>
    </li>
    <li>
      <span class="sm-cta__num">2</span>
      <span class="sm-cta__text"><strong>授权辅助功能</strong> — 设置 → 权限，打开系统开关</span>
    </li>
    <li>
      <span class="sm-cta__num">3</span>
      <span class="sm-cta__text"><strong>画第一笔手势</strong> — 按住右键上滑，触发 Mission Control</span>
    </li>
  </ol>
  <div class="sm-cta__actions">
    <a class="sm-btn sm-btn--primary" href="/download">立即下载</a>
    <a class="sm-btn sm-btn--ghost" href="/guide/getting-started">查看快速开始</a>
  </div>
</section>

</div>
