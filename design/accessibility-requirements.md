# Accessibility Requirements: 七夜 (Seven Nights)

> **Status**: Committed
> **Author**: ux-designer / producer
> **Last Updated**: 2026-05-14
> **Accessibility Tier Target**: Comprehensive
> **Platform(s)**: PC (Steam) + macOS (primary), mobile (iOS/Android portability)
> **External Standards Targeted**:
> - WCAG 2.1 Level AA
> - Game Accessibility Guidelines (basic + intermediate + partial advanced)
> - Steam Accessibility Features / SDL
> - Apple / Google Accessibility Guidelines (mobile port)
> **Accessibility Consultant**: None engaged (indie scope)
> **Linked Documents**: `design/gdd/systems-index.md`, `docs/architecture/architecture.md`

---

## Accessibility Tier Definition

### This Project's Commitment

**Target Tier**: Comprehensive

**Rationale**: 七夜 is a narrative-driven point-and-click mystery with reading-heavy gameplay, timed countdown pressure, and color-as-knowledge visual mechanics. The core barriers are visual (text-heavy, color-dependent), cognitive (7-night loop state tracking, clue connections, countdown pressure), and motor (point-and-click precision). Standard tier would exclude players who rely on colorblind modes in a game where color IS the core mechanic (knowledge = color). Comprehensive tier ensures the knowledge-color system is accessible to all players through multiple encoding channels. The game's low-action nature (no twitch combat, no platforming) makes motor accessibility straightforward — most effort goes to visual and cognitive accommodations. Target audience research (narrative adventure players aged 20-45) indicates higher-than-average disability awareness expectations in this genre.

**Features explicitly in scope (beyond tier baseline)**:
- Full subtitle customization — elevated because dialogue is a primary gameplay channel and the game is Chinese-language-first with localization plans
- Visual indicators for all knowledge-color changes — elevated because color is the core mechanic
- Reduced motion mode covering ink wash shader effects — custom to this game's visual identity

**Features explicitly out of scope**:
- Screen reader support for in-game world exploration (menus only) — Godot 4.6 AccessKit covers menus but not spatial game world
- Full haptic alternatives for audio cues — PC primary platform limits haptic standardization

---

## Visual Accessibility

| Feature | Target Tier | Scope | Status | Implementation Notes |
|---------|-------------|-------|--------|---------------------|
| Minimum text size — menu UI | Standard | All menu screens | Not Started | 24px minimum at 1080p. Chinese characters (CJK) require larger minimum than Latin — use 28px for KaiTi/FangSong fonts. |
| Minimum text size — subtitles | Standard | All voiced/captioned content | Not Started | 32px minimum at 1080p. CJK subtitle text at 36px recommended. |
| Minimum text size — HUD | Standard | In-game HUD (timer, suspicion gauge) | Not Started | 20px minimum for critical information (countdown, suspicion level). Non-critical may be smaller. |
| Text contrast — UI text | Standard | All UI text | Not Started | Minimum 4.5:1 ratio (WCAG AA). Ink wash aesthetic uses warm paper tones — test all text on xuan paper backgrounds. |
| Text contrast — subtitles | Standard | Subtitle display | Not Started | Minimum 7:1 ratio. Use semi-opaque background box by default to handle variable scene backgrounds. |
| Colorblind mode — Protanopia | Standard | All color-coded gameplay | Not Started | Knowledge-color system must encode through pattern/shape/icon in addition to hue. |
| Colorblind mode — Deuteranopia | Standard | All color-coded gameplay | Not Started | Same pattern/shape backup as Protanopia. |
| Colorblind mode — Tritanopia | Standard | All color-coded gameplay | Not Started | Affects blue-yellow perception — relevant if any NPC uses blue tones. |
| Color-as-only-indicator audit | Basic | All UI and gameplay | Not Started | CRITICAL for this game: knowledge = color is the core mechanic. Every color signal must have a non-color backup. |
| UI scaling | Standard | All UI elements | Not Started | Range: 75% to 150%. Test at both extremes with CJK text (character density matters). |
| High contrast mode | Comprehensive | Menus + HUD | Not Started | Replace ink wash backgrounds with high-contrast alternatives while preserving aesthetic identity. |
| Brightness controls | Basic | Global | Not Started | Ink wash aesthetic is intentionally muted — brightness controls must not break the visual identity. Use subtle range (-30% to +30%). |
| Screen flash warning | Basic | All cutscenes, VFX | Not Started | Ink wash splash effects and night transition animations must be audited for flash frequency. |
| Motion/animation reduction mode | Comprehensive | All transitions, shader effects, camera shake | Not Started | Reduces ink wash shader motion, night transition animation, countdown pulse effects. Static alternatives for all animated UI. |
| Subtitles — on/off | Basic | All voiced content | Not Started | Default: ON for this game (reading-heavy narrative). |
| Subtitles — speaker identification | Standard | All voiced content | Not Started | NPC name + portrait icon. Color-coded by NPC IF non-color backup exists. |
| Subtitles — style customization | Comprehensive | Subtitle display | Not Started | Font size (4 sizes), background opacity (0-100%), position (bottom/top). |
| Subtitles — sound effect captions | Comprehensive | Gameplay-critical SFX | Not Started | Ink wash splashes, countdown whispers/roars, environmental audio cues. |

