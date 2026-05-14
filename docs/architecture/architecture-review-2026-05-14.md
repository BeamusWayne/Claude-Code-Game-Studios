# Architecture Review Report

**Date**: 2026-05-14 (Second Review)
**Engine**: Godot 4.6
**GDDs Reviewed**: 5 (game-concept.md, loop-state-management.md, clue-database.md, room-location-management.md, systems-index.md)
**ADRs Reviewed**: 13 (ADR-0001 through ADR-0013)
**Mode**: Full review (all phases)
**Reviewer**: Architecture Review skill + Godot Engine Specialist consultation
**Previous Review**: 7 ADRs, 28 requirements, 82% coverage, CONCERNS

---

## Traceability Summary

| Metric | Count | Percentage |
|--------|-------|------------|
| Total requirements | 38 | 100% |
| Covered | 37 | 97.4% |
| Partial | 1 | 2.6% |
| Gaps | 0 | 0% |

**Coverage improvement since last review**: +15 percentage points (82% -> 97%)
**Key driver**: ADR-0008 through ADR-0013 resolved all previous gaps and partials. room-location-management GDD added 10 new requirements, all covered by ADR-0007.

---

## Resolved Issues (from previous review)

| Previous Issue | Status | Resolution |
|---------------|--------|------------|
| TR-concept-008: NPC interrogation + conditional dialogue (GAP) | **Resolved** | ADR-0012 (Trust/Suspicion) + ADR-0013 (Conditional Dialogue) |
| TR-concept-006: Countdown pressure (PARTIAL) | **Resolved** | ADR-0008 (Countdown Timer) |
| TR-concept-011: Pressure rhythm phases (PARTIAL) | **Resolved** | ADR-0008 (Countdown Timer) |
| TR-concept-014: Save/load persistence (PARTIAL) | **Resolved** | ADR-0010 (Save/Load Persistence) |

---

## Remaining Partial Coverage

### TR-concept-010: Cross-Platform Support
- **ADR Coverage**: ADR-0006 (touch/mouse input), ADR-0003 (mobile UI adaptations)
- **Gap**: No dedicated platform/export strategy ADR. Godot handles cross-platform export natively.
- **Priority**: LOW -- game-design-level cross-platform requirements covered; export configuration is project setup, not architecture decision.

---

## Cross-ADR Conflicts

### Conflict 1: ADR-0006 vs ADR-0007 -- Interactable Registration Ownership (MEDIUM)

**Type**: Integration Contract

- **ADR-0006**: Interactable components self-register in `_ready()` by calling `InteractionBus.register_interactable()`
- **ADR-0007 + Room GDD Rule 5.1**: RoomManager owns registration. Interactable components do NOT self-register. RoomManager calls `Interactable.get_registration_info()` in POST_LOAD.

**Impact**: If both behaviors are implemented, Interactables register twice (once from `_ready()`, once from RoomManager POST_LOAD).

