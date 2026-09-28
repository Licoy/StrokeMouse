# 曲线识别验证报告

> **历史快照（curve-signature-v1）**：本文记录 v1 合成语料设计与当时的 607 项测试、性能结果，其中“没有真实轨迹”和“不使用有限对齐”等描述已不代表当前实现；真实同形 a 数据、`curve-signature-v2` 有限有序对齐及最新验证见 [真实小写 a 曲线识别修复](./real-a-recognition-fix.md)。

## 范围与证据边界

本次变更使用确定性合成语料验证 `eight`、`S`、`epsilon`、`D`、`O`、`C`、`R`、`G`、`U`。目前没有 Issue 对应的真实用户轨迹，因此这些结果不能证明真实场景已经达到 90% 或 95% 的识别率。匹配器公开 `TemplateMatcher.algorithmVersion = curve-signature-v1`，后续真实诊断日志可以据此确认使用的算法版本。

曲线通道只根据录制模板选择一次。进入该通道后，重绘轨迹直接通过有序转向序列、累计正负转向、闭合比例、uniform-normalized 有序位置，以及 offset 为 2、4、8 的多尺度切线差异完成验证，不会在失败后重试第二套算法。已有直线、折线与圆角单转向模板继续使用旧结构门控和 canonical path。

## 旧算法失败基线

独立 Swift harness 直接编译改动前仓库中的 `Constants`、`PathSimplifier`、`UnistrokeGeometry`、结构识别文件和 `TemplateMatcher`。一条确定性的 17 点八字形，宽度比例 `0.55`、高度比例 `1.30`、phase warp `0.65`，与 128 点参考模板比较后得到：

```text
score=0.6949868119040983
shapeScore=0.6949868119040983
structuralMismatch=nil
stroke/template segments=5/7
```

默认阈值为 `0.70`。该样本失败于几何分数，而非结构拒绝，因此需要把保形弧长采样与旧 RDP 结构分析拆开。这个极端宽高变化只用于记录旧算法边界；新的 uniform normalization 会保留宽高比，所以报告不把它列为必须接受的目标样本。

## 合成语料

`CurveRecognitionTests` 中的语料分为：

- 训练集：9 个字形各自进行一次精确 self-match。
- 校准集：18 个变体，覆盖两种采样密度、非线性输入速度、`±8°` 旋转，以及小幅 X/Y 局部比例变化。
- 附加合成回归集：9 个原 holdout 变体，使用另一种采样数量、phase warp、`5°` 旋转、局部变形和确定性 jitter。该集合在开发过程中暴露过 R 的失败，并用于定位 stroke 侧 `isCurve` 二次分类门槛，因此不能视为独立盲测，也不能据此估计泛化率。
- 跨字形混淆：不同字形之间的全部 72 个有向组合必须低于 `0.60`。
- 安全负例：反向、非等价镜像轨迹、错误起点、截断、新增末段，以及 15%/30%/70% 尾巴必须低于 `0.60`；额外再画一圈也必须拒绝。
- 旧结构契约：右后折返、尖锐 V 和现有复杂锯齿折线不得进入曲线通道。旧套件继续验证 8% 短尾允许、10% 新转折拒绝，以及累计 6%+6% 碎尾拒绝。
- 兼容性：同一条 raw epsilon 曲线分别匹配旧 32 点模板与新 128 点录制模板。

冻结实现后，离线 before/after harness 使用完全相同的输入分别编译旧 matcher 与最终 matcher，结果如下：

| 语料 | 旧 matcher | 新 matcher |
|---|---:|---:|
| 校准集召回 | 15/18 | 18/18 |
| 附加合成回归集召回 | 8/9 | 9/9 |
| 分数达到或超过 0.60 的跨字形组合 | 0/72 | 0/72 |

随后独立执行 `/tmp/curve-corpus-old` 与 `/tmp/curve-corpus-new`，复核得到相同输出。

旧 matcher 未通过两个 `D` 校准变体、一个 `G` 校准变体及一个 `D` 附加回归变体。以上只能说明最终实现在这组合成语料上改善了召回，且没有增加该混淆矩阵内的负例。真正独立的验收仍需新的真实轨迹，或在实现冻结后收集且开发过程中未见过的数据。

