# ADR-0001: Ink Wash Shader Pipeline

## Status
Accepted

## Date
2026-05-14

## Engine Compatibility

| Field | Value |
|-------|-------|
| **Engine** | Godot 4.6 |
| **Domain** | Rendering |
| **Knowledge Risk** | HIGH — Godot 4.6 is post-LLM-cutoff (LLM covers ~4.3) |
| **References Consulted** | docs/engine-reference/godot/VERSION.md, docs/engine-reference/godot/breaking-changes.md, prototypes/ink-wash-shader/REPORT.md |
| **Post-Cutoff APIs Used** | None — SCREEN_TEXTURE and canvas_item shaders exist since Godot 4.0 |
| **Verification Required** | Test glow behavior in 4.6 (processes before tonemapping) — may affect vignette blending. Test mobile half-resolution rendering for performance. |

## ADR Dependencies

| Field | Value |
|-------|-------|
| **Depends On** | None |
| **Enables** | ADR-0002 (knowledge-color-accumulation) — shader uniforms defined here; System #17 (计时器/倒计时) — pressure_level uniform allows timer system (ADR-0003 timer seal) to drive ink wash behavior under time pressure |
| **Blocks** | System #18 (水墨视觉风格), System #19 (计时器/HUD UI — timer crack visual depends on ink wash) |
| **Ordering Note** | Must be Accepted before ADR-0002. ADR-0002 defines what drives the knowledge_level uniform; this ADR defines how the uniform is consumed. |

## Context

### Problem Statement

七夜的核心视觉身份是水墨画风格——一个近乎单色的世界，随着玩家发现真相而获得色彩。游戏需要一个渲染管线实现：(1) 全场景水墨渲染（纸纹、墨密度、干笔质感），(2) 基于玩家知识水平的动态色彩恢复，(3) 可独立控制的雨覆盖层。着色器是整个视觉系统成败的关键因素。

### Constraints

- 目标 60fps，帧预算 16.6ms
- 着色器 GPU 时间总计 ≤3.0ms（墨色 1.5ms + 雨 1.5ms）
- 每片段 <64 ALU 指令，<4 纹理采样
- 兼容移动端集成 GPU
- Godot 4.6 Forward+ 渲染器，2D 优化

### Requirements

- 全场景后处理——不修改单个精灵材质
- knowledge_level 参数（0.0-1.0）控制色彩恢复程度
- 雨效果可独立开关和调节强度
- 纸纹、墨密度、干笔质感作为基础视觉层
- 支持未来每-NPC 颜色饱和度独立控制（ADR-0002 定义公式）

## Decision

采用 SCREEN_TEXTURE canvas_item 着色器的双管线后处理架构。已通过原型验证（prototypes/ink-wash-shader/）。

### Architecture Diagram

```
┌──────────────────────────────────────────┐
│              Game Scene (Node2D)          │
│  Sprites, NPCs, rooms, furniture         │
│  z_index: -10 to 1                       │
└──────────────┬───────────────────────────┘
               │ screen buffer
┌──────────────▼───────────────────────────┐
│  CanvasLayer 10: InkWashPostProcess       │
│  follow_viewport_enabled = true           │
│  ┌────────────────────────────────────┐   │
│  │  ink_wash.gdshader                  │   │
│  │  - SCREEN_TEXTURE → FBM paper grain│   │
│  │  - Luminance → ink density         │   │
│  │  - Three-tone wash thresholds      │   │
│  │    (0.15 light / 0.35 mid / 0.55)  │   │
│  │  - Dry brush texture (vnoise)      │   │
│  │  - Ink pooling (secondary FBM)     │   │
│  │  - Color: smoothstep(ink) × know   │   │
│  │  - Desat: mix(lum, col, 0.2+k*0.5)│   │
│  │  - Vignette framing                │   │
│  │  Uniforms:                         │   │
│  │    knowledge_level (float 0-1)     │   │
│  │    pressure_level (float 0-1)      │   │
│  │    time_value (float)              │   │
│  └────────────────────────────────────┘   │
└──────────────┬───────────────────────────┘
               │
┌──────────────▼───────────────────────────┐
│  CanvasLayer 20: RainOverlay              │
│  follow_viewport_enabled = true           │
│  ┌────────────────────────────────────┐   │
│  │  rain.gdshader                      │   │
│  │  - 3-layer procedural streaks      │   │
│  │  - Different scales/speeds         │   │
│  │  - Bottom mist                     │   │
│  │  Uniforms:                         │   │
│  │    rain_intensity (float 0-1)      │   │
│  │    time_value (float)              │   │
│  └────────────────────────────────────┘   │
└──────────────────────────────────────────┘
               │
┌──────────────▼───────────────────────────┐
│  CanvasLayer 30+: HUD, Dialogue, Notebook │
│  (not affected by ink wash or rain)       │
└──────────────────────────────────────────┘
```

