# Architecture Review Report

**Date**: 2026-05-15 (Third Review)
**Engine**: Godot 4.6
**GDDs Reviewed**: 21 (all in design/gdd/)
**ADRs Reviewed**: 14 (ADR-0001 through ADR-0014)
**Mode**: Full review (all phases)
**Reviewer**: Architecture Review skill + Godot Engine Specialist consultation
**Previous Review**: 5 GDDs, 13 ADRs, 38 requirements, 97% coverage, PASS

---

## Traceability Summary

| Metric | Count | Percentage |
|--------|-------|------------|
| Total requirements | ~137 | 100% |
| Covered | ~108 | 78.8% |
| Partial | ~9 | 6.6% |
| Gaps | ~20 | 14.6% |

**Coverage change since last review**: 97% to 78.8% (scope expanded from 5 to 21 GDDs). Foundation and Core layers remain fully covered. New gaps in Feature and Presentation layers.

---

## Resolved Issues (from previous review)

| Previous Issue | Status | Resolution |
|---------------|--------|------------|
| TR-concept-008: NPC interrogation + conditional dialogue (GAP) | Resolved | ADR-0012 + ADR-0013 |
| TR-concept-006: Countdown pressure (PARTIAL) | Resolved | ADR-0008 |
| TR-concept-011: Pressure rhythm phases (PARTIAL) | Resolved | ADR-0008 |
| TR-concept-014: Save/load persistence (PARTIAL) | Resolved | ADR-0010 |
| Interactable registration conflict (ADR-0006 vs ADR-0007) | Unresolved | Pending Interaction System implementation |

---

## Cross-ADR Conflicts

### Conflict 1: NPC Emotional State Enum Mismatch (HIGH)

**Type**: Integration Contract

- **GDD (npc-state-machine.md)**: NEUTRAL, CURIOUS, ANXIOUS, HOSTILE, TRUSTING, FRIGHTENED
- **ADR-0009**: NEUTRAL, FRIENDLY, SUSPICIOUS, HOSTILE, SECRETIVE, REVEALING
- **Impact**: Only NEUTRAL and HOSTILE match. Transition tables differ. Downstream systems affected.
- **Resolution**: Unify to one enum set. Recommend GDD-driven resolution.

### Conflict 2: BASE_DURATION Inconsistency (MEDIUM)

**Type**: Data Conflict

- **loop-state-management.md**: BASE_DURATION = 300.0 (5 min)
- **countdown-timer.md**: BASE_DURATION = 180.0 (3 min)
- **Resolution**: TimerService owns duration. Loop State references TimerService.

### Conflict 3: ADR-0014 Interface Mismatch (MEDIUM)

**Type**: Integration Contract

ADR-0014 references undefined methods:
- `NPCManager.move_npc_to_room()` not in ADR-0009
- `UIManager.start_dialogue()` should be DialogueManager
- `InteractionBus.dispatch_custom()` not in ADR-0006
- **Resolution**: Update ADR-0014 dispatch table.

### Conflict 4: ADR-0014 Proposed but System Implemented (MEDIUM)

**Type**: Process Violation
- **Resolution**: Accept ADR-0014.

### Conflict 5: Interactable Registration Ownership (Carried Over, MEDIUM)

