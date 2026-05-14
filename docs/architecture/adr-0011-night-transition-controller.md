# ADR-0011: Night Transition Controller

## Status

Accepted

## Date

2026-05-14

## Engine Compatibility

| Field | Value |
|-------|-------|
| **Engine** | Godot 4.6 |
| **Domain** | Core / Lifecycle |
| **Knowledge Risk** | LOW -- uses standard GDScript signals, Tween, and call_deferred patterns. No post-cutoff APIs required. |
| **References Consulted** | docs/engine-reference/godot/VERSION.md, docs/engine-reference/godot/breaking-changes.md, docs/engine-reference/godot/deprecated-apis.md |
| **Post-Cutoff APIs Used** | None |
| **Verification Required** | Test full night transition (save + stop + advance + reinit + reload + restart) with 10+ registered consequences. Test transition blocked during dialogue (ADR-0003). Test transition blocked during room transition. Test night 7 transition triggers game end instead of night 8. Test fade overlay covers entire sequence. Test save_before_transition succeeds before advance_night(). Test timer restarts with correct duration after transition. Test NPCManager re-initializes from templates after night_advanced. Test RoomManager template reset after night_advanced. |

## ADR Dependencies

| Field | Value |
|-------|-------|
| **Depends On** | ADR-0004 (loop-state-management -- advance_night() atomic operation, night_advanced/night_ready signals, is_transitioning guard), ADR-0007 (room-location-management -- RoomManager template reset, fade overlay CanvasLayer 100), ADR-0008 (countdown-timer -- TimerService stop/start/serialize, night_timer_ended signal), ADR-0009 (npc-state-machine -- NPCManager re-initialization on night_advanced), ADR-0010 (save-load-persistence -- SaveManager.save_game() before transition, save blocked during is_transitioning) |
| **Enables** | System #9 (Event Scheduler -- needs night boundary to schedule per-night events), System #24 (Audio System -- cross-night music/ambient transitions), ending trigger logic (night 7 completion). Enables the "night ends" mechanic: timer expires -> transition -> next night or loop end. |
| **Blocks** | System #9 (Event Scheduler -- needs night boundary signal), System #24 (Audio System -- cross-night transitions), ending trigger logic (night 7 = game end), full time-loop playable cycle. |
| **Ordering Note** | Must be Accepted before Event Scheduler ADR and Audio System ADR. All dependency ADRs (0004, 0007, 0008, 0009, 0010) are already Accepted. |

## Context

### Problem Statement

The 7-night time loop is the core structure of the game. Each night has a countdown timer; when it expires, the game must transition to the next night. This transition is a multi-system coordinated operation: save the player's progress, stop the timer, atomically advance the night state (resetting template state while preserving persistent mutations), re-initialize NPCs from new night templates, reload the room with fresh state, and restart the timer for the new night. Currently, each system knows about its own piece (TimerService knows when time runs out, LoopStateManager knows how to advance_night()), but no single entity coordinates the full sequence. Without a coordinator, the calling order, error handling, and blocking conditions (dialogue active, room transition in progress) would be scattered across multiple systems with no clear owner.

### Current State

Five systems each own a piece of the night transition:

- **TimerService** (ADR-0008): emits `night_timer_ended` when the countdown reaches zero. Does NOT call advance_night() -- boundary rule.
- **LoopStateManager** (ADR-0004): owns the atomic `advance_night()` 7-step operation (VALIDATE, SNAPSHOT, COLLECT, LOAD, REBUILD, INCREMENT, NOTIFY). Emits `night_advanced` and `night_ready`.
- **RoomManager** (ADR-0007): listens to `night_advanced` for template reset, and `night_ready` for initial room load. Owns the fade overlay (CanvasLayer 100).
- **NPCManager** (ADR-0009): listens to `night_advanced` to re-initialize NPC state from new night templates + DeltaAccumulator.
- **SaveManager** (ADR-0010): provides `save_game()` for persistence. Save is blocked during `is_transitioning`.

The systems are designed to react to signals, but the orchestration -- what happens first, what happens after, what blocks, what happens on failure -- is undefined.

### Constraints

