class_name EnemyData
extends Resource
## Defines an enemy type's base properties and move pool.

enum EnemyType { NORMAL, ELITE, BOSS }

@export var id: String = ""
@export var enemy_name: String = ""
@export var enemy_type: EnemyType = EnemyType.NORMAL
@export var min_hp: int = 40
@export var max_hp: int = 44
@export var color: Color = Color.RED  # Placeholder visual color

# Move pool - each move is a dictionary with: name, type, damage, block, effects
# type can be: "attack", "defend", "buff", "debuff", "attack_debuff"
@export var moves: Array = []

# AI pattern: "sequential", "random_no_repeat", "conditional"
@export var ai_pattern: String = "sequential"

# Optional idle sprite (res:// path to a PNG). If set, replaces the colored figure.
@export var idle_sprite_path: String = ""