### Color-as-Only-Indicator Audit

This is the most critical accessibility table for 七夜. The core mechanic (knowledge = color) means color carries essential gameplay information. Every entry must have a non-color backup.

| Location | Color Signal | What It Communicates | Non-Color Backup | Status |
|----------|-------------|---------------------|-----------------|--------|
| Knowledge color overlay on NPCs | Per-guest unique color (5 NPC colors + gold ochre for insights) | Which NPC's knowledge domain is active | NPC name label + distinct icon/pattern per NPC (e.g., leaf pattern, wave pattern) | Not Started |
| Notebook clue entries | Color border indicates source NPC | Clue provenance | Source NPC name text label + icon | Not Started |
| Insight glow effect | Gold ochre glow | New insight generated | "NEW INSIGHT" text label + sound cue | Not Started |
| Countdown timer | Color shift from white → amber → red | Time pressure level | Numeric countdown display + pulsing speed increases | Not Started |
| Suspicion gauge | Color fill from green → yellow → red | Suspicion level | Numeric percentage + gauge width (wider = more suspicious) + icon expression changes | Not Started |
| Minimap location markers | Color per room type | Room category | Icon shape per type + text label on hover/focus | Not Started |

---

## Motor Accessibility

七夜 is a point-and-click adventure with no twitch combat or platforming. Motor accessibility is simpler than most genres.

| Feature | Target Tier | Scope | Status | Implementation Notes |
|---------|-------------|-------|--------|---------------------|
| Full input remapping | Standard | All inputs (mouse, keyboard, touch) | Not Started | All actions: interact, notebook, ui_cancel, scroll, click. Touch targets must meet 44x44pt minimum. |
| Input method switching | Standard | PC | Not Started | Mouse + keyboard + touch must switch seamlessly. UI prompts update dynamically. |
| Touch-friendly interactions | Comprehensive | All gameplay | Not Started | NO hover-only mechanics (project constraint from GDD). All interactions work with tap/click. Touch targets 48x48pt minimum for interactable objects. |
| Hold-to-press alternatives | Standard | Any hold inputs | Not Started | If any "hold to examine" mechanic exists, provide toggle alternative. |
| Rapid input alternatives | Standard | N/A for this game | Not Started | Point-and-click has no rapid input requirements. Mark as N/A unless minigames add timed input. |
| Input timing adjustments | Standard | Timed dialogue choices, countdown pressure | Not Started | Countdown timer extension multiplier: 0.5x to 3.0x. At 3.0x, the whisper phase is significantly longer. |
| Aim assist | Standard | N/A for this game | Not Started | Point-and-click has no aiming. Mark as N/A. |
| Auto-sprint / movement assists | Standard | N/A for this game | Not Started | No sustained movement input in point-and-click. Mark as N/A. |
| HUD element repositioning | Comprehensive | Timer, suspicion gauge, minimap | Not Started | Allow repositioning to any screen corner. Important for players using eye-gaze or head-tracking. |
| Click/tap precision tolerance | Comprehensive | All interactable objects | Not Started | Generous click hitboxes. Minimum 48x48px tap target on interactable objects (mobile). Expand hitbox beyond visual bounds for small objects. |