- Night transition is NOT the same as loop reset. Loop reset resets ALL cross-loop state (including persistent mutations and player knowledge). Night transition preserves everything and only resets template state. The game does not currently have a loop reset mechanic -- this ADR addresses night-to-night advancement only.
- Dialogue has priority over night transition (ADR-0004, ADR-0003): if dialogue is active when the timer expires, the transition must wait for dialogue to complete.
- Room transitions (ADR-0007) and night transitions are separate operations. Night transition should not begin during a room transition.
- The transition must be visually seamless: a fade overlay covers the entire sequence (unload old state, advance, load new state).
- Night 7 is the final night. Timer expiration on night 7 triggers the game ending, not a transition to night 8.
- Save must occur BEFORE advance_night() (ADR-0010: save blocked during is_transitioning). This captures the player's exact state at the end of the night.
- TimerService.set_time_scale(0.0) during transition prevents the timer from ticking during the transition sequence (ADR-0008).

### Requirements

- Orchestrate the full night transition sequence: save, stop timer, fade out, advance night, re-initialize systems, fade in, restart timer.
- Block during: active dialogue (UIManager.is_dialogue_active), room transition in progress (RoomManager._is_transitioning), night transition already in progress (own guard).
- Emit signals for transition lifecycle: started, completed, failed.
- On night 7 timer expiration: trigger game ending instead of advancing to night 8.
- Own NO game state -- purely an orchestration layer. All state changes are delegated to the systems that own the state.
- Provide a public API for systems that need to request a night transition (e.g., a scripted event that forces night end).

## Decision

NightTransitionController Autoload singleton that orchestrates but owns NO state. It coordinates the sequence by calling each system's methods in a defined order, connected by signals and call_deferred() to avoid same-frame ordering issues.

### Architecture Diagram

```
┌──────────────────────────────────────────────────────────────────────┐
│              NightTransitionController (Autoload)                     │
│                                                                      │
│  NO GAME STATE OWNED -- orchestration only                           │
│                                                                      │
│  Signals:                                                            │
│    night_transition_started(old_night: int)                          │
│    night_transition_completed(new_night: int)                        │
│    night_transition_failed(reason: String)                           │
│    game_ending_triggered(final_night: int)                           │
│                                                                      │
│  State (orchestration-only, not game state):                         │
│    _is_transitioning: bool                                           │
│    _pending_transition: bool                                         │
│                                                                      │
│  ┌──────────────────────────────────────────────────────────────┐    │
│  │  Transition Sequence:                                        │    │
│  │                                                              │    │
│  │  request_night_transition()                                  │    │
│  │    1. GUARD    — block if: _is_transitioning,                │    │
│  │                  dialogue active, room transition active      │    │
│  │       OR enqueue as _pending_transition                      │    │
│  │    2. PRE_SAVE — SaveManager.save_game(current_slot)         │    │
│  │       on fail: abort, emit night_transition_failed           │    │
│  │    3. STOP     — TimerService.stop_timer()                   │    │
│  │                  TimerService.set_time_scale(0.0)             │    │
│  │    4. SIGNAL   — emit night_transition_started               │    │
│  │    5. FADE_OUT — RoomManager fade overlay out                 │    │
│  │       (CanvasLayer 100, 0.3s tween)                          │    │
│  │    6. ADVANCE  — LoopStateManager.advance_night()            │    │
│  │       on fail: rollback handled by LoopStateManager;         │    │
│  │       emit night_transition_failed, fade back in              │    │
│  │    7. POST     — (night_advanced signal fires:               │    │
│  │       NPCManager re-initializes, RoomManager resets          │    │
│  │       template)                                              │    │
│  │    8. FADE_IN  — RoomManager fade overlay in                 │    │
│  │       (CanvasLayer 100, 0.3s tween)                          │    │
│  │    9. RESTART  — TimerService.start_night_timer()            │    │
│  │       (triggered by night_ready signal from LoopState)       │    │
│  │   10. COMPLETE — _is_transitioning = false                   │    │
│  │                  emit night_transition_completed              │    │
│  │                  check _pending_transition                    │    │
│  └──────────────────────────────────────────────────────────────┘    │
│                                                                      │
│  Trigger Sources:                                                    │
│    TimerService.night_timer_ended → _on_night_timer_ended            │
│    request_night_transition() → public API for scripted events       │
└───────────┬──────────────┬──────────────┬──────────────┬─────────────┘
            │              │              │              │
   ┌────────▼─────┐ ┌──────▼──────┐ ┌─────▼──────┐ ┌───▼───────────┐
   │LoopState     │ │TimerService │ │RoomManager │ │SaveManager    │
   │Manager       │ │             │ │            │ │               │
   │advance_night │ │stop_timer   │ │fade overlay│ │save_game      │
   │              │ │start_timer  │ │            │ │               │
   └──────────────┘ └─────────────┘ └────────────┘ └───────────────┘
            │              │              │              │
   ┌────────▼─────┐ ┌──────▼──────┐ ┌─────▼──────┐
   │NPCManager    │ │UIManager    │ │Ending Logic │
   │(re-init via  │ │(dialogue    │ │(night 7     │
   │ signal)      │ │ blocking)   │ │ trigger)    │
   └──────────────┘ └─────────────┘ └─────────────┘
```

