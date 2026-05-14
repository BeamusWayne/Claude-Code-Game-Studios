# Sprint 1: Foundation Layer

**Dates**: 2026-05-15 to 2026-05-21 (1 week)
**Epic**: Foundation
**Goal**: Implement Foundation layer systems with unit tests. By end of sprint, the game boots, autoloads initialize, state cycles through nights, events flow through the bus, and the ink wash shader renders.
**PR-SPRINT**: CONCERNS (accepted) -- 6.5 days estimated vs 4 days available capacity. Mitigated by parallelizing independent stories, splitting SaveManager into core infrastructure (this sprint) and full integration (Sprint 2), and carrying shader work as Should Have.

## Sprint Goal

Ship the three zero-dependency Foundation systems (LoopStateManager, InteractionBus, SaveManager core) with passing unit tests, plus GDUnit4 test harness, so Core layer systems can build on them in Sprint 2.

## Capacity

- Total days: 5 (Mon-Fri)
- Buffer (20%): 1 day reserved for unplanned work / bug fixes
- Available: 4 days

## Stories

### Must Have (Critical Path)

| ID | Task | Agent/Owner | Est. Days | Dependencies | Acceptance Criteria |
|----|------|-------------|-----------|--------------|-------------------|
| S1-1 | GDUnit4 installation + test harness setup | -- | 0.5 | None | GDUnit4 installed from Godot AssetLib; `tests/gdunit4_runner.gd` executes without errors; `tests/unit/core/` and `tests/integration/core/` directories exist; sample test runs green |
| S1-2 | LoopStateManager: core state model + signals | godot-gdscript-specialist | 1.0 | S1-1 | Autoload singleton `LoopStateManager` initializes at boot; three state layers (Template, PersistentMutations, PlayerKnowledge) modeled; signals `night_advanced`, `night_ready`, `advance_failed`, `consequence_registered` emit correctly; `current_night` starts at 1; `current_phase` starts at WHISPER; `is_transitioning` starts false; unit tests pass per ADR-0004 validation criteria 8-10 |
| S1-3 | LoopStateManager: advance_night + consequence registration | godot-gdscript-specialist | 1.0 | S1-2 | 7-step atomic `advance_night()` completes end-to-end; `register_consequence()` stores mutations with affects_nights; consequences survive across `advance_night()` calls; `advance_night()` at night 7 triggers game-end behavior (does not go to night 8); rollback restores state on step failure; unit tests pass per ADR-0004 validation criteria 1-7 |
| S1-4 | InteractionBus: event bus + Interactable component | godot-gdscript-specialist | 1.5 | S1-1 | Autoload singleton `InteractionBus` registers/unregisters Interactables; frame buffer collects events; `_process` resolves highest-priority event per frame; `interaction_detected` signal emits resolved event; CLICK and LONG_PRESS detection via InputEventMouseButton and InputEventScreenTouch; input_method tagging (MOUSE vs TOUCH); long-press cancel on cursor/finger exit; unregister on `_exit_tree`; unit tests pass per ADR-0006 validation criteria 1-10 |
| S1-5 | SaveManager: atomic file I/O + JSON schema | godot-gdscript-specialist | 0.5 | S1-1 | SaveManager autoload skeleton; `_atomic_write()` writes to .tmp then renames to .json; `_rotate_backup()` preserves previous save as .bak; `_read_save_file()` falls back to .bak if primary is corrupt; `_build_save_envelope()` produces valid JSON with schema_version; 3 slot paths generated correctly; schema migration framework exists (empty migration list for v1); unit tests pass per ADR-0010 validation criteria 1-6 |

### Should Have

