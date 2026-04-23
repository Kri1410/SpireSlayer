class_name RelicData
extends Resource
## Defines a relic's properties.

enum RelicRarity { STARTER, COMMON, UNCOMMON, RARE, BOSS, EVENT }

@export var id: String = ""
@export var relic_name: String = ""
@export_multiline var description: String = ""
@export var rarity: RelicRarity = RelicRarity.COMMON
@export var color: Color = Color.GOLD  # Placeholder visual

# Effect hooks - which game event triggers this relic
# e.g., "on_combat_start", "on_turn_start", "on_card_played", "on_enemy_kill", "passive"
@export var trigger: String = "passive"

# Generic effect values
@export var effect_value: int = 0
@export var effect_type: String = ""  # e.g., "heal", "draw", "energy", "strength", "block"
