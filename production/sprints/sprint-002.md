# Sprint 2: Core Layer — Independent Systems

**Dates**: 2026-05-15 to 2026-05-21 (1 week)
**Epic**: Core
**Goal**: Implement four independent Core layer systems (TimerService, ClueDatabase, RoomManager, NPCManager) with passing unit tests. All four depend only on Foundation systems completed in Sprint 1 and can be implemented in parallel.

## Sprint Goal

Ship four Core layer systems that build on the Foundation layer, each with comprehensive unit tests. By end of sprint, the game has a working countdown timer with pressure curves, a clue/insight database, room transitions, and NPC emotional state management.

## Capacity

- Total days: 5 (Mon-Fri)
- Buffer (20%): 1 day reserved for unplanned work / bug fixes
- Available: 4 days

## Stories

### Must Have (Critical Path)

| ID | Task | Agent/Owner | Est. Days | Dependencies | Acceptance Criteria |
|----|------|-------------|-----------|--------------|-------------------|
| S2-1 | TimerService: countdown + pressure curve | godot-gdscript-specialist | 1.5 | Foundation (Sprint 1) | Autoload singleton TimerService; pressure_curve (Godot Curve Resource) drives pressure_level 0.0-1.0; three phases CALM/INTENSE/CRITICAL with thresholds at 0.3/0.7; time_scale for dialogue slow-down; night_timer_ended signal on expiry; serialize/deserialize remaining_time + pressure_level; unit tests pass per ADR-0008 validation criteria |
| S2-2 | ClueDatabase: entries + connections + contextual unlocks | godot-gdscript-specialist | 1.5 | Foundation (Sprint 1) | Autoload singleton ClueDatabase; KnowledgeEntry (CLUE/INSIGHT) with unified schema; Connection structure (bidirectional); contextual_unlocks cascade on insight creation; CRUD + search API; serialize/deserialize with 50+ entries; unit tests pass per ADR-0005 validation criteria |
| S2-3 | RoomManager: room loading + transitions | godot-gdscript-specialist | 1.5 | Foundation (Sprint 1) | Autoload singleton RoomManager; PackedScene on-demand load/unload; fade transition (CanvasLayer 100 ColorRect); interactable register/unregister on room change; template reset on night_advanced; unit tests pass per ADR-0007 validation criteria |
| S2-4 | NPCManager: emotional state machine | godot-gdscript-specialist | 1.5 | Foundation (Sprint 1) | Autoload singleton NPCManager; NPCEmotionalState enum (6 states); transition validation; NPCTemplate resources; propose_delta() integration; night reset from templates; unit tests pass per ADR-0009 validation criteria |

### Should Have

| ID | Task | Agent/Owner | Est. Days | Dependencies | Acceptance Criteria |
|----|------|-------------|-----------|--------------|-------------------|
| S2-5 | TimerService + InkWashDriver integration | godot-gdscript-specialist | 0.5 | S2-1 | TimerService.pressure_updated drives InkWashDriver.set_pressure_level(); visual pressure feedback works end-to-end |

## Carryover from Previous Sprint

None — Sprint 1 fully complete (7/7 stories done).

## Risks

| Risk | Probability | Impact | Mitigation |
|------|------------|--------|------------|
| TimerService Curve resource not available in headless test | Medium | Medium | Create default linear Curve in code as fallback |
| RoomManager PackedScene loading in headless tests | Medium | Medium | Mock PackedScene with test scene; test state management separately from scene loading |
| NPCManager propose_delta() requires LoopStateManager integration | Low | Medium | Use LoopStateManager as implemented in Sprint 1; test against real system |
| Four parallel agents may create conflicting file structures | Low | Low | Each agent writes to separate directories (src/core/, tests/unit/core/) |

## Dependencies on External Factors

- All Foundation systems must be stable from Sprint 1
- GDUnit4 test framework operational from Sprint 1
- No art assets required for this sprint (test fixtures only)