### Key Interfaces

**NightTransitionController (Autoload Singleton)**:
```gdscript
class_name NightTransitionController
extends Node

signal night_transition_started(old_night: int)
signal night_transition_completed(new_night: int)
signal night_transition_failed(reason: String)
signal game_ending_triggered(final_night: int)

## Whether a night transition is currently in progress.
## Other systems can read this to block operations during transition.
var is_transitioning: bool = false

var _pending_transition: bool = false

func _ready() -> void:
    TimerService.night_timer_ended.connect(_on_night_timer_ended)
    LoopStateManager.night_advanced.connect(_on_night_advanced)
    LoopStateManager.advance_failed.connect(_on_advance_failed)
    UIManager.dialogue_ended.connect(_on_blocking_cleared)
    RoomManager.room_transition_completed.connect(_on_blocking_cleared)
    set_process(false)

## --- Public API ---

func request_night_transition() -> void:
    ## Public entry point for night transition.
    ## Called when timer expires, or by scripted events that force night end.
    ## Guards: blocks during dialogue, room transition, or existing night transition.
    if is_transitioning:
        return
    if not _can_start_transition():
        _pending_transition = true
        return

    _execute_transition()

## --- Guards ---

func _can_start_transition() -> bool:
    ## Check all blocking conditions.
    if UIManager.is_dialogue_active:
        return false
    if RoomManager._is_transitioning:
        return false
    return true

## --- Transition Sequence ---

func _execute_transition() -> void:
    var old_night: int = LoopStateManager.get_current_night()

    ## Night 7 check: timer expiration on the final night triggers game ending.
    if old_night >= LoopStateManager.MAX_NIGHTS:
        game_ending_triggered.emit(old_night)
        return

    is_transitioning = true
    LoopStateManager.is_transitioning = true

    ## Step 1: PRE_SAVE — save before advancing night.
    ## ADR-0010: save must happen before advance_night() because
    ## save_game() is blocked during LoopStateManager.is_transitioning.
    if SaveManager.current_slot >= 0:
        var save_ok: bool = SaveManager.save_game(SaveManager.current_slot)
        if not save_ok:
            _abort_transition("Save failed before night advance")
            return

    ## Step 2: STOP — halt the countdown timer.
    TimerService.stop_timer()
    TimerService.set_time_scale(0.0)

    ## Step 3: SIGNAL — notify all systems that transition is starting.
    night_transition_started.emit(old_night)

    ## Step 4: FADE_OUT — animate fade overlay to cover the screen.
    ## Uses RoomManager's fade overlay (CanvasLayer 100, per ADR-0007).
    ## Tween duration: 0.3s (matches room transition fade time).
    _fade_out(_on_fade_out_complete)

func _on_fade_out_complete() -> void:
    ## Step 5: ADVANCE — call the atomic advance_night() operation.
    ## LoopStateManager handles the 7-step sequence (VALIDATE through NOTIFY).
    ## On success: night_advanced signal fires, triggering downstream re-init.
    ## On failure: advance_failed signal fires, triggering rollback.
    LoopStateManager.advance_night()

func _on_night_advanced(old_night: int, new_night: int) -> void:
    ## Step 6: POST — downstream systems react to night_advanced.
    ## NPCManager re-initializes from templates (ADR-0009).
    ## RoomManager applies template reset (ADR-0007).
    ## These happen via their own night_advanced signal connections.
    ##
    ## After downstream systems complete, fade back in.
    _fade_in(_on_fade_in_complete)

func _on_fade_in_complete() -> void:
    ## Step 7: COMPLETE — transition finished.
    ## TimerService restarts via night_ready signal (ADR-0008):
    ##   LoopStateManager.night_ready -> TimerService._on_night_ready -> start_night_timer()
    is_transitioning = false
    LoopStateManager.is_transitioning = false
    TimerService.set_time_scale(1.0)

    night_transition_completed.emit(LoopStateManager.get_current_night())

    ## Check for pending transition (queued while we were busy).
    if _pending_transition:
        _pending_transition = false
        call_deferred("request_night_transition")

func _on_advance_failed(step: int, error: String) -> void:
    ## advance_night() failed at a specific step.
    ## LoopStateManager handles rollback internally (restores SNAPSHOT).
    ## We need to abort the transition and restore visual state.
    var reason: String = "advance_night() failed at step %d: %s" % [step, error]
    push_error("NightTransitionController: " + reason)

    is_transitioning = false
    LoopStateManager.is_transitioning = false

    ## Fade back in to show the restored state.
    _fade_in(func() -> void:
        night_transition_failed.emit(reason)
        TimerService.set_time_scale(1.0)
        TimerService.start_night_timer()
    )

func _abort_transition(reason: String) -> void:
    ## Abort before advance_night() was called (e.g., save failed).
    is_transitioning = false
    LoopStateManager.is_transitioning = false
    TimerService.set_time_scale(1.0)
    night_transition_failed.emit(reason)

## --- Timer Expiration Handler ---

func _on_night_timer_ended(night: int) -> void:
    ## TimerService.night_timer_ended fires when countdown reaches zero.
    ## Deferred to next frame to avoid same-frame ordering issues
    ## (ADR-0008 risk: TimerService emits at end of _process;
    ##  transition controller should defer advance_night()).
    call_deferred("request_night_transition")

func _on_blocking_cleared(_arg: Variant = null) -> void:
    if _pending_transition and not is_transitioning:
        _pending_transition = false
        call_deferred("request_night_transition")

## --- Fade Helpers ---

func _fade_out(on_complete: Callable) -> void:
    ## Animate the fade overlay (CanvasLayer 100 ColorRect) alpha 0.0 -> 1.0.
    ## Duration: 0.3s, ease: EaseType.EASE_IN.
    var tween := create_tween()
    tween.tween_method(RoomManager.set_fade_alpha, 0.0, 1.0, 0.3)
    tween.tween_callback(on_complete)

func _fade_in(on_complete: Callable) -> void:
    ## Animate the fade overlay alpha 1.0 -> 0.0.
    ## Duration: 0.3s, ease: EaseType.EASE_OUT.
    var tween := create_tween()
    tween.tween_method(RoomManager.set_fade_alpha, 1.0, 0.0, 0.3)
    tween.tween_callback(on_complete)
```