---

## Cognitive Accessibility

The 7-night time loop with clue connection mechanics creates significant cognitive load. This section is critical for 七夜.

| Feature | Target Tier | Scope | Status | Implementation Notes |
|---------|-------------|-------|--------|---------------------|
| Difficulty options | Standard | Countdown timer pressure, suspicion accumulation rate | Not Started | Separate sliders: timer speed (0.5x-2.0x), suspicion gain rate, hint frequency. "Story mode" preset disables timer entirely. |
| Pause anywhere | Basic | All gameplay states | Not Started | Pause during countdown, dialogue, cutscenes. Countdown pauses when game is paused. |
| Tutorial persistence | Standard | All tutorials and help text | Not Started | Help section in notebook (accessible via N key). Every mechanic explained in persistent help pages. |
| Quest / objective clarity | Standard | Current investigation goals | Not Started | Active objective always visible in HUD. Full objective text accessible in notebook within 2 inputs. |
| Visual indicators for audio-only information | Standard | All gameplay-critical SFX | Not Started | Countdown whispers/roars need visual intensity indicator. Environmental audio clues need visual backup. |
| Reading time for UI | Standard | All auto-dismissing dialogs | Not Started | Knowledge gain notifications do not auto-dismiss — require click to close. Dialogue choices wait indefinitely (no timer on choices unless story-mandated). |
| Cognitive load documentation | Comprehensive | Per game system | Not Started | Clue connection system: player tracks up to 15+ clues simultaneously. Notebook must provide filtering, sorting, and search to reduce cognitive load. |
| Navigation assists | Standard | Hotel navigation | Not Started | Hotel map always accessible. Current room highlighted. Visited rooms show completion percentage. Fast travel to any visited room. |
| Loop state summary | Comprehensive | Night start recap | Not Started | At the start of each night, show a brief summary of persistent knowledge and unresolved questions from previous nights. Reduces re-orientation cognitive load after loop reset. |

---

## Auditory Accessibility

| Feature | Target Tier | Scope | Status | Implementation Notes |
|---------|-------------|-------|--------|---------------------|
| Subtitles for all spoken dialogue | Basic | All voiced content | Not Started | 100% coverage including NPC interrogation, environmental dialogue, narrator. |
| Closed captions for gameplay-critical SFX | Comprehensive | Identified SFX list (below) | Not Started | Countdown whispers/roars, ink wash effects, door/environmental sounds during investigation. |
| Mono audio option | Comprehensive | Global audio output | Not Started | Folds spatial audio to mono. Important for players with single-sided deafness. |
| Independent volume controls | Basic | Music / SFX / Voice / Ambient buses | Not Started | Four independent sliders. Persist to save file. Accessible from pause menu. |
| Visual representations for directional audio | Comprehensive | Off-screen audio events | Not Started | Screen-edge indicators for directional sounds. Opacity scales with proximity. |
| Hearing aid compatibility mode | Standard | High-frequency audio cues | Not Started | Audit countdown whisper SFX for frequency range. Provide visual equivalent for any high-frequency-only cues. |

### Gameplay-Critical SFX Audit