### Key Interfaces

**Shader Uniforms — ink_wash.gdshader**:
- `knowledge_level: float` — range 0.0 (monochrome) to 1.0 (max color restoration)
- `pressure_level: float` — range 0.0 (whisper / calm) to 1.0 (roar / crisis). Driven by the timer system (ADR-0003 timer seal). Affects: ink pooling intensity, vignette darkness, paper grain turbulence, desaturation boost during crisis.
- `time_value: float` — elapsed seconds for subtle paper grain drift

**Shader Uniforms — rain.gdshader**:
- `rain_intensity: float` — range 0.0 (clear) to 1.0 (storm), driven by time-of-night or event system
- `time_value: float` — elapsed seconds for streak animation

**Pressure Visual Effects** — how `pressure_level` modifies the ink wash image:

| Pressure Range | Phase | Visual Behavior |
|----------------|-------|-----------------|
| 0.0 -- 0.3 | Whisper (低语) | Calm ink flow, gentle paper grain drift, soft vignette. Baseline aesthetic. |
| 0.3 -- 0.7 | Transition | Grain drift accelerates (FBM time multiplier scales with pressure), ink pooling increases (secondary FBM amplitude boost), vignette tightens (radius shrinks toward center). |
| 0.7 -- 1.0 | Roar (咆哮) | Heavy ink pooling with visible density spikes, aggressive grain turbulence, tight vignette pulling focus to screen center, slight color desaturation boost (even if knowledge_level is high -- pressure overrides color to reinforce urgency). |

The pressure effects layer on top of the existing knowledge-driven color system. Both uniforms are independent inputs; the shader blends their contributions.

**Color Accumulation Core Formula** (in shader):
```
ink_density = dot(screen_color, vec3(0.299, 0.587, 0.114))
color_restoration = smoothstep(0.25, 0.5, ink_density) * knowledge_level
final_color = mix(luminance, original_color, 0.2 + knowledge_level * 0.5)
```

**GDScript Driver Contract**:
```gdscript
# InkWashPostProcess reads from KnowledgeManager and TimerSystem each frame
func _process(delta: float) -> void:
    ink_material["shader_parameter/knowledge_level"] = KnowledgeManager.knowledge_level
    ink_material["shader_parameter/pressure_level"] = TimerSystem.pressure_level
    ink_material["shader_parameter/time_value"] = time_elapsed
```

> **Engine Note (4.6)**: Use direct property access `material["shader_parameter/name"]`
> instead of `set_shader_parameter()` (Godot 3.x API, removed in 4.0).
> Alternative: `set_shader_uniform()` (Godot 4.x method name).

## Alternatives Considered

### Alternative 1: Per-Sprite Material Shaders

- **Description**: Apply ink_wash.gdshader as material to every sprite individually
- **Pros**: Per-object control; could tint NPCs independently
- **Cons**: N draw calls × material overhead; inconsistent treatment between sprites; every new asset needs the shader; no screen-space effects (vignette, rain)
- **Rejection Reason**: Defeats unified screen-space aesthetic. Performance scales linearly with scene complexity. Prototype proved screen-space approach is cleaner.

### Alternative 2: SubViewport Post-Processing

- **Description**: Render scene to SubViewport, apply shader to SubViewport texture
- **Pros**: Multiple passes possible; can render at lower resolution for mobile
- **Cons**: Extra VRAM for SubViewport texture; one-frame latency; complex scene tree setup
- **Rejection Reason**: SCREEN_TEXTURE achieves same result without VRAM overhead. SubViewport adds latency and complexity.

### Alternative 3: BackBufferCopy + Shader

- **Description**: Use BackBufferCopy node to capture screen, apply shader
- **Pros**: Built-in Godot feature
- **Cons**: Less flexible; region-based not full-screen; poorly documented in 4.x
- **Rejection Reason**: SCREEN_TEXTURE is the idiomatic Godot 4.x approach. BackBufferCopy is a legacy pattern.