**RoomManager Extension (ADR-0007 supplement)**:
```gdscript
## Add to RoomManager to support night transition fade.
## The fade overlay ColorRect is owned by RoomManager per ADR-0007.
## NightTransitionController calls this method to animate the overlay.

var _fade_rect: ColorRect  ## Initialized in _ready() on CanvasLayer 100

func set_fade_alpha(alpha: float) -> void:
    ## Called by Tween during fade animation.
    _fade_rect.color.a = clampf(alpha, 0.0, 1.0)

func get_fade_alpha() -> float:
    return _fade_rect.color.a
```

### Blocking Conditions Detail

| Condition | Check | Resolution |
|-----------|-------|------------|
| Night transition in progress | `NightTransitionController.is_transitioning` | Guard returns immediately; no queue |
| Dialogue active | `UIManager.is_dialogue_active` | Queued as `_pending_transition`; checked in `_process` or on `dialogue_ended` signal |
| Room transition in progress | `RoomManager._is_transitioning` | Queued as `_pending_transition`; checked on `room_transition_completed` signal |
| Night 7 (final night) | `old_night >= LoopStateManager.MAX_NIGHTS` | Emits `game_ending_triggered` instead of advancing |
| Save failure | `SaveManager.save_game() returns false` | Abort transition, emit `night_transition_failed` |

### Signal Flow During Transition