**Type**: Integration Contract (Review #2, still unresolved)
- **Resolution**: Pending Interaction System implementation.

---

## ADR Dependency Order

No cycles. ADR-0014 is the only Proposed ADR.

```
Foundation (no dependencies):
  1. ADR-0001: Ink Wash Shader Pipeline
  2. ADR-0002: Knowledge Color Accumulation
  3. ADR-0003: UI Visual Register System
  4. ADR-0004: Loop State Management
  5. ADR-0005: Clue/Insight Unified Schema
  6. ADR-0006: Interaction Event Bus

Core (depends on Foundation):
  7. ADR-0007: Room/Location Management (0004, 0006)
  8. ADR-0008: Countdown Timer (0004)
  9. ADR-0009: NPC State Machine (0004, 0006)
  10. ADR-0010: Save/Load Persistence (0004, 0005)

Feature (depends on Core):
  11. ADR-0011: Night Transition Controller (0004, 0007, 0008, 0009, 0010)
  12. ADR-0012: NPC Trust/Suspicion (0004, 0006, 0009)
  13. ADR-0013: Conditional Dialogue Trees (0003, 0004, 0005, 0008, 0009, 0011)
  14. ADR-0014: Event Scheduler (0004, 0007, 0008, 0009, 0011) Proposed
```

---

## Coverage Gaps (no ADR)

| System | GDD | Issue | Priority |
|--------|-----|-------|----------|
| Ink Wash Visual Style (#18) | ink-wash-visual-style.md | VisualStyleManager state machine | MEDIUM-HIGH |
| Guest Interrogation (#15) | guest-interrogation.md | InterrogationManager pressure overlay | MEDIUM |
| Notebook System (#17) | notebook-system.md | NotebookManager read-only view | MEDIUM |
| Ending Trigger Logic (#23) | ending-trigger-logic.md | EndingManager trigger conditions | MEDIUM |
| Clue Discovery (#10) | clue-discovery.md | ClueDefinition condition system | LOW |
| Dialogue UI (#20) | dialogue-ui.md | Panel layout, animations | LOW |

---

## GDD Revision Flags

| GDD | Assumption | Reality | Action |
|-----|-----------|---------|--------|
| npc-state-machine.md | 6 states (NEUTRAL/CURIOUS/ANXIOUS/HOSTILE/TRUSTING/FRIGHTENED) | ADR-0009 uses different enum | Unify |
| countdown-timer.md | BASE_DURATION = 180s | loop-state defines 300s | Coordinate |
| guest-interrogation.md | Uses GDD emotional states | ADR-0009 uses different enum | Follow unification |
| event-scheduler.md | Calls NPCManager.move_npc_to_room() | Not in ADR-0009 | Update |
| event-scheduler.md | Calls UIManager.start_dialogue() | Should be DialogueManager | Update |

---

## Engine Specialist Findings

### Code Issues (from implementation review)

| # | Priority | Issue | File | Action |
|---|----------|-------|------|--------|
| 1 | HIGH | DialoguePanel @onready dead code produces runtime warnings | src/ui/dialogue_panel.gd | Remove @onready, rely on _build_ui() |
| 2 | HIGH | Typewriter Tween O(n) steps (2*N for N chars) | src/ui/dialogue_panel.gd | Refactor to single tween_method |
| 3 | HIGH | find_children("*","") scans entire subtree | src/core/room_manager.gd | Use group or typed filter |
| 4 | MEDIUM | register_consequence mutates in-place (immutability violation) | src/core/loop_state_manager.gd | New-array construction |
| 5 | MEDIUM | InteractionBus _process runs every frame when idle | src/core/interaction_bus.gd | set_process(false) when empty |
| 6 | MEDIUM | VisualParams factory mutates returned object | src/rendering/visual_style_manager.gd | Accept config params |
| 7 | MEDIUM | ADR-0004 duplicate_deep text misleading; code uses Dictionary.duplicate(true) | ADR-0004 | Update ADR comment |
| 8 | MEDIUM | ADR-0013 TrustManager lookup pattern differs from implementation | ADR-0013 | Sync ADR with code |
| 9 | LOW | InkWashDriver writes shader params every frame unchanged | src/rendering/ink_wash_driver.gd | Add dirty flag |
| 10 | LOW | Room navigation data hardcoded | src/ui/room_navigation_ui.gd | Extract to Resource |
| 11 | LOW | Room visual configs hardcoded | src/rendering/visual_style_manager.gd | Extract to Resource |
| 12 | LOW | 18 autoloads with implicit ordering | project.godot | Create order manifest |

### Verified Non-Issues

- Glow before tonemapping: does NOT affect canvas_item shaders
- Curve Resource API: stable across 4.4-4.6
- Tween animations: no breaking changes in 4.4-4.6
- PackedScene instantiate + queue_free: correct pattern
- Shader parameter writing: code correctly uses set_shader_parameter()
- Deprecated APIs: none found across all 14 ADRs

---

## Autoload Registration Order (18 autoloads)

| # | Autoload | ADR |
|---|----------|-----|
| 1 | LoopStateManager | ADR-0004 |
| 2 | InteractionBus | ADR-0006 |
| 3 | SaveManager | ADR-0010 |
| 4 | TimerService | ADR-0008 |
| 5 | ClueDatabase | ADR-0005 |
| 6 | RoomManager | ADR-0007 |
| 7 | NPCManager | ADR-0009 |
| 8 | NightTransitionController | ADR-0011 |
| 9 | ClueDiscoveryManager | -- |
| 10 | ColorAccumulationManager | ADR-0002 |
| 11 | EventScheduler | ADR-0014 |
| 12 | TrustSuspicionManager | ADR-0012 |
| 13 | ClueConnectionManager | -- |
| 14 | DialogueManager | ADR-0013 |
| 15 | InterrogationManager | -- |
| 16 | VisualStyleManager | -- |
| 17 | DialoguePanel | -- |
| 18 | NotebookManager | -- |

---

## Verdict: CONCERNS

Foundation and Core fully covered. Feature and Presentation layers have ADR gaps. 3 issues require immediate resolution.

### Blocking Issues

1. NPC emotional state enum conflict (downstream systems affected)
2. BASE_DURATION inconsistency (impacts game duration)
3. ADR-0014 must be Accepted (process violation)

### Required ADRs (prioritized)

1. `/architecture-decision ink-wash-visual-style` (System #18)
2. `/architecture-decision guest-interrogation` (System #15)
3. `/architecture-decision notebook-system` (System #17)
4. `/architecture-decision ending-trigger-logic` (System #23)

### Recommended Code Fixes (prioritized)

1. DialoguePanel @onready dead code
2. Typewriter Tween refactor
3. find_children wildcard fix
4. InteractionBus idle-process guard
5. register_consequence immutability

---

## History

| Date | Review | ADRs | GDDs | Reqs | Covered | Partial | Gaps | Verdict |
|------|--------|------|------|------|---------|---------|------|---------|
| 2026-05-14 | 1 | 7 | 4 | 28 | 23 (82%) | 4 (14%) | 1 (4%) | CONCERNS |
| 2026-05-14 | 2 | 13 | 5 | 38 | 37 (97%) | 1 (3%) | 0 | PASS |
| 2026-05-15 | 3 | 14 | 21 | ~137 | ~108 (79%) | ~9 (7%) | ~20 (14%) | CONCERNS |
