## Per-night NPC configuration resource. Authored in the editor for each NPC and night.
## Path convention: assets/data/npcs/{npc_id}/night_{n}.tres
class_name NPCTemplate
extends Resource

## Unique NPC identifier (e.g., &"guest_indigo").
@export var npc_id: StringName

## Display name shown in dialogue and UI.
@export var display_name: String

## Starting emotional state for this night.
@export var initial_emotional_state: int = 0  ## NPCEmotionalState.NEUTRAL

## Room ID where the NPC starts this night.
@export var initial_location: StringName

## Whether dialogue is available at the start of this night.
@export var is_dialogue_available: bool = true

## Root dialogue node ID for this night's conversation.
@export var dialogue_id: StringName

## NPC portrait texture for dialogue UI.
@export var portrait: Texture2D

## Art bible color key (e.g., &"indigo", &"ochre").
@export var color_key: StringName

## Per-night overrides: night_num -> { emotional_state, location, dialogue_available }.
@export var per_night_overrides: Dictionary = {}

## Night-specific override conditions for future narrative scripting.
@export var conditions: Dictionary = {}