```
TimerService.night_timer_ended(night)
  -> NightTransitionController._on_night_timer_ended
  -> (call_deferred) NightTransitionController.request_night_transition
  -> _execute_transition:
       SaveManager.save_game()
       TimerService.stop_timer() + set_time_scale(0.0)
       night_transition_started.emit(old_night)
       _fade_out -> RoomManager.set_fade_alpha (tween 0.3s)
       -> _on_fade_out_complete:
            LoopStateManager.advance_night()
            -> (internal 7-step sequence)
            -> LoopStateManager.night_advanced.emit(old, new)
               -> NPCManager._on_night_advanced (re-init from templates)
               -> RoomManager._on_night_advanced (template reset)
               -> NightTransitionController._on_night_advanced
                  -> _fade_in -> RoomManager.set_fade_alpha (tween 0.3s)
                  -> _on_fade_in_complete:
                       is_transitioning = false
                       TimerService.set_time_scale(1.0)
                       -> (night_ready fires from LoopStateManager)
                          -> TimerService._on_night_ready -> start_night_timer()
                       night_transition_completed.emit(new_night)
```

### Error Handling

| Failure Point | Action |
|---------------|--------|
| Save fails (step 1) | Abort transition. is_transitioning = false. Emit `night_transition_failed`. Timer continues. |
| advance_night() fails at any step (step 5) | LoopStateManager rolls back to SNAPSHOT internally. NightTransitionController fades back in, restarts timer, emits `night_transition_failed`. |
| Fade tween interrupted (e.g., scene tree change) | Tween cleans up automatically on node free. The is_transitioning flag remains true, preventing duplicate transitions. A timeout guard (see Implementation Guidelines) can force-reset. |

## Alternatives Considered

### Alternative 1: Signal Chain (No Coordinator)

- **Description**: TimerService.night_timer_ended -> SaveManager.save_game -> LoopStateManager.advance_night -> (night_advanced) -> TimerService.start_night_timer. No central coordinator; each system calls the next in a chain.
- **Pros**: No new Autoload; fewer moving parts; each system only knows about the next step.
- **Cons**: The chain crosses system boundaries -- TimerService would need to know about SaveManager, or SaveManager about LoopStateManager, creating tight coupling between systems that should be independent. Error handling is fragmented: if save fails mid-chain, there is no single point to abort and roll back. Blocking conditions (dialogue, room transition) would need to be checked at each link in the chain. Adding a new step (e.g., audio fade) requires modifying the chain, risking breakage.
- **Rejection Reason**: A coordinator keeps each system independent. The signal chain pattern violates the state ownership model (architecture.yaml): TimerService should not know about SaveManager, and SaveManager should not trigger advance_night(). A single coordinator is the cleanest way to manage ordering, blocking, and error recovery without coupling the systems to each other.

### Alternative 2: Coroutines (async/await)

- **Description**: Use GDScript's await pattern to write the transition as a sequential coroutine: `await SaveManager.save_game(); await _fade_out(); await LoopStateManager.advance_night(); await _fade_in();`.
- **Pros**: Readable sequential flow; linear code; easy to add steps.
- **Cons**: GDScript's await suspends execution but does NOT pause the game loop. Other systems continue processing during await, potentially causing race conditions (e.g., another interaction triggers during the fade). The blocking guard (is_transitioning) still needs to be maintained separately. Error handling with try/catch patterns is not idiomatic in GDScript. Tween awaits add complexity around cancellation.
- **Rejection Reason**: Callback-based flow (Tween.tween_callback) provides the same sequential guarantees with clearer control over what happens at each stage. The callback approach is more explicit about what runs after each step completes, and integrates naturally with Godot's Tween system. The await pattern adds hidden complexity around cancellation and error propagation that callbacks avoid.

### Alternative 3: State Machine Transition

- **Description**: A dedicated TransitionState enum (PRE_SAVE, STOPPING, FADING_OUT, ADVANCING, FADING_IN, COMPLETING) with a _process() driven state machine that checks and advances the current state each frame.
- **Pros**: Explicit state tracking; easy to visualize in debugger; can pause/resume mid-transition.
- **Cons**: Over-engineered for a linear sequence that always runs the same steps in the same order. Adds _process() overhead during transition. State machine adds 6+ states for a sequence that runs exactly once per night. The is_transitioning bool + callback pattern achieves the same sequencing with less code.
- **Rejection Reason**: The transition is a linear pipeline, not a reactive state machine. There are no branches, no loops, and no mid-transition decision points. A callback chain provides the same sequential execution with simpler code. If the transition becomes more complex in the future (e.g., conditional steps, branching paths), this alternative can be revisited.

