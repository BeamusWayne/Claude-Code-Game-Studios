# Epic: Foundation

**Layer**: Foundation
**Status**: Planning
**ADRs**: ADR-0001, ADR-0004, ADR-0006, ADR-0010
**GDDs**: game-concept.md, loop-state-management.md, systems-index.md

## Goal

Implement the four systems with zero external dependencies that all other game
systems build upon: the time-loop state backbone, the interaction event bus,
the ink-wash rendering pipeline, and the save/load persistence coordinator.

## Stories

| # | Title | Type | TR-IDs | ADR | Status |
|---|-------|------|--------|-----|--------|
| 001 | Loop State Manager -- three-layer state model and advance_night | Logic | TR-loop-001, TR-loop-002, TR-loop-006, TR-loop-007, TR-loop-008 | ADR-0004 | Planning |
| 002 | Loop State Manager -- propose_delta entry point and conflict resolution | Logic | TR-loop-003, TR-loop-004, TR-loop-005 | ADR-0004 | Planning |
| 003 | Loop State Manager -- save/load crash recovery integrity | Integration | TR-loop-009, TR-concept-014 | ADR-0004 | Planning |
| 004 | Interaction Bus -- event bus singleton and frame-buffered dispatch | Logic | TR-concept-009, TR-concept-012 | ADR-0006 | Planning |
| 005 | Interactable Component -- click/long-press detection with touch support | Integration | TR-concept-009, TR-concept-012 | ADR-0006 | Planning |
| 006 | Ink Wash Shader Pipeline -- post-processing canvas_item shader | Visual/Feel | TR-concept-001 | ADR-0001 | Planning |
| 007 | Ink Wash Shader -- rain overlay shader | Visual/Feel | TR-concept-001 | ADR-0001 | Planning |
| 008 | Ink Wash Shader -- GDScript driver and uniform binding | Integration | TR-concept-001, TR-concept-002 | ADR-0001 | Planning |
| 009 | Save/Load Persistence -- SaveManager coordinator and atomic write | Logic | TR-concept-014 | ADR-0010 | Planning |
| 010 | Save/Load Persistence -- auto-save triggers, debounce, and 3-slot support | Integration | TR-concept-014, TR-concept-015 | ADR-0010 | Planning |
| 011 | Save/Load Persistence -- schema migration and crash recovery | Logic | TR-concept-014 | ADR-0010 | Planning |

## Acceptance Criteria

- LoopStateManager passes all 10 validation criteria from ADR-0004 (advance_night 1-7, rollback, signal emission)
- propose_delta() correctly resolves conflicts using sort_key formula
- InteractionBus dispatches CLICK and LONG_PRESS events with priority resolution
- Interactable supports both mouse and touch with 44px minimum touch target
- ink_wash.gdshader achieves >= 80% desaturation at knowledge_level 0.0, <= 3.0ms GPU time combined
- rain.gdshader is independently toggleable
- SaveManager produces valid JSON after atomic write; .bak fallback works on corruption
- Auto-save fires after clue_discovered, consequence_registered, room_changed signals
- All systems have serialize()/deserialize() round-trip tests passing
- No S1 or S2 bugs in delivered systems
