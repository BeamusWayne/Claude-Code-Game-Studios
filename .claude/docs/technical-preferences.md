# Technical Preferences

## Engine & Language

- **Engine**: Godot 4.6
- **Language**: GDScript
- **Rendering**: Godot 4 Forward+ (2D optimized)
- **Physics**: Jolt (Godot 4.6 default)

## Input & Platform

- **Target Platforms**: PC (Steam) + macOS (primary), mobile (iOS/Android) portability
- **Input Methods**: Keyboard/Mouse (primary), Touch (mobile)
- **Primary Input**: Keyboard/Mouse (point-and-click)
- **Gamepad Support**: Partial (recommended)
- **Touch Support**: Full (design all interactions touch-friendly for mobile portability)
- **Platform Notes**: All UI must support both mouse click and touch tap. No hover-only interactions. Design anchors for 16:9 (PC) and 19.5:9 (modern phones) aspect ratios.

## Naming Conventions

- **Classes**: PascalCase (e.g., `PlayerController`)
- **Variables/functions**: snake_case (e.g., `move_speed`)
- **Signals**: snake_case past tense (e.g., `health_changed`)
- **Files**: snake_case matching class (e.g., `player_controller.gd`)
- **Scenes**: PascalCase matching root node (e.g., `PlayerController.tscn`)
- **Constants**: UPPER_SNAKE_CASE (e.g., `MAX_HEALTH`)

## Performance Budgets

- **Target Framerate**: 60 fps
- **Frame Budget**: 16.6 ms
- **Draw Calls**: Keep under 100 per frame (2D with shader effects)
- **Memory Ceiling**: 512 MB (mobile-safe baseline)

## Testing

- **Framework**: GDUnit4
- **Minimum Coverage**: 80%
- **Required Tests**: Loop state management, clue connection logic, NPC dialogue conditions, save/load persistence

## Forbidden Patterns

- [None configured yet — add as architectural decisions are made]

## Allowed Libraries / Addons

- [None configured yet — add as dependencies are approved]

## Architecture Decisions Log

- ADR-0001: Ink Wash Shader Pipeline — Accepted (2026-05-14)
- ADR-0002: Knowledge Color Accumulation — Accepted (2026-05-14)
- ADR-0003: UI Visual Register System — Accepted (2026-05-14)
- ADR-0004: Loop State Management — Accepted (2026-05-14)
- ADR-0005: Clue/Insight Unified Schema — Accepted (2026-05-14)
- ADR-0006: Interaction Event Bus — Accepted (2026-05-14)
- ADR-0007: Room/Location Management — Accepted (2026-05-14)
- ADR-0008: Countdown Timer System — Accepted (2026-05-14)
- ADR-0009: NPC State Machine — Accepted (2026-05-14)
- ADR-0010: Save/Load Persistence — Accepted (2026-05-14)
- ADR-0011: Night Transition Controller — Accepted (2026-05-14)
- ADR-0012: NPC Trust/Suspicion — Accepted (2026-05-14)
- ADR-0013: Conditional Dialogue Trees — Accepted (2026-05-14)
- ADR-0014: Event Scheduler — Accepted (2026-05-15)

## Engine Specialists

- **Primary**: godot-specialist
- **Language/Code Specialist**: godot-gdscript-specialist (all .gd files)
- **Shader Specialist**: godot-shader-specialist (.gdshader files, VisualShader resources)
- **UI Specialist**: godot-specialist (no dedicated UI specialist — primary covers all UI)
- **Additional Specialists**: godot-gdextension-specialist (GDExtension / native C++ bindings only)
- **Routing Notes**: Invoke primary for architecture decisions, ADR validation, and cross-cutting code review. Invoke GDScript specialist for code quality, signal architecture, static typing enforcement, and GDScript idioms. Invoke shader specialist for material design and shader code. Invoke GDExtension specialist only when native extensions are involved.

### File Extension Routing

| File Extension / Type | Specialist to Spawn |
|-----------------------|---------------------|
| Game code (.gd files) | godot-gdscript-specialist |
| Shader / material files (.gdshader, VisualShader) | godot-shader-specialist |
| UI / screen files (Control nodes, CanvasLayer) | godot-specialist |
| Scene / prefab / level files (.tscn, .tres) | godot-specialist |
| Native extension / plugin files (.gdextension, C++) | godot-gdextension-specialist |
| General architecture review | godot-specialist |