## Consequences

### Positive

- Single post-process pass handles entire visual identity — no per-asset shader setup
- knowledge_level is a simple float any system can drive
- Prototype validates visual quality and performance within budget
- Rain and ink wash independently controllable for per-night weather variation
- Vignette grounds the image as "painted on paper"

### Negative

- All game objects must be designed with ink density in mind — dark shapes get heavy ink, light shapes stay paper-white
- Color restoration is global via knowledge_level — per-NPC saturation requires ADR-0002's approach
- UI elements below CanvasLayer 10 will be ink-washed — HUD must render at layer 30+

### Risks

- **Glow rework in 4.6**: Glow processes before tonemapping. May interact with vignette. Mitigation: test in Godot 4.6 editor specifically.
- **Mobile FBM cost**: 4-octave FBM may exceed mobile GPU budget. Mitigation: octave count is the tuning knob — reduce to 2-3 for mobile.
- **Shader complexity ceiling**: Adding per-NPC tinting, transition animations, ink splash VFX may push past <64 ALU. Mitigation: split into passes or use lookup textures.
- **Dual-uniform blending during simultaneous change**: pressure_level adds another real-time uniform. If both knowledge_level and pressure_level change simultaneously (e.g., player discovers a clue during roar phase), the shader must blend both effects smoothly without visual popping. Mitigation: both uniforms already flow through smoothstep/mix chains; ensure pressure desaturation lerps rather than snaps.

## GDD Requirements Addressed

| GDD System | Requirement | How This ADR Addresses It |
|------------|-------------|--------------------------|
| game-concept.md | Visual Identity Anchor: 水墨旅馆 | Dual-shader pipeline produces ink wash rendering with paper grain, ink density, dry brush texture |
| game-concept.md | Pillar 1: 知识 = 色彩 | knowledge_level uniform drives color restoration via smoothstep formula |
| game-concept.md | Pillar 2: 墨色承载时间 | pressure_level uniform drives ink behavior tied to time pressure -- whisper (calm grain, soft vignette) through roar (heavy pooling, tight vignette, desaturation boost). Timer system (ADR-0003 seal) writes this uniform each frame. |
| art-bible.md Sec 1 | 理解褪去墨色；无知保存墨色 | `smoothstep(ink) * knowledge` — color only where ink exists, proportional to knowledge |
| art-bible.md Sec 8 | 着色器 GPU 时间 1.5ms max each | Prototype confirms <3.0ms total for both shaders |
| art-bible.md Sec 8 | <64 ALU, <4 texture samples per fragment | FBM (16 ALU) + vnoise + smoothstep chain — within budget |

## Performance Implications

- **CPU**: Negligible — 3-4 `material["shader_parameter/..."]` property writes per frame (knowledge_level, pressure_level, time_value for ink wash; rain_intensity, time_value for rain)
- **Memory**: ~2MB shader programs; no intermediate render targets
- **GPU**: ~3.0ms total at 1280x720 (prototype estimate). FBM (4 octaves × 2 calls) is main cost. The pressure_level effects use existing FBM and vignette infrastructure -- no additional texture samples required. The FBM amplitude multiplier and vignette radius scaling are scalar operations that stay within the <64 ALU budget.
- **Load Time**: Shader compilation ~100ms at startup. Godot 4.5 Shader Baker could pre-compile.

## Migration Plan

Not applicable — new system. Prototype at `prototypes/ink-wash-shader/` validates the approach but will NOT be migrated. Production code written from scratch per this ADR.

## Validation Criteria

1. knowledge_level = 0.0 produces near-monochrome output (desaturation ≥80%)
2. knowledge_level = 1.0 produces visible color in ink-dense areas (saturation ≥50% original)
3. Paper-white areas remain monochrome at all knowledge levels
4. Both shaders combined ≤3.0ms at 1280x720 on target hardware
5. Rain toggleable without affecting ink wash
6. No visible artifacts (banding, flickering, temporal instability) at 60fps

## Related Decisions

- ADR-0002: Knowledge Color Accumulation — defines knowledge_level calculation and per-NPC saturation
- Art Bible Section 1: Visual Identity Statement
- Art Bible Section 8: Asset Standards (shader budgets)
- Prototype Report: prototypes/ink-wash-shader/REPORT.md
