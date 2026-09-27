---
layout: home
title: "StrokeMouse"
titleTemplate: "macOS のマウス／トラックパッドジェスチャ"
description: "StrokeMouse は macOS のマウス／トラックパッドジェスチャツールです。マウスボタンまたは修飾キー 1 つで軌跡を描くか、実験的なマルチタッチを使い、ショートカットやウインドウ操作、スクリプトを実行します。ホイールは軸ごとに反転でき、段付きホイールは滑らかにできます。"
---

<div class="sm-home">

<GeekHero
  title="マウスとトラックパッドのジェスチャで macOS を動かす"
  tagline="マウスボタンまたは修飾キー 1 つを押したまま軌跡を描くか、実験的なマルチタッチジェスチャを使います。一致するとショートカット、ウインドウ操作、スクリプトを実行します。"
  primary-text="ダウンロード"
  primary-link="/ja/download"
  secondary-text="ドキュメントを読む"
  secondary-link="/ja/guide/getting-started"
  image-src="/screenshots/1.png"
  image-alt="ジェスチャ設定一覧"
  hud-label="軌跡キャプチャ"
/>

<ProofStrip
  :items="['ローカル実行', 'テレメトリなし', 'オープンソース AGPL', 'macOS 14+']"
/>

<PromoVideo
  heading="2 分でわかる StrokeMouse"
  description="入力方法、実行できるアクション、認識のしくみ、3 ステップの導入まで。動画内の文字は簡体字中国語です。"
  play-label="動画を再生"
/>

<ScreenshotCarousel
  heading="製品画面"
  description="ジェスチャライブラリ、テスト、設定、権限。"
  :shots="[
    { src: '/screenshots/1.png', alt: 'ジェスチャ設定一覧' },
    { src: '/screenshots/2.png', alt: 'ジェスチャテスト' },
    { src: '/screenshots/3.png', alt: '一般設定' },
    { src: '/screenshots/4.png', alt: '権限' },
    { src: '/screenshots/5.png', alt: '軌跡の記録' },
    { src: '/screenshots/6.png', alt: 'アプリ範囲' },
  ]"
/>

<HowItWorks
  heading="3 ステップで最初のジェスチャ"
  :steps="[
    { title: 'ダウンロード', desc: 'Apple Silicon または Intel 版をインストールします。' },
    { title: '許可', desc: 'システム設定でアクセシビリティをオンにします。' },
    { title: '入力を選ぶ', desc: 'マウス描画、トラックパッド描画、またはタッチジェスチャ。' },
  ]"
/>

<FeatureBento
  heading="パワーユーザー向けの機能"
  lead="3 つの入力方式がアクションと App 範囲を共有します。描いた軌跡は制御可能なマッチングを使います。スクロール強化は別設定で、この Mac にだけ残ります。"
  :items="[
    { icon: 'sparkles', title: '自由軌跡マッチング', desc: '正規化、制限付き回転、折れ曲がり構造ゲートで、いい加減な近傍一致を拒否します。', size: 'large', image: '/screenshots/5.png', imageAlt: '軌跡の記録' },
    { icon: 'menu', title: 'メニューバー常駐', desc: 'ジェスチャの開始／停止と設定を開きます。一時停止や権限不足でアイコンの色が変わります。' },
    { icon: 'mouse', title: 'マウス描画', desc: '右、中、サイドボタンでトリガー。有効な設定が使うボタンだけを監視します。' },
    { icon: 'sparkles', title: 'トラックパッド描画', desc: 'Fn、Control、Option、Shift、Command のどれか 1 つを押したままポインタを動かします。マウス描画のルールを再利用できます。' },
    { icon: 'zap', title: '実験的タッチジェスチャ', desc: '34 種類の複数指タップ、スワイプ、ピンチ、スプレッド、回転。システムジェスチャが同時に起きることがあります。' },
    { icon: 'mouse', title: 'スクロール強化', desc: 'マウスホイールとトラックパッドを軸ごとに反転し、段付きホイールを滑らかにします。ジェスチャのバックアップには入りません。', href: '/guide/settings#scroll-enhancement' },
    { title: '一般設定', desc: '一致しきい値、外観、タッチジェスチャのマスタースイッチ。', size: 'media', image: '/screenshots/3.png', imageAlt: '一般設定' },
    { icon: 'window', title: 'App 範囲', desc: 'グローバルまたは App ごと。サイドバーが範囲でジェスチャをまとめます。' },
    { icon: 'import', title: 'アクションと読み込み', desc: 'ショートカット、ウインドウ、メディア、Shell と AppleScript。JSON で一括管理します。' },
  ]"
/>

<GestureTiles
  heading="デフォルトのマウス描画"
  lead="インストール直後から使える軌跡。すべてカスタマイズできます。"
/>

<HomeCta
  heading="StrokeMouse を始める"
  lead="ローカルで動きます。3 つの入力がアクションと App 範囲を共有し、設定は JSON で読み書きできます。"
  :steps="['チップに合ったビルドをダウンロード', 'アクセシビリティを許可', '入力を選び、最初のジェスチャを設定']"
  primary-text="ダウンロード"
  primary-link="/ja/download"
  secondary-text="ドキュメントを読む"
  secondary-link="/ja/guide/getting-started"
/>

</div>
