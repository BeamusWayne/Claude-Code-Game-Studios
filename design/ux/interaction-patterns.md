# Interaction Pattern Library

**Project**: 七夜 (Seven Nights)
**Last Updated**: 2026-05-14
**Status**: Initialized (minimal)

This library documents interaction patterns used across the game. Each pattern defines the input, response, and accessibility considerations.

---

## Core Input Model

**Primary**: Point-and-click (mouse) / tap (touch)
**Secondary**: Keyboard shortcuts
**Constraint**: No hover-only mechanics (touch compatibility)

### Input Actions

| Action | Default Binding | Touch Equivalent | Context |
|--------|----------------|-----------------|---------|
| Interact | Left mouse click | Screen tap | Click/tap on interactable objects |
| Notebook | N key | Notebook button (HUD) | Open/close clue notebook |
| Cancel / Back | Escape | Back gesture / button | Close overlay, cancel action |
| Scroll | Mouse wheel | Swipe | Scroll lists, zoom |

---

## Patterns

### P01: Interactable Click/Tap

**Trigger**: Player clicks/taps an interactable object
**Response**: Object highlights, interaction executes (examine, pick up, use)
**Feedback**: Ink wash highlight animation + audio cue
**Accessibility**: 48x48px minimum hitbox. Visual highlight + sound confirm success.

### P02: Dialogue Choice

**Trigger**: Dialogue presents choices, player clicks/taps one
**Response**: Selected choice highlights, NPC responds
**Feedback**: Choice text enlarges on selection, ink wash underline
**Accessibility**: Choices navigable by keyboard (arrow keys + Enter). Extended timer option.

### P03: Notebook Open/Close

**Trigger**: N key or HUD notebook button
**Response**: Notebook slides in from left, gameplay pauses
**Feedback**: Paper unfold animation + sound
**Accessibility**: Keyboard-navigable. Screen reader announces sections.

### P04: Room Transition (Exit Click)

**Trigger**: Player clicks/taps an exit hotspot
**Response**: Ink wash fade-out → load room → fade-in
**Feedback**: Full-screen ink wash animation (CanvasLayer 100)
**Accessibility**: Fade uses reduced motion alternative if enabled. No flash.

### P05: Clue Connection

**Trigger**: Player drags one clue card onto another in notebook
**Response**: Connection line drawn, system evaluates match
**Feedback**: Gold ochre glow if valid connection (insight); ink splash if invalid
**Accessibility**: Alternative: select two clues then tap "Connect" button (no drag required).

### P06: Timer Pressure

**Trigger**: Countdown timer starts at night begin
**Response**: Timer ticks down, visual intensity increases
**Feedback**: Timer color shifts white → amber → red. Whisper/roar audio phases.
**Accessibility**: Timer extension multiplier (0.5x-3.0x). Story mode disables timer.

### P07: NPC Interrogation Initiation

**Trigger**: Player clicks/taps an NPC in the current room
**Response**: NPC highlights, dialogue tree opens
**Feedback**: NPC portrait animation + greeting audio
**Accessibility**: NPC highlighted on focus. Keyboard-navigable NPC list if multiple NPCs present.

---

## Pattern Selection Guide

When designing a new screen or feature:

1. Check if an existing pattern applies — reuse before creating new
2. Every new pattern must define: trigger, response, feedback, accessibility
3. All patterns must support both mouse and touch input
4. No pattern may require hover state as the sole interaction method