## Consequences

### Positive

- Single orchestration point for the night transition -- the sequence is defined in one place, not scattered across signal connections between systems.
- NightTransitionController owns NO game state -- it reads and delegates to the systems that own state (LoopStateManager, TimerService, RoomManager, SaveManager, NPCManager). This respects the state ownership model in architecture.yaml.
- Blocking conditions are centralized -- dialogue, room transition, and transition-in-progress guards are all checked in one place.
- Error recovery is centralized -- save failure and advance_night() failure are handled in the controller, not distributed across signal handlers.
- call_deferred() for timer expiration avoids same-frame ordering issues between TimerService._process() and advance_night().
- Night 7 game ending is handled before advance_night() is called, preventing the need for a "night 8 rollback" in LoopStateManager.
- _pending_transition flag ensures that a timer expiration during a blocked state (dialogue) is not lost -- it fires as soon as the blocking condition clears.

### Negative

- One more Autoload singleton in the project (adds to InteractionBus, LoopStateManager, TimerService, RoomManager, NPCManager, SaveManager, UIManager, ClueDatabase, KnowledgeManager).
- NightTransitionController has direct knowledge of 5 other systems (LoopStateManager, TimerService, RoomManager, SaveManager, UIManager). This is inherent to a coordinator pattern -- it must know about the systems it coordinates.
- The callback chain (Tween.tween_callback) is less readable than a sequential coroutine. Each step's completion handler calls the next step, creating a callback chain that spans multiple methods.
- The transition is synchronous from the player's perspective (fade covers the entire operation), but internally it is asynchronous (callbacks fire after tween completion). This adds complexity around the is_transitioning guard.
- Fade overlay ownership is shared: the ColorRect is owned by RoomManager (per ADR-0007), but NightTransitionController animates it. RoomManager must expose set_fade_alpha() for the controller to use.

### Risks

| Risk | Probability | Impact | Mitigation |
|------|------------|--------|------------|
| advance_night() failure leaves game in semi-transitioned state (fade stuck at black) | Low | High -- player sees black screen | LoopStateManager rolls back to SNAPSHOT internally. NightTransitionController fades back in and restarts timer on advance_failed signal. Unit test this path. |
| Callback chain breaks if a tween is interrupted by scene tree change | Low | Medium -- is_transitioning stuck true | Add a timeout guard: if is_transitioning is true for more than 5 seconds, force-reset and emit night_transition_failed. |
| _pending_transition fires at wrong time (e.g., after save slot changes) | Low | Low -- duplicate transition attempt | _pending_transition is cleared after use. The guard in request_night_transition() prevents duplicate execution. |
| Save failure before advance_night() is confusing to player | Medium | Medium -- player loses the night's progress | Emit night_transition_failed with reason. UI should display "Save failed -- night cannot end safely." The player can try again or troubleshoot storage. |
| TimerService.night_timer_ended fires during dialogue, player misses the transition | Medium | Low -- transition is deferred, not lost | _pending_transition flag ensures the transition fires after dialogue ends. The fade naturally signals to the player that the night has changed. |
| Race condition: dialogue ends and timer expires in same frame | Low | Medium -- two trigger paths | is_transitioning guard prevents double execution. _on_night_timer_ended uses call_deferred(), which runs after the current frame's signal processing. |
| Fade duration too short for advance_night() with many consequences | Low | Medium -- player sees loading artifacts | Profile advance_night() with 30+ consequences. If it exceeds 0.3s, increase fade duration or add a loading indicator during the fade. |

## Boundary Rules

1. **NightTransitionController MUST NOT own any game state.** It does not store night number, timer values, room state, or NPC state. All state reads go through the owning system's public interface. All state writes go through the owning system's methods.

2. **NightTransitionController MUST NOT bypass advance_night().** It must never increment current_night directly, modify NPC state, or change room state during transition. The only mutation path is LoopStateManager.advance_night(), which triggers downstream reactions via signals.

3. **NightTransitionController MUST NOT contain game logic.** It does not decide which NPCs to reinitialize or which rooms to load. It calls advance_night() and lets the signal chain handle the rest. The controller's job is ordering and error recovery, not decision-making.