| Sound Effect | What It Communicates | Visual Backup | Caption Required | Status |
|-------------|---------------------|--------------|-----------------|--------|
| Countdown whisper | Timer entering whisper phase (low pressure) | Timer display + color shift to amber | Optional — visual is primary | Not Started |
| Countdown roar | Timer entering roar phase (high pressure) | Timer display + color shift to red + screen pulse | Optional — visual is primary | Not Started |
| Knowledge color gain chime | New color/knowledge acquired | Notification toast + NPC color icon | No — visual is sufficient | Not Started |
| Insight generation sound | Two clues connected to form insight | "NEW INSIGHT" text + gold ochre glow | No — visual is sufficient | Not Started |
| Door open/close | Room transition | Screen fade animation (ink wash transition) | No — visual is sufficient | Not Started |
| NPC approach footstep | NPC entering player's room | NPC sprite appears on screen | No — visual is sufficient | Not Started |
| Notebook open/close | Notebook UI toggle | Notebook screen visible/invisible | No — visual is sufficient | Not Started |
| Interaction success | Player clicked interactable correctly | Object highlight + response animation | No — visual is sufficient | Not Started |
| Suspicion level increase | NPC growing suspicious | Suspicion gauge fills + NPC expression change | No — visual is sufficient | Not Started |

---

## Platform Accessibility API Integration

| Platform | API / Standard | Features Planned | Status | Notes |
|----------|---------------|-----------------|--------|-------|
| Steam (PC) | Steam Accessibility Features / SDL | Controller remapping via Steam Input, subtitle support | Not Started | Primary platform. In-game remapping still required. |
| macOS | Apple Accessibility / VoiceOver | VoiceOver support for menus (if AccessKit supports on macOS) | Not Started | Godot 4.6 AccessKit integration should cover macOS VoiceOver for Control nodes. |
| iOS (future) | UIAccessibility / VoiceOver | VoiceOver for menus, Dynamic Type scaling | Not Started | Mobile port — not in v1.0 scope. |
| Android (future) | AccessibilityService / TalkBack | TalkBack for menus | Not Started | Mobile port — not in v1.0 scope. |
| PC (Screen Reader) | NVDA / Windows Narrator | Menu navigation announcements via AccessKit | Not Started | Godot 4.5+ AccessKit integration covers Control nodes. Verify against engine-reference/godot/ docs. |

---

## Per-Feature Accessibility Matrix

| System | Visual Concerns | Motor Concerns | Cognitive Concerns | Auditory Concerns | Addressed | Notes |
|--------|----------------|---------------|-------------------|------------------|-----------|-------|
| Knowledge Color System | Color is THE mechanic — critical colorblind barrier | None — passive observation | Tracking 6+ NPC color states simultaneously | None — visual-only system | Partial | Pattern/icon backup for all colors is critical |
| Clue Database / Notebook | Text-heavy, color borders for source | Click/tap precision for small clue cards | 15+ clues to track, connection mechanics | None | Partial | Search/filter reduces cognitive load |
| Countdown Timer | Color shift for pressure level | None — passive | Time pressure anxiety | Whisper/roar audio cues need visual backup | Partial | Timer extension multiplier planned |
| NPC Interrogation | Subtitle readability, speaker identification | None — dialogue choices are single clicks | Long dialogue trees, conditional branching | All dialogue voiced — subtitles required | Not Started | Dialogue choice timer extension needed |
| Room Navigation | Minimap color coding | Click/tap precision for exits | Spatial orientation across 7+ rooms | Door/transition SFX | Not Started | Map + fast travel reduce cognitive load |
| Night Transition | Flash/strobe risk in ink wash animation | None — automated sequence | Loop state reset confusion | Transition sound effects | Not Started | Loop state summary at night start planned |
| Suspicion System | Gauge color fill | None — passive | Tracking suspicion per NPC | None — visual-only system | Not Started | Gauge width + numeric % as non-color backup |
| Save/Load | None significant | Menu navigation only | None significant | Save confirmation sound | Not Started | Standard menu accessibility |

---

## Accessibility Test Plan

