# 倒计时系统 (Countdown Timer System)

## 1. Overview

倒计时系统管理每夜的有限时间，将时间进度映射为压力值（pressure_level 0.0-1.0），驱动水墨着色器的视觉强度变化。系统在三个压力阶段（低语 CALM、激昂 INTENSE、危急 CRITICAL）之间转换，每个阶段转换发出信号通知下游系统（事件调度器、HUD UI、音频系统）。计时器支持变速（对话期间 50% 减速），序列化完整状态用于存档。

## 2. Player Fantasy

**"心跳加速的紧迫感"** — 玩家感受到时间流逝的物理压力。低语阶段，世界安静而缓慢，像水墨在宣纸上慢慢洇开；激昂阶段，墨色加深，雨声变大，NPC 开始焦虑；危急阶段，画面几乎全黑，时间仿佛凝固又飞逝——迫使玩家做出最后的行动选择。

## 3. Detailed Rules

### 3.1 计时器生命周期

1. 每夜开始时，`LoopStateManager.night_ready` 信号触发 `TimerService.start_night_timer()`
2. 计时器从 `total_duration` 倒数到 0
3. 每帧减少 `delta * time_scale` 秒
4. 倒数至 0 时发出 `night_timer_ended` 信号，不直接调用 `advance_night()`
5. 夜晚过渡期间 `time_scale = 0.0`（暂停）

### 3.2 压力曲线

- 使用 Godot `Curve` Resource，默认线性 `(0,0)→(1,1)`
- 输入：progress = 1.0 - (remaining_time / total_duration)
- 输出：pressure_level (0.0-1.0)
- 设计师可在编辑器调整曲线节点创建非线性节奏

### 3.3 压力阶段

| 阶段 | progress 范围 | pressure 范围 | 对应 ADR-0001 |
|------|--------------|--------------|---------------|
| CALM | 0.0 - 0.3 | 0.0 - 0.3 | Whisper |
| INTENSE | 0.3 - 0.7 | 0.3 - 0.7 | Transition |
| CRITICAL | 0.7 - 1.0 | 0.7 - 1.0 | Roar |

阶段转换条件：pressure_level 跨越阈值时立即触发 `phase_changed` 信号。

### 3.4 变速控制

| 场景 | time_scale | 说明 |
|------|-----------|------|
| 正常游戏 | 1.0 | 默认 |
| 对话中 | 0.5 | ADR-0003 要求 |
| 暂停/菜单 | 0.0 | 完全暂停 |
| 夜晚过渡 | 0.0 | 过渡期间不计时 |
| 房间切换 | 1.0 | 不暂停（切换 < 1秒） |

### 3.5 每夜时长

每夜时长由 `NightSchedule` Resource 定义，允许设计师为每夜配置不同时长。

## 4. Formulas

### 压力计算

```
progress = 1.0 - clampf(remaining_time / total_duration, 0.0, 1.0)
pressure_level = pressure_curve.sample(progress)
```

### 默认每夜时长

```
BASE_DURATION = 180.0  // 秒（3 分钟）
```

MVP 阶段所有夜晚使用相同时长。未来可通过 `NightSchedule` 为不同夜晚配置不同时长。

### 阶段判定

```
if pressure_level < CALM_THRESHOLD (0.3):
    phase = CALM
elif pressure_level < CRITICAL_THRESHOLD (0.7):
    phase = INTENSE
else:
    phase = CRITICAL
```

## 5. Edge Cases

| 场景 | 行为 |
|------|------|
| 计时器已结束时再次收到 night_ready | 重置并开始新计时（先 stop 再 start） |
| time_scale = 0 时 remaining_time 不变 | 正确——delta * 0 = 0 |
| total_duration = 0 | 不启动计时器，立即发出 night_timer_ended |
| 存档时计时器在 INTENSE 阶段 | 序列化 remaining_time 和 pressure_level，读档恢复到精确时刻 |
| advance_night 在计时器未结束时触发 | 计时器停止（night_advanced → stop_timer） |
| 多个系统同时设置 time_scale | 最后一个设置生效，调用方负责恢复原值 |

## 6. Dependencies

### 上游依赖
- **循环状态管理 (#1)** — 读取 `current_night`，监听 `night_ready`、`night_advanced` 信号
- **存档/读档持久化 (#4)** — TimerService 提供 `serialize()`/`deserialize()` 接口

### 下游被依赖
- **水墨视觉风格 (#18)** — 消费 `pressure_level` 写入 shader uniform
- **事件调度器 (#9)** — 监听 `phase_changed` 触发阶段相关事件
- **计时器/HUD UI (#19)** — 读取 `remaining_time` 和 `pressure_level` 显示
- **音频系统 (#24)** — 监听 `phase_changed` 切换音乐/环境音

## 7. Tuning Knobs

| 参数 | 类型 | 默认值 | 范围 | 影响 |
|------|------|--------|------|------|
| BASE_DURATION | float | 180.0 | 60.0-600.0 | 每夜总时长（秒） |
| CALM_THRESHOLD | float | 0.3 | 0.1-0.5 | 低语→激昂阶段转换点 |
| CRITICAL_THRESHOLD | float | 0.7 | 0.5-0.9 | 激昂→危急阶段转换点 |
| DIALOGUE_TIME_SCALE | float | 0.5 | 0.0-1.0 | 对话期间计时速度 |
| pressure_curve | Curve | linear | — | 压力曲线形状 |

## 8. Acceptance Criteria

1. 每夜倒计时从配置时长倒数至 0，误差 < 0.1 秒
2. pressure_level 从 0.0 平滑升至 1.0，每帧更新
3. 三个阶段转换信号正确触发（CALM→INTENSE→CRITICAL）
4. 对话期间 time_scale = 0.5，倒计时速度减半
5. time_scale = 0 时 remaining_time 不变
6. night_timer_ended 信号在 remaining_time <= 0 时触发
7. serialize/deserialize 保存并恢复 remaining_time 和 pressure_level
8. reset() 恢复到初始非活跃状态
9. advance_night 信号正确停止当前计时器
10. 三个阶段阈值与 ADR-0001 shader 压力分段对齐

## Open Questions

- 是否需要"暂停菜单"期间完全停止计时（time_scale = 0.0），还是允许玩家在菜单中继续消耗时间？
- 未来扩展：`NightSchedule` 是否应支持非线性时长（夜 1: 180s, 夜 4: 120s, 夜 7: 90s）？