4. **Night transition is NOT loop reset.** This system advances from night N to night N+1, preserving all persistent mutations and player knowledge. A future loop reset mechanic (restarting from night 1) is a separate operation that this ADR does not address.

5. **Only NightTransitionController should set LoopStateManager.is_transitioning.** Other systems read this flag (e.g., SaveManager blocks saves during transition, InteractionBus could block interactions), but only the transition controller writes it.

## Conventions

1. **Autoload load order**: NightTransitionController must be registered after LoopStateManager, TimerService, RoomManager, SaveManager, UIManager, and NPCManager in Project Settings > Autoload. Godot fires _ready() in registration order; the controller's _ready() connects to signals from all these systems, which requires them to be initialized first.

2. **Fade overlay delegation**: The fade overlay (CanvasLayer 100 ColorRect) is physically owned by RoomManager (per ADR-0007), but NightTransitionController drives the animation during night transitions. RoomManager exposes `set_fade_alpha(alpha: float)` for this purpose. RoomManager also uses the same overlay for room-to-room transitions. Night transitions and room transitions should never overlap (guard prevents this).

3. **call_deferred for timer trigger**: The `_on_night_timer_ended` handler uses `call_deferred("request_night_transition")` to defer the transition to the next frame. This follows ADR-0008's mitigation for TimerService and advance_night() ordering: TimerService emits night_timer_ended at the end of _process, and the transition should not begin in the same frame to avoid re-entrant state mutation.

4. **Signal naming**: NightTransitionController signals use the `night_transition_` prefix to distinguish from LoopStateManager's `night_advanced`/`night_ready` and RoomManager's `room_transition_started`/`room_transition_completed`.

## GDD Requirements Addressed

| GDD Document | System | Requirement | How This ADR Satisfies It |
|-------------|--------|-------------|--------------------------|
| game-concept.md | Pillar 2 | 7-night time loop -- each night has fixed duration, transitioning to next night when it expires | NightTransitionController orchestrates the full night-to-night transition sequence |
| game-concept.md | Core Mechanic | Time Loop Exploration -- integrated experience from #1, #3, #5, #8 | Controller coordinates LoopStateManager (#1), RoomManager (#3), TimerService (#5) to produce the loop exploration experience |
| loop-state-management.md | advance_night() contract | Atomic 7-step operation for night advancement | Controller calls advance_night() as step 5 of its sequence, with pre-save and post-reinit around it |
| loop-state-management.md | Dialogue vs Transition Priority | Dialogue must complete before advance_night() | _can_start_transition() checks UIManager.is_dialogue_active; _pending_transition queues the request |
| systems-index.md | System #8 | Night Transition Controller -- depends on #1, #4 | This ADR defines the complete Night Transition Controller |
| systems-index.md | System #9 | Event Scheduler -- depends on #5, #3, #6 | night_transition_completed signal provides the night boundary for event scheduler |
| systems-index.md | System #24 | Audio System -- depends on #5, #9, #8 | night_transition_started/completed signals enable cross-night audio transitions |
| ADR-0008 | Boundary Rule | TimerService must not call advance_night() | NightTransitionController is the designated coordinator; TimerService only emits night_timer_ended |
| ADR-0010 | Save Before Transition | Save must occur before advance_night() | Controller saves in step 1, before calling advance_night() in step 5 |
| ADR-0007 | Template Reset | RoomManager template reset on night_advanced | Controller triggers advance_night(); RoomManager reacts to night_advanced signal independently |

## Performance Implications

| Metric | Expected Value | Budget | Notes |
|--------|---------------|--------|-------|
| CPU (transition) | ~15-50 ms total | < 500 ms | advance_night() dominates (~10-30ms with 20+ consequences). Save ~5ms. Fade tween is GPU. Total wall-clock time from player perspective: 0.6s (fade) + ~50ms (operations hidden by fade) = ~0.65s. |
| CPU (idle) | 0.0 ms | 0.0 ms | set_process(false) when not transitioning. No per-frame cost. |
| Memory (runtime) | ~0 KB additional | < 1 KB | Controller holds two bools and a pending flag. No cached state. Tween objects are GC'd after completion. |
| GPU (fade) | 2 draw calls (ColorRect) | 100 total | Fade overlay adds 1 draw call (full-screen ColorRect) on CanvasLayer 100. Already accounted for in ADR-0007's room transition. |
| Disk I/O (save) | ~1-5 ms | < 16 ms | One SaveManager.save_game() call per transition. JSON write ~50-200 KB. Already accounted for in ADR-0010. |