| Feature | Test Method | Pass Criteria | Responsible | Status |
|---------|------------|--------------|-------------|--------|
| Text contrast ratios | Automated contrast analyzer on all UI screenshots | All text ≥ 4.5:1; subtitles ≥ 7:1 | ux-designer | Not Started |
| Colorblind modes | Coblis simulator on all gameplay screenshots | No information lost in any mode | ux-designer | Not Started |
| Input remapping | Remap all inputs, complete first night | All actions work; no conflicts; persists across restart | qa-tester | Not Started |
| Subtitle accuracy | Verify against voice script | 100% coverage; speaker ID on all multi-character scenes | qa-tester | Not Started |
| Touch targets | Measure all interactable hitboxes on mobile viewport | All ≥ 48x48px | ux-designer | Not Started |
| Reduced motion mode | Enable mode, navigate all UI + complete one night | No shader motion; no screen shake; all transitions are fade | qa-tester | Not Started |
| Timer extension | Set multiplier to 3.0x, complete timed sequence | All timed sequences completable at 3.0x | qa-tester | Not Started |
| Screen reader (menus) | Enable OS screen reader, navigate all menus | All menu elements announced; logical navigation order | ux-designer | Not Started |
| Knowledge color backup | Enable each colorblind mode, identify all NPC knowledge | All NPC knowledge identifiable without color | qa-tester | Not Started |

---

## Known Intentional Limitations

| Feature | Tier Required | Why Not Included | Risk / Impact | Mitigation |
|---------|--------------|-----------------|--------------|------------|
| Screen reader for game world | Exemplary | Godot 4.6 AccessKit covers Control nodes only; spatial world description requires custom system | Affects blind players who can navigate menus but not game world | All critical world info duplicated in accessible notebook/menu systems |
| Full subtitle font customization | Exemplary | CJK custom font rendering requires additional pipeline work | Affects players with specific font needs (dyslexia fonts, etc.) | Two preset subtitle styles (default + high-readability) |
| Haptic alternatives for all audio | Exemplary | PC primary platform lacks haptic standardization | Affects deaf players relying on haptic feedback | Visual indicators for all audio cues (Comprehensive tier) |
| Cognitive load assist tools (auto-connect clues) | Exemplary | Would bypass the core gameplay mechanic | None — this is a design choice, not an oversight | Hint system + difficulty sliders for clue connection |

---

## Audit History

| Date | Auditor | Type | Scope | Findings Summary | Status |
|------|---------|------|-------|-----------------|--------|
| 2026-05-14 | Internal — initial setup | Tier commitment | Comprehensive tier defined, feature matrix populated | Initial document — no audit findings yet | Pending first audit |

---

## External Resources

| Resource | URL | Relevance |
|----------|-----|-----------|
| Game Accessibility Guidelines | https://gameaccessibilityguidelines.com | Comprehensive game-specific checklist |
| WCAG 2.1 | https://www.w3.org/TR/WCAG21/ | Contrast ratios, text sizing standards |
| Coblis Color Blindness Simulator | https://www.color-blindness.com/coblis-color-blindness-simulator/ | Visual testing tool for colorblind modes |
| AbleGamers | https://ablegamers.org | Player testing and consulting resources |
| Godot Accessibility (AccessKit) | https://docs.godotengine.org/en/stable/tutorials/ui/gui_accessibility.html | Engine-specific accessibility API support |

---

## Open Questions

| Question | Owner | Deadline | Resolution |
|----------|-------|----------|-----------|
| Does Godot 4.6 AccessKit support dynamic HUD element announcements, or only static menus? | ux-designer | Before Production | Unresolved — check engine-reference/godot/ docs |
| What is the Steam minimum accessibility feature set for 2026 release? | producer | Before Pre-Production | Unresolved |
| Can the ink wash shader pipeline support a static/low-motion mode without architectural changes? | technical-director | Before Production | Likely yes — ADR-0001 shader parameters are data-driven |
| What CJK font size is equivalent to 24px Latin for readability? | ux-designer | During UX design | Research suggests 28px minimum for CJK at 1080p |
