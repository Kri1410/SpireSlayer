class_name CardData
extends Resource
## Defines a single card's properties.

enum CardType { ATTACK, SKILL, POWER, STATUS, CURSE }
enum CardRarity { STARTER, COMMON, UNCOMMON, RARE, SPECIAL }
enum TargetType { SINGLE_ENEMY, ALL_ENEMIES, SELF, NONE }
enum CardClass { ANY, RONIN, YUMI, BANNER }

@export var card_class: CardClass = CardClass.ANY

@export var id: String = ""
@export var card_name: String = ""
@export_multiline var description: String = ""
@export var energy_cost: int = 1
@export var card_type: CardType = CardType.ATTACK
@export var rarity: CardRarity = CardRarity.COMMON
@export var target_type: TargetType = TargetType.SINGLE_ENEMY

# Combat values
@export var damage: int = 0
@export var block: int = 0
@export var magic_number: int = 0  # Used for misc effects (draw, str gain, etc.)

# Replay mechanic
@export var replay_count: int = 0  # Number of additional times this card triggers

# Flags
@export var exhaust: bool = false
@export var ethereal: bool = false  # Exhausts if still in hand at end of turn
@export var innate: bool = false    # Always drawn in opening hand
@export var upgraded: bool = false

# Upgrade values (applied when upgraded)
@export var upgrade_damage_bonus: int = 0
@export var upgrade_block_bonus: int = 0
@export var upgrade_cost_reduction: int = 0
@export var upgrade_magic_bonus: int = 0
@export var upgrade_replay_bonus: int = 0

# Color for placeholder card visuals
@export var color: Color = Color.WHITE


func get_effective_damage() -> int:
	return damage + (upgrade_damage_bonus if upgraded else 0)


func get_effective_block() -> int:
	return block + (upgrade_block_bonus if upgraded else 0)


func get_effective_cost() -> int:
	return max(0, energy_cost - (upgrade_cost_reduction if upgraded else 0))


func get_effective_magic() -> int:
	return magic_number + (upgrade_magic_bonus if upgraded else 0)


func get_effective_replay() -> int:
	return replay_count + (upgrade_replay_bonus if upgraded else 0)


func get_display_name() -> String:
	if upgraded:
		return card_name + "+"
	return card_name


func duplicate_card() -> CardData:
	var copy = self.duplicate()
	return copy