最终仓库级 Debug 测试执行 607 项，其中 1 项 opt-in 性能测试跳过，0 failures。结果包：`/tmp/strokemouse-issue17-final-debug.xcresult`；日志：`/tmp/strokemouse-issue17-final-debug.log`。

## 实时反馈

Live evaluation 仍然每 4 个有效采样点执行一次，并保留连续 3 次 unlikely 的 hysteresis。未完成的闭合曲线不会获得伪造的 hope 分数，也不会绕过终态匹配。

仅在 HUD 反馈中，当前轨迹会与闭合曲线模板的 35%、50%、65%、80% 有序前缀进行实际比较，仍使用 uniform position 与多尺度 tangent distance。终态识别不调用这条路径。测试同时要求长锯齿轨迹面对 `O` 模板时进入 unlikely，避免注册闭合模板后任意开放乱画都保持 viable。

## Release 性能

性能数据来自本机 arm64 Mac、Xcode Release 优化，并启用 testability。每个数值是在一次 warm-up 后执行 100 次并取 nearest-rank P95。终态识别调用真实的 `GestureRecognitionEvaluator.evaluateDrawn`；实时识别使用全部预处理样本模板。

```text
50 profiles x 3 samples: end P95 3.230584 ms
50 profiles x 3 samples: live P95 2.999000 ms
100 profiles x 5 samples: end P95 10.572667 ms
100 profiles x 5 samples: live P95 10.276333 ms
```

要求的 50×3 边界通过：end 低于 30 ms，live 低于 8 ms。100×5 仅为压力观测，没有设置验收阈值。

测量时曾使用临时 `/tmp/strokemouse-run-curve-benchmark` opt-in sentinel，并在结束后立即删除。最终测试使用 test-host 环境变量，复现命令为：

```bash
TEST_RUNNER_STROKEMOUSE_CURVE_BENCHMARK=1 \
xcodebuild -project StrokeMouse.xcodeproj -scheme StrokeMouse -configuration Release \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath /tmp/strokemouse-curve-release-derived \
  -onlyUsePackageVersionsFromResolvedFile \
  ENABLE_TESTABILITY=YES ONLY_ACTIVE_ARCH=YES ARCHS=arm64 \
  -only-testing:StrokeMouseTests/CurveRecognitionTests/testCurvePerformanceWhenExplicitlyEnabled test
```

成功结果包：`/tmp/strokemouse-curve-release-derived/Logs/Test/Test-StrokeMouse-2026.09.27_22-09-13-+0800.xcresult`。

## DTW 决策

最终没有加入 bounded DTW。预设采用条件是：存在结构检查已通过但仍低于阈值的校准样本，并且离线对比证明 DTW 能提高召回、不增加负例、性能也满足预算。当前合成校准集和附加回归集无需 DTW 即可通过，同时没有真实 Issue 轨迹支持承担额外运行成本与维护成本。

如果后续真实日志出现完全符合上述条件的失败，应先离线比较 64 points、band 4、anchored ends、monotonic 与连续 warp 限制，以及 position+tangent cost，再决定是否进入生产实现。

## 配置恢复边界

独立审查确认：旧配置中如果主模板只含重复点，现在会被明确判定为无效，`ConfigStore` 会进入 `requiresRecovery`，同时保留原文件 bytes。该行为符合新的严格无效样本处理，不能描述成对所有历史无效配置都能无感兼容。

## UI 与实现规模边界

英文环境下的最小尺寸样本编辑器已经单独渲染并完成视觉检查。该结果只证明这一个截图状态，不代替所有语言、外观、窗口尺寸和真实输入设备的人工验收。

`GestureTestLogReplay.swift` 约 469 行，超过项目建议的 300 行目标。日志版本验证、确定性重评和全部候选比较集中在同一个纯 replay 模块中，若仅为行数拆分会增加没有复用价值的接口。其他已有大型模块只做了聚焦增量。`CurveRecognitionTests.swift` 也集中保存同一套确定性字形语料及训练、校准、附加回归、负例和性能检查，避免在多个测试文件中复制几何生成器。