**Resolution options**:
1. Amend ADR-0006: Remove self-registration, defer to RoomManager lifecycle
2. Amend ADR-0007: Accept self-registration, change RoomManager to unregister-only
3. Resolve in Interaction System GDD (#7) -- room GDD Open Question #1 already flags this

**Recommendation**: Option 1 is cleaner. Flag for resolution when Interaction System GDD (#7) is authored.

### Conflict 2: ADR-0004 Interface vs GDD Refined Interface (MEDIUM)

**Type**: Integration Contract

ADR-0004's code block defines a simplified `register_consequence()` interface. The GDD (loop-state-management.md) defines a more refined interface with `propose_delta()`, `register_consequence()`, and `register_state_paths()`.

**Resolution**: GDD interface supersedes ADR simplified examples. Add a note to ADR-0004 that code blocks are illustrative and the GDD interface is canonical.

### Conflict 3: ADR-0003 vs ADR-0006 -- HUD Seal Button Routing (LOW)

**Type**: Integration Contract

- ADR-0003: "HUD seal buttons are interactables"
- ADR-0006: "UI controls (CanvasLayer 30+) bypass InteractionBus"

**Resolution**: HUD buttons use Godot Button signals, not InteractionBus. Update ADR-0003 wording.

### Conflict 4: ADR-0004 Signal Contract -- GDD vs ADR Discrepancy (LOW)

**Type**: Integration Contract

GDD defines signals not in ADR (`night_ended_final`, `state_changed`, `consequence_registered`). ADR defines signals not in GDD (`night_advanced_failed`, `consequence_replayed`).

**Resolution**: Merge both sets. GDD is canonical for game-design signals; ADR supplements with error-handling signals.

---

## ADR Dependency Order (Topologically Sorted)

No dependency cycles detected. All 13 ADRs are Accepted. No unresolved dependencies.

```
Foundation (no dependencies):
  1. ADR-0001: Ink Wash Shader Pipeline
  2. ADR-0002: Knowledge Color Accumulation
  3. ADR-0003: UI Visual Register System
  4. ADR-0004: Loop State Management
  5. ADR-0005: Clue/Insight Unified Schema
  6. ADR-0006: Interaction Event Bus

Core layer (depends on Foundation):
  7. ADR-0007: Room/Location Management (requires 0004, 0006)
  8. ADR-0008: Countdown Timer (requires 0004)
  9. ADR-0009: NPC State Machine (requires 0004, 0006)
  10. ADR-0010: Save/Load Persistence (requires 0004, 0005)

Feature layer (depends on Core):
  11. ADR-0011: Night Transition Controller (requires 0004, 0007, 0008, 0009, 0010)
  12. ADR-0012: NPC Trust/Suspicion (requires 0004, 0006, 0009)

Feature layer (depends on Feature):
  13. ADR-0013: Conditional Dialogue Trees (requires 0003, 0004, 0005, 0008, 0009, 0011; soft-dep 0012)
```

---

## GDD Revision Flags

| GDD | Issue | Action |
|-----|-------|--------|
| room-location-management.md (Open Q #1) | Interactable registration conflict with ADR-0006 | Resolve when authoring Interaction System GDD (#7) |

All other GDD assumptions consistent with verified engine behavior.

---

## Engine Compatibility Issues

### Knowledge Risk Distribution

10 of 13 ADRs claim LOW knowledge risk. 3 claim HIGH:
- ADR-0001 (Shader): SCREEN_TEXTURE + 4.6 glow rework interaction
- ADR-0002 (Knowledge): Per-NPC saturation formulas depend on shader behavior
- ADR-0003 (UI Visual Register): CanvasLayer ordering + dual-focus (4.6 feature)

All HIGH-risk ADRs correctly flag their concerns and specify verification requirements.

### Engine Specialist Findings

| Priority | Issue | ADR | Action |
|----------|-------|-----|--------|
| Medium | `duplicate_deep()` on Dictionary vs Resource -- ADR says `_active_state.duplicate_deep()` but active state may be a Dictionary | ADR-0004 | Clarify in implementation: use `Dictionary.duplicate(true)` or restructure active state as Resource |
| Medium | TrustManager lookup via `Engine.get_main_loop().root.get_node_or_null()` -- fragile, not cached | ADR-0013 | Cache autoload reference on first successful lookup; use `get_node_or_null("/root/TrustManager")` |
| Medium | No autoload registration order manifest -- 12 autoloads have implicit ordering dependencies | All | Create autoload order manifest in technical preferences or dedicated document |
| Low-Medium | Touch-to-Area2D `input_event` propagation depends on `Input.emulate_mouse_from_touch` Project Setting | ADR-0006 | Document required Project Settings configuration for touch |
| Low | Typewriter Tween creates O(n) steps per character -- consider `tween_method` for single interpolation | ADR-0013 | Optimization for mobile; not blocking for MVP |
| Low | `find_children("*")` scans entire subtree when Interactables container is known | ADR-0007 | Iterate container's children directly for cleaner architecture |

### Deprecated API Usage

None found across all 13 ADRs.

### Stale Version References

None -- all ADRs target Godot 4.6.

---

## Autoload Architecture

**12 Autoload singletons** defined across 13 ADRs:

| Order | Autoload | ADR | Depends On |
|-------|----------|-----|------------|
| 1 | LoopStateManager | ADR-0004 | -- |
| 2 | InteractionBus | ADR-0006 | -- |
| 3 | ClueDatabase | ADR-0005 | LoopStateManager |
| 4 | KnowledgeManager | ADR-0002 | ClueDatabase |
| 5 | UIManager | ADR-0003 | -- |
| 6 | RoomManager | ADR-0007 | LoopStateManager, InteractionBus |
| 7 | TimerService | ADR-0008 | LoopStateManager |
| 8 | NPCManager | ADR-0009 | LoopStateManager, InteractionBus |
| 9 | TrustManager | ADR-0012 | LoopStateManager, NPCManager |
| 10 | SaveManager | ADR-0010 | Multiple systems |
| 11 | NightTransitionController | ADR-0011 | All above |
| 12 | DialogueManager | ADR-0013 | NPCManager, ClueDatabase, TimerService, UIManager, TrustManager |

---

## System Coverage (from systems-index.md)

| Layer | Total | With ADR | With GDD | No ADR |
|-------|-------|----------|----------|--------|
| Foundation | 4 | 4 (#1-4) | 3 (#1,3,4) | 0 |
| Core | 6 | 6 (#5-8,16,17) | 3 (#5,7,16) | 0 |
| Feature | 8 | 4 (#10-12,23) | 1 (#10) | 4 (#9,13-15) |
| Presentation | 6 | 0 | 0 | 6 (#18-22,24) |
| Polish | 1 | 0 | 0 | 1 (#25) |

**System count with ADR**: 14/25 (56%)
**System count with GDD**: 7/25 (28%)

---

## Verdict: PASS

All Foundation and Core requirements covered by Accepted ADRs. No blocking conflicts. Previous gaps (NPC interrogation, countdown timer, save/load, night transition) all resolved by ADR-0008 through ADR-0013.

### Non-Blocking Items (implement when relevant GDD is authored)

1. **TR-concept-010** (Cross-platform): Partial -- LOW priority, Godot handles natively
2. **Interactable registration conflict** (ADR-0006 vs ADR-0007): Resolve when authoring Interaction System GDD (#7)
3. **Autoload order manifest**: Create centralized document for 12-Autoload load order
4. **Engine specialist findings**: 3 Medium, 1 Low-Medium, 2 Low items -- address during implementation

### Next Steps

1. Run `/gate-check pre-production` to validate readiness for Pre-Production phase
2. Author remaining GDDs (Interaction System #7, Event Scheduler #9, NPC systems #13-15)
3. Create ADRs for Presentation layer systems (#18-24) when their GDDs are complete