- **Network**: N/A (single-player game)
- **Frame budget impact**: The transition hides all operations behind a 0.3s fade-out. advance_night() runs while the screen is black, so the player never sees a frame hitch. The transition does NOT run in _process() -- each step is triggered by callbacks (Tween completion, signal handlers).

## Migration Plan

New system. Implementation order:

1. Add `set_fade_alpha()` / `get_fade_alpha()` methods to RoomManager (ADR-0007 supplement).
2. Implement NightTransitionController Autoload skeleton with guards and signal connections.
3. Implement `_execute_transition()` sequence (save, stop, fade, advance, fade, restart).
4. Implement `_on_advance_failed()` error recovery path.
5. Implement `_on_night_timer_ended()` with call_deferred.
6. Implement `_pending_transition` queue for blocked transitions.
7. Wire NightTransitionController to `night_transition_completed` for future Event Scheduler integration.
8. Write unit tests for: full transition sequence, blocked during dialogue, blocked during room transition, night 7 game ending, save failure abort, advance_night failure recovery.

**Rollback plan**: NightTransitionController is an Autoload that can be removed from project settings without affecting LoopStateManager, TimerService, RoomManager, or SaveManager. Each system continues to function independently -- they just lose the coordinated transition. The only change to existing systems is the `set_fade_alpha()` method added to RoomManager, which is additive and non-breaking.

## Validation Criteria

1. request_night_transition() triggers the full save-stop-fade-advance-fade-restart sequence
2. SaveManager.save_game() is called before LoopStateManager.advance_night()
3. TimerService.stop_timer() and set_time_scale(0.0) are called before advance_night()
4. Fade overlay covers the screen (alpha 0.0 -> 1.0) before advance_night() is called
5. Fade overlay reveals the screen (alpha 1.0 -> 0.0) after advance_night() completes
6. NightTransitionController.is_transitioning is true during the entire transition and false after completion
7. LoopStateManager.is_transitioning is true during the transition and false after completion
8. TimerService restarts after transition completes (via night_ready signal)
9. NPCManager re-initializes from new night templates after night_advanced signal
10. RoomManager template reset fires after night_advanced signal
11. Transition blocked when UIManager.is_dialogue_active is true
12. Transition blocked when RoomManager._is_transitioning is true
13. Transition blocked when NightTransitionController.is_transitioning is true (no re-entry)
14. _pending_transition fires after blocking condition clears
15. Night 7 timer expiration emits game_ending_triggered instead of advancing to night 8
16. Save failure aborts transition, emits night_transition_failed, does NOT call advance_night()
17. advance_night() failure (advance_failed signal) triggers fade-back-in and timer restart
18. call_deferred used for _on_night_timer_ended (no same-frame mutation)
19. NightTransitionController owns no game state (no current_night, timer values, room state, or NPC state stored)
20. Full round-trip: night 1 -> save -> transition -> night 2 -> timer restarts -> timer expires -> save -> transition -> night 3 (repeatable through night 7)
21. Serialization round-trip: save mid-night -> load -> timer expires -> transition succeeds (no state corruption from mid-night save)

## Related Decisions

- ADR-0004: Loop State Management -- provides advance_night() atomic operation, night_advanced/night_ready/advance_failed signals, is_transitioning flag, MAX_NIGHTS constant
- ADR-0007: Room/Location Management -- provides fade overlay (CanvasLayer 100), template reset on night_advanced, room transition guard (_is_transitioning)
- ADR-0008: Countdown Timer -- provides night_timer_ended trigger, stop/start/set_time_scale methods, timer restart on night_ready
- ADR-0009: NPC State Machine -- re-initializes from templates on night_advanced signal
- ADR-0010: Save/Load Persistence -- provides save_game() before transition, save blocked during is_transitioning
- ADR-0003: UI Visual Register -- defines UIManager.is_dialogue_active for blocking check, CanvasLayer ordering for fade overlay
- ADR-0006: Interaction Event Bus -- boundary pattern reference (detect/dispatch only, no game logic); NightTransitionController follows the same coordination-only discipline
- architecture.yaml: State ownership registry -- NightTransitionController does not register any state (owns none); all state access goes through owning systems