| ID | Task | Agent/Owner | Est. Days | Dependencies | Acceptance Criteria |
|----|------|-------------|-----------|--------------|-------------------|
| S1-6 | Ink Wash Shader: production implementation | godot-shader-specialist | 1.0 | None (parallel) | `ink_wash.gdshader` canvas_item post-processing on CanvasLayer 10 with SCREEN_TEXTURE; uniforms: knowledge_level (0-1), pressure_level (0-1), time_value; `rain.gdshader` on CanvasLayer 20 with rain_intensity; GDScript driver updates uniforms per frame; visual validation: knowledge_level=0.0 is near-monochrome, knowledge_level=1.0 shows visible color; both shaders combined under 3.0ms at 1280x720; Screenshot evidence in `production/qa/evidence/` |

### Nice to Have

| ID | Task | Agent/Owner | Est. Days | Dependencies | Acceptance Criteria |
|----|------|-------------|-----------|--------------|-------------------|
| S1-7 | SaveManager: full system integration (serialize coordination) | godot-gdscript-specialist | 0.5 | S1-3, S1-5 | `_collect_snapshots()` calls LoopStateManager.serialize(); `_distribute_snapshots()` calls LoopStateManager.deserialize() first; auto-save signal connections wired; debounce prevents double-save within 2 seconds; save blocked during is_transitioning |

## Carryover from Previous Sprint

No previous sprint -- this is Sprint 1.

## Risks

| Risk | Probability | Impact | Mitigation |
|------|------------|--------|------------|
| GDUnit4 requires manual installation from Godot editor (cannot be scripted) | High | Medium | Complete S1-1 first thing; document step-by-step install process; if AssetLib fails, install from GitHub release |
| Ink wash shader needs real art assets for meaningful visual testing | Medium | Low | Use solid-color rectangles as test sprites; shader validates against ADR-0001 formulas, not art quality |
| LoopStateManager `advance_night()` is the highest-risk story -- 7-step atomic operation with rollback | Medium | High | Write tests for each step failure independently before implementing the full sequence |
| Solo dev context: interruptions reduce available capacity below 4 days | Medium | Medium | 20% buffer already reserved; Must Have stories total 4.5 days with S1-7 deferred |
| SaveManager depends on LoopStateManager.serialize() being available | Low | Medium | S1-5 (atomic I/O) is independent of LoopStateManager; S1-7 (integration) can slip to Sprint 2 |

## Dependencies on External Factors

- GDUnit4 addon must be installed manually via Godot editor AssetLib (or downloaded from GitHub)
- Ink wash shader prototype exists at `prototypes/ink-wash-shader/` but production code will be written from scratch per ADR-0001
- No art assets required for this sprint (test sprites only)

## Definition of Done for this Sprint

- [ ] All Must Have stories completed with passing unit tests
- [ ] All source files in `src/core/` and `src/persistence/`
- [ ] Unit tests in `tests/unit/core/` for LoopStateManager, InteractionBus, SaveManager
- [ ] All tests pass: `godot --headless --script tests/gdunit4_runner.gd`
- [ ] Game boots without errors, autoloads initialize (LoopStateManager, InteractionBus, SaveManager at minimum)
- [ ] Code follows naming conventions from `technical-preferences.md`
- [ ] Each story committed individually after tests pass

## ADR References

| Story | Primary ADR | Validation Criteria |
|-------|------------|-------------------|
| S1-2, S1-3 | ADR-0004 (Loop State Management) | 10 criteria listed in ADR |
| S1-4 | ADR-0006 (Interaction Event Bus) | 15 criteria listed in ADR |
| S1-5, S1-7 | ADR-0010 (Save/Load Persistence) | 17 criteria listed in ADR |
| S1-6 | ADR-0001 (Ink Wash Shader Pipeline) | 6 criteria listed in ADR |

## Notes

- Use TDD: write tests first for each story, then implement
- Each story should be completable in one focused session (2-4 hours)
- Commit after each story passes its tests
- S1-7 (SaveManager full integration) explicitly deferred to Sprint 2 if time runs out -- it depends on all Foundation systems being complete
- The ink wash shader (S1-6) is independent and can be done in any spare session; it does not block any other story
