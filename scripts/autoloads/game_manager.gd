extends Node
## Manages the overall game state for a single run.

# --- Character classes ---
# Each class has: name, max_hp, starter_relic, starter_cards (id->count),
# sprite paths and frame counts for idle and attack animations.
const CLASSES := {
	"ronin": {
		"name": "The Ronin",
		"tagline": "Disciplined swordsman.\nHigh single-target damage.",
		"max_hp": 75,
		"starter_relic": "whetstone",
		"starter_cards": {"slash": 5, "stance": 4, "iaido": 1},
		"idle_sprite": "res://assets/Characters/sprites/Samurai/Idle.png",
		"idle_frames": 6,
		"attack_sprite": "res://assets/Characters/sprites/Samurai/Attack_1.png",
		"attack_frames": 4,
		"accent_color": Color(0.95, 0.65, 0.2)
	},
	"yumi": {
		"name": "The Yumi",
		"tagline": "Ranged hunter.\nMulti-hit shots and card draw.",
		"max_hp": 65,
		"starter_relic": "quiver",
		"starter_cards": {"quick_shot": 5, "take_aim": 4, "hunters_eye": 1},
		"idle_sprite": "res://assets/Characters/sprites/Samurai_Archer/Idle.png",
		"idle_frames": 9,
		"attack_sprite": "res://assets/Characters/sprites/Samurai_Archer/Shot.png",
		"attack_frames": 14,
		"accent_color": Color(0.85, 0.3, 0.25)
	},
	"banner": {
		"name": "The Banner",
		"tagline": "Stalwart commander.\nTanky with party-wide debuffs.",
		"max_hp": 90,
		"starter_relic": "standard",
		"starter_cards": {"cleaver": 5, "bulwark": 4, "rally": 1},
		"idle_sprite": "res://assets/Characters/sprites/Samurai_Commander/Idle.png",
		"idle_frames": 5,
		"attack_sprite": "res://assets/Characters/sprites/Samurai_Commander/Attack_1.png",
		"attack_frames": 4,
		"accent_color": Color(0.85, 0.2, 0.25)
	}
}

# Player state
var selected_class: String = "ronin"
var player_name: String = "The Ronin"
var max_hp: int = 75
var current_hp: int = 75
var gold: int = 99
var current_act: int = 1
var current_floor: int = 0
var battles_this_act: int = 0


func get_class_data() -> Dictionary:
	return CLASSES.get(selected_class, CLASSES["ronin"])

# Deck
var deck: Array[CardData] = []
var relics: Array[RelicData] = []

# Map data for current act
var map_data: Array = []
var map_path: Array[int] = []

# Card database
var all_cards: Dictionary = {}
var all_enemies: Dictionary = {}
var all_relics: Dictionary = {}

# Current encounter info
var current_encounter_enemies: Array[EnemyData] = []


func _ready() -> void:
	_load_card_database()
	_load_enemy_database()
	_load_relic_database()

	# Always run code definitions — they fill in any cards/relics/enemies not on disk.
	# (Existing .tres entries take precedence; missing ids get the in-code fallback.)
	_create_cards_in_code()
	_create_enemies_in_code()
	_create_relics_in_code()

	print("[GameManager] Loaded ", all_cards.size(), " cards, ", all_enemies.size(), " enemies, ", all_relics.size(), " relics")


func start_new_run() -> void:
	var cls = get_class_data()
	player_name = cls.name
	max_hp = cls.max_hp
	current_hp = max_hp
	gold = 99
	current_act = 1
	current_floor = 0
	battles_this_act = 0
	deck.clear()
	relics.clear()
	map_data.clear()
	map_path.clear()
	current_encounter_enemies.clear()

	_build_starter_deck()

	var relic_id: String = cls.starter_relic
	if all_relics.has(relic_id):
		relics.append(all_relics[relic_id].duplicate())

	print("[GameManager] New ", selected_class, " run. HP: ", max_hp, "  Deck: ", deck.size())


func _build_starter_deck() -> void:
	var cls = get_class_data()
	for card_id in cls.starter_cards:
		var count: int = cls.starter_cards[card_id]
		if not all_cards.has(card_id):
			push_error("[GameManager] Missing starter card '%s' for class %s" % [card_id, selected_class])
			continue
		for i in range(count):
			deck.append(all_cards[card_id].duplicate_card())
	print("[GameManager] Built starter deck with ", deck.size(), " cards")


func heal(amount: int) -> void:
	current_hp = mini(current_hp + amount, max_hp)
	EventBus.player_hp_changed.emit(current_hp, max_hp)


func take_damage(amount: int) -> void:
	current_hp = maxi(current_hp - amount, 0)
	EventBus.player_hp_changed.emit(current_hp, max_hp)


func add_gold(amount: int) -> void:
	gold += amount
	EventBus.player_gold_changed.emit(gold)


func spend_gold(amount: int) -> bool:
	if gold >= amount:
		gold -= amount
		EventBus.player_gold_changed.emit(gold)
		return true
	return false


func add_card_to_deck(card: CardData) -> void:
	deck.append(card)


func remove_card_from_deck(card: CardData) -> void:
	var idx = deck.find(card)
	if idx >= 0:
		deck.remove_at(idx)


func register_combat_start() -> void:
	battles_this_act += 1


func should_use_undercity_background() -> bool:
	return current_act == 1 and battles_this_act > 0 and battles_this_act % 3 == 0


# --- Database Loading from .tres ---

func _load_card_database() -> void:
	var card_dir = "res://data/cards/"
	var dir = DirAccess.open(card_dir)
	if dir == null:
		print("[GameManager] Cannot open card directory: ", card_dir)
		return
	dir.list_dir_begin()
	var file_name = dir.get_next()
	while file_name != "":
		var load_name = file_name
		if file_name.ends_with(".remap"):
			load_name = file_name.trim_suffix(".remap")
		if load_name.ends_with(".tres"):
			var card = load(card_dir + load_name)
			if card and card is CardData:
				all_cards[card.id] = card
		file_name = dir.get_next()
	dir.list_dir_end()


func _load_enemy_database() -> void:
	var enemy_dir = "res://data/enemies/"
	var dir = DirAccess.open(enemy_dir)
	if dir == null:
		return
	dir.list_dir_begin()
	var file_name = dir.get_next()
	while file_name != "":
		var load_name = file_name
		if file_name.ends_with(".remap"):
			load_name = file_name.trim_suffix(".remap")
		if load_name.ends_with(".tres"):
			var enemy = load(enemy_dir + load_name)
			if enemy and enemy is EnemyData:
				all_enemies[enemy.id] = enemy
		file_name = dir.get_next()
	dir.list_dir_end()


func _load_relic_database() -> void:
	var relic_dir = "res://data/relics/"
	var dir = DirAccess.open(relic_dir)
	if dir == null:
		return
	dir.list_dir_begin()
	var file_name = dir.get_next()
	while file_name != "":
		var load_name = file_name
		if file_name.ends_with(".remap"):
			load_name = file_name.trim_suffix(".remap")
		if load_name.ends_with(".tres"):
			var relic = load(relic_dir + load_name)
			if relic and relic is RelicData:
				all_relics[relic.id] = relic
		file_name = dir.get_next()
	dir.list_dir_end()


# --- Programmatic Fallback (if .tres loading fails) ---

func _make_card(id: String, cname: String, desc: String, cost: int, ctype: CardData.CardType,
		rarity: CardData.CardRarity, target: CardData.TargetType, dmg: int, blk: int,
		magic: int, replay: int = 0, exhaust_flag: bool = false, ethereal_flag: bool = false,
		up_dmg: int = 0, up_blk: int = 0, up_cost: int = 0, up_magic: int = 0, up_replay: int = 0,
		klass: CardData.CardClass = CardData.CardClass.ANY) -> CardData:
	# Skip if a .tres of the same id was already loaded
	if all_cards.has(id):
		return all_cards[id]
	var card = CardData.new()
	card.card_class = klass
	card.id = id
	card.card_name = cname
	card.description = desc
	card.energy_cost = cost
	card.card_type = ctype
	card.rarity = rarity
	card.target_type = target
	card.damage = dmg
	card.block = blk
	card.magic_number = magic
	card.replay_count = replay
	card.exhaust = exhaust_flag
	card.ethereal = ethereal_flag
	card.upgrade_damage_bonus = up_dmg
	card.upgrade_block_bonus = up_blk
	card.upgrade_cost_reduction = up_cost
	card.upgrade_magic_bonus = up_magic
	card.upgrade_replay_bonus = up_replay
	return card


func _create_cards_in_code() -> void:
	var A = CardData.CardType.ATTACK
	var S = CardData.CardType.SKILL
	var P = CardData.CardType.POWER
	var SE = CardData.TargetType.SINGLE_ENEMY
	var AE = CardData.TargetType.ALL_ENEMIES
	var SL = CardData.TargetType.SELF
	var ST = CardData.CardRarity.STARTER
	var CO = CardData.CardRarity.COMMON
	var UC = CardData.CardRarity.UNCOMMON
	var RA = CardData.CardRarity.RARE
	var ANY = CardData.CardClass.ANY
	var RON = CardData.CardClass.RONIN
	var YUM = CardData.CardClass.YUMI
	var BAN = CardData.CardClass.BANNER

	# Generic starters (kept for backwards compat with old saves / .tres files)
	all_cards["strike"] = _make_card("strike", "Strike", "Deal {D} damage.", 1, A, ST, SE, 6, 0, 0, 0, false, false, 3, 0, 0, 0, 0, ANY)
	all_cards["defend"] = _make_card("defend", "Defend", "Gain {B} Block.", 1, S, ST, SL, 0, 5, 0, 0, false, false, 0, 3, 0, 0, 0, ANY)
	all_cards["bash"] = _make_card("bash", "Bash", "Deal {D} damage.\nApply {M} Vulnerable.", 2, A, ST, SE, 8, 0, 2, 0, false, false, 2, 0, 0, 1, 0, ANY)

	# ============================================================
	# RONIN (samurai swordsman) — discipline, momentum, sword combos
	# ============================================================
	# Starters
	all_cards["slash"] = _make_card("slash", "Slash", "Deal {D} damage.", 1, A, ST, SE, 6, 0, 0, 0, false, false, 3, 0, 0, 0, 0, RON)
	all_cards["stance"] = _make_card("stance", "Stance", "Gain {B} Block.", 1, S, ST, SL, 0, 5, 0, 0, false, false, 0, 3, 0, 0, 0, RON)
	all_cards["iaido"] = _make_card("iaido", "Iaido", "Deal {D} damage.\nIf Fatal, gain 1 Energy.", 1, A, ST, SE, 9, 0, 0, 0, false, false, 4, 0, 0, 0, 0, RON)
	# Common
	all_cards["riposte"] = _make_card("riposte", "Riposte", "Deal {D} damage.\nGain {B} Block.", 1, A, CO, SE, 7, 4, 0, 0, false, false, 3, 2, 0, 0, 0, RON)
	all_cards["crescent_cut"] = _make_card("crescent_cut", "Crescent Cut", "Deal {D} damage.\nLose 3 Block.", 1, A, CO, SE, 9, 0, 0, 0, false, false, 4, 0, 0, 0, 0, RON)
	all_cards["focus_strike"] = _make_card("focus_strike", "Focus Strike", "Deal {D} damage.\nGain 1 Strength.", 1, A, CO, SE, 6, 0, 1, 0, false, false, 2, 0, 0, 1, 0, RON)
	all_cards["iron_guard"] = _make_card("iron_guard", "Iron Guard", "Gain {B} Block.", 1, S, CO, SL, 0, 7, 0, 0, false, false, 0, 4, 0, 0, 0, RON)
	all_cards["honed_edge"] = _make_card("honed_edge", "Honed Edge", "Deal {D} damage.\nIf you have Block, deal {M} more.", 1, A, CO, SE, 5, 0, 4, 0, false, false, 2, 0, 0, 2, 0, RON)
	# Uncommon
	all_cards["wind_slash"] = _make_card("wind_slash", "Wind Slash", "Deal {D} damage.\nIf Fatal, draw 2 cards.", 1, A, UC, SE, 9, 0, 0, 0, false, false, 4, 0, 0, 0, 0, RON)
	all_cards["stoic_stance"] = _make_card("stoic_stance", "Stoic Stance", "Gain {B} Block.\nGain 1 Strength.", 2, S, UC, SL, 0, 14, 1, 0, false, false, 0, 4, 0, 1, 0, RON)
	all_cards["whirlwind_cut"] = _make_card("whirlwind_cut", "Whirlwind Cut", "Deal {D} damage to ALL enemies.", 2, A, UC, AE, 6, 0, 0, 0, false, false, 3, 0, 0, 0, 0, RON)
	all_cards["perfect_form"] = _make_card("perfect_form", "Perfect Form", "Gain {M} Strength.\nExhaust.", 1, S, UC, SL, 0, 0, 2, 0, true, false, 0, 0, 0, 1, 0, RON)
	all_cards["twin_blade"] = _make_card("twin_blade", "Twin Blade", "Deal {D} damage twice.", 1, A, UC, SE, 5, 0, 0, 1, false, false, 2, 0, 0, 0, 0, RON)
	# Rare
	all_cards["masters_strike"] = _make_card("masters_strike", "Master's Strike", "Deal {D} damage.", 2, A, RA, SE, 24, 0, 0, 0, false, false, 8, 0, 0, 0, 0, RON)
	all_cards["bushido"] = _make_card("bushido", "Bushido", "POWER: At the start of each turn, gain {M} Strength.", 2, P, RA, SL, 0, 0, 1, 0, false, false, 0, 0, 0, 1, 0, RON)
	all_cards["final_stand"] = _make_card("final_stand", "Final Stand", "Deal {D} damage.\nGain {B} Block.\nExhaust.", 1, A, RA, SE, 12, 6, 0, 0, true, false, 4, 3, 0, 0, 0, RON)

	# ============================================================
	# YUMI (samurai archer) — multi-hit, draw, AOE, vulnerable synergy
	# ============================================================
	# Starters
	all_cards["quick_shot"] = _make_card("quick_shot", "Quick Shot", "Deal {D} damage twice.", 1, A, ST, SE, 4, 0, 0, 1, false, false, 1, 0, 0, 0, 0, YUM)
	all_cards["take_aim"] = _make_card("take_aim", "Take Aim", "Gain {B} Block.\nDraw 1 card.", 1, S, ST, SL, 0, 4, 1, 0, false, false, 0, 2, 0, 0, 0, YUM)
	all_cards["hunters_eye"] = _make_card("hunters_eye", "Hunter's Eye", "Apply {M} Vulnerable.\nDraw 1 card.", 0, S, ST, SE, 0, 0, 2, 0, false, false, 0, 0, 0, 1, 0, YUM)
	# Common
	all_cards["snipe"] = _make_card("snipe", "Snipe", "Deal {D} damage.", 1, A, CO, SE, 9, 0, 0, 0, false, false, 4, 0, 0, 0, 0, YUM)
	all_cards["quick_draw"] = _make_card("quick_draw", "Quick Draw", "Draw {M} cards.", 0, S, CO, SL, 0, 0, 1, 0, false, false, 0, 0, 0, 1, 0, YUM)
	all_cards["pinning_shot"] = _make_card("pinning_shot", "Pinning Shot", "Deal {D} damage.\nApply {M} Vulnerable.", 1, A, CO, SE, 5, 0, 1, 0, false, false, 2, 0, 0, 1, 0, YUM)
	all_cards["side_step"] = _make_card("side_step", "Side-Step", "Gain {B} Block.\nDraw 1 card.", 1, S, CO, SL, 0, 5, 1, 0, false, false, 0, 3, 0, 0, 0, YUM)
	all_cards["twin_shot"] = _make_card("twin_shot", "Twin Shot", "Deal {D} damage twice.", 1, A, CO, SE, 4, 0, 0, 1, false, false, 1, 0, 0, 0, 0, YUM)
	# Uncommon
	all_cards["volley"] = _make_card("volley", "Volley", "Deal {D} damage to ALL enemies twice.", 2, A, UC, AE, 4, 0, 0, 1, false, false, 2, 0, 0, 0, 0, YUM)
	all_cards["steady_aim"] = _make_card("steady_aim", "Steady Aim", "Draw {M} cards.", 1, S, UC, SL, 0, 0, 2, 0, false, false, 0, 0, 0, 1, 0, YUM)
	all_cards["razor_arrow"] = _make_card("razor_arrow", "Razor Arrow", "Deal {D} damage three times.", 1, A, UC, SE, 3, 0, 0, 2, false, false, 1, 0, 0, 0, 0, YUM)
	all_cards["hunters_trap"] = _make_card("hunters_trap", "Hunter's Trap", "Apply {M} Vulnerable.\nDraw 1 card.", 1, S, UC, SE, 0, 0, 3, 0, false, false, 0, 0, 0, 1, 0, YUM)
	all_cards["killshot"] = _make_card("killshot", "Killshot", "Deal {D} damage.\nIf Vulnerable, deal {M} extra.", 1, A, UC, SE, 8, 0, 9, 0, false, false, 3, 0, 0, 4, 0, YUM)
	# Rare
	all_cards["rain_of_arrows"] = _make_card("rain_of_arrows", "Rain of Arrows", "Deal {D} damage to ALL enemies three times.", 3, A, RA, AE, 5, 0, 0, 2, false, false, 2, 0, 0, 0, 0, YUM)
	all_cards["eagle_eye"] = _make_card("eagle_eye", "Eagle Eye", "POWER: At the start of each turn, draw {M} additional card.", 2, P, RA, SL, 0, 0, 1, 0, false, false, 0, 0, 0, 1, 0, YUM)
	all_cards["true_shot"] = _make_card("true_shot", "True Shot", "Deal damage equal to twice your remaining hand size.\nExhaust.", 0, A, RA, SE, 0, 0, 0, 0, true, false, 0, 0, 0, 0, 0, YUM)
	# Extended Yumi pool — more build variety (precision / swarm / control)
	all_cards["piercing_shot"] = _make_card("piercing_shot", "Piercing Shot", "Deal {D} damage.", 1, A, CO, SE, 10, 0, 0, 0, false, false, 4, 0, 0, 0, 0, YUM)
	all_cards["grazing_shot"] = _make_card("grazing_shot", "Grazing Shot", "Deal {D} damage twice.", 1, A, CO, SE, 3, 0, 0, 1, false, false, 1, 0, 0, 0, 1, YUM)
	all_cards["arrow_dance"] = _make_card("arrow_dance", "Arrow Dance", "Gain {B} Block.", 1, S, CO, SL, 0, 7, 0, 0, false, false, 0, 3, 0, 0, 0, YUM)
	all_cards["scout_shot"] = _make_card("scout_shot", "Scout Shot", "Ethereal.\nDeal {D} damage.", 0, A, CO, SE, 5, 0, 0, 0, false, true, 2, 0, 0, 0, 0, YUM)
	all_cards["double_tap"] = _make_card("double_tap", "Double Tap", "Deal {D} damage twice.", 2, A, UC, SE, 8, 0, 0, 1, false, false, 3, 0, 0, 0, 0, YUM)
	all_cards["arrowhail"] = _make_card("arrowhail", "Arrowhail", "Deal {D} damage to ALL enemies twice.", 2, A, UC, AE, 5, 0, 0, 1, false, false, 2, 0, 0, 0, 0, YUM)
	all_cards["bolt_action"] = _make_card("bolt_action", "Bolt Action", "Deal {D} damage.\nGain {B} Block.", 2, A, UC, SE, 12, 3, 0, 0, false, false, 4, 2, 0, 0, 0, YUM)
	all_cards["hunters_mark"] = _make_card("hunters_mark", "Hunter's Mark", "Apply {M} Vulnerable to ALL enemies.", 0, S, UC, AE, 0, 0, 2, 0, false, false, 0, 0, 0, 1, 0, YUM)
	all_cards["arrow_storm"] = _make_card("arrow_storm", "Arrow Storm", "Deal {D} damage to ALL enemies three times.", 3, A, RA, AE, 5, 0, 0, 2, false, false, 2, 0, 0, 0, 0, YUM)
	all_cards["heart_shot"] = _make_card("heart_shot", "Heart Shot", "Deal {D} damage.\nIf Fatal, gain 1 Energy.", 2, A, RA, SE, 20, 0, 0, 0, false, false, 6, 0, 0, 0, 0, YUM)

	# ============================================================
	# BANNER (samurai commander) — tank, AOE debuffs, strength
	# ============================================================
	# Starters
	all_cards["cleaver"] = _make_card("cleaver", "Cleaver", "Deal {D} damage.", 1, A, ST, SE, 7, 0, 0, 0, false, false, 3, 0, 0, 0, 0, BAN)
	all_cards["bulwark"] = _make_card("bulwark", "Bulwark", "Gain {B} Block.", 1, S, ST, SL, 0, 6, 0, 0, false, false, 0, 3, 0, 0, 0, BAN)
	all_cards["rally"] = _make_card("rally", "Rally", "Apply {M} Vulnerable to ALL enemies.", 1, S, ST, AE, 0, 0, 1, 0, false, false, 0, 0, 0, 1, 0, BAN)
	# Common
	all_cards["heavy_strike"] = _make_card("heavy_strike", "Heavy Strike", "Deal {D} damage.", 1, A, CO, SE, 8, 0, 0, 0, false, false, 4, 0, 0, 0, 0, BAN)
	all_cards["wall"] = _make_card("wall", "Wall", "Gain {B} Block.", 1, S, CO, SL, 0, 8, 0, 0, false, false, 0, 4, 0, 0, 0, BAN)
	all_cards["intimidate"] = _make_card("intimidate", "Intimidate", "Apply {M} Weak to ALL enemies.\nExhaust.", 0, S, CO, AE, 0, 0, 1, 0, true, false, 0, 0, 0, 1, 0, BAN)
	all_cards["battle_cry"] = _make_card("battle_cry", "Battle Cry", "Apply {M} Vulnerable to ALL enemies.", 1, S, CO, AE, 0, 0, 1, 0, false, false, 0, 0, 0, 1, 0, BAN)
	all_cards["iron_will"] = _make_card("iron_will", "Iron Will", "Gain {B} Block.\nGain 1 Strength.", 1, S, CO, SL, 0, 5, 1, 0, false, false, 0, 3, 0, 1, 0, BAN)
	# Uncommon
	all_cards["banner_wave"] = _make_card("banner_wave", "Banner Wave", "Apply {M} Vulnerable to ALL enemies.", 1, S, UC, AE, 0, 0, 2, 0, false, false, 0, 0, 0, 1, 0, BAN)
	all_cards["fortress"] = _make_card("fortress", "Fortress", "Gain {B} Block.", 2, S, UC, SL, 0, 16, 0, 0, false, false, 0, 6, 0, 0, 0, BAN)
	all_cards["crushing_blow"] = _make_card("crushing_blow", "Crushing Blow", "Deal {D} damage.\nIf Vulnerable, apply {M} Weak.", 2, A, UC, SE, 14, 0, 2, 0, false, false, 4, 0, 0, 1, 0, BAN)
	all_cards["steel_plate"] = _make_card("steel_plate", "Steel Plate", "POWER: Gain {M} Block at the end of each turn.", 2, P, UC, SL, 0, 0, 3, 0, false, false, 0, 0, 0, 1, 0, BAN)
	all_cards["rallying_cry"] = _make_card("rallying_cry", "Rallying Cry", "Gain {B} Block.\nGain {M} Strength.", 1, S, UC, SL, 0, 5, 2, 0, false, false, 0, 3, 0, 1, 0, BAN)
	# Rare
	all_cards["hold_the_line"] = _make_card("hold_the_line", "Hold The Line", "Gain {B} Block.", 2, S, RA, SL, 0, 25, 0, 0, false, false, 0, 8, 0, 0, 0, BAN)
	all_cards["war_banner"] = _make_card("war_banner", "War Banner", "POWER: At the start of each turn, apply {M} Vulnerable to ALL enemies.", 3, P, RA, SL, 0, 0, 1, 0, false, false, 0, 0, 0, 1, 0, BAN)
	all_cards["decimate"] = _make_card("decimate", "Decimate", "Deal {D} damage to ALL enemies.", 3, A, RA, AE, 18, 0, 0, 0, false, false, 6, 0, 0, 0, 0, BAN)
	# Extended Banner pool — more build variety (fortress / rally / commander)
	all_cards["shield_wall"] = _make_card("shield_wall", "Shield Wall", "Gain {B} Block.", 1, S, CO, SL, 0, 8, 0, 0, false, false, 0, 4, 0, 0, 0, BAN)
	all_cards["war_shout"] = _make_card("war_shout", "War Shout", "Apply {M} Weak to ALL enemies.", 1, S, CO, AE, 0, 0, 1, 0, false, false, 0, 0, 0, 1, 0, BAN)
	all_cards["hammer_down"] = _make_card("hammer_down", "Hammer Down", "Deal {D} damage.\nGain {B} Block.", 1, A, CO, SE, 9, 2, 0, 0, false, false, 3, 2, 0, 0, 0, BAN)
	all_cards["shove"] = _make_card("shove", "Shove", "Deal {D} damage.\nGain {B} Block.", 1, A, CO, SE, 5, 5, 0, 0, false, false, 2, 2, 0, 0, 0, BAN)
	all_cards["reinforce"] = _make_card("reinforce", "Reinforce", "Gain {B} Block.\nGain {M} Strength.", 2, S, UC, SL, 0, 14, 1, 0, false, false, 0, 4, 0, 1, 0, BAN)
	all_cards["scorch"] = _make_card("scorch", "Scorch", "Deal {D} damage to ALL enemies.", 2, A, UC, AE, 10, 0, 0, 0, false, false, 4, 0, 0, 0, 0, BAN)
	all_cards["taunt"] = _make_card("taunt", "Taunt", "Apply {M} Weak to ALL enemies.", 1, S, UC, AE, 0, 0, 2, 0, false, false, 0, 0, 0, 1, 0, BAN)
	all_cards["iron_hide"] = _make_card("iron_hide", "Iron Hide", "Gain {B} Block.\nGain {M} Strength.", 1, S, UC, SL, 0, 10, 1, 0, false, false, 0, 4, 0, 1, 0, BAN)
	all_cards["final_command"] = _make_card("final_command", "Final Command", "Deal {D} damage to ALL enemies.\nApply {M} Vulnerable to ALL enemies.", 2, A, RA, AE, 14, 0, 1, 0, false, false, 5, 0, 0, 1, 0, BAN)
	all_cards["onslaught"] = _make_card("onslaught", "Onslaught", "Deal {D} damage.\nApply {M} Weak.", 3, A, RA, SE, 24, 0, 2, 0, false, false, 8, 0, 0, 1, 0, BAN)

	# ============================================================
	# Legacy Ironclad-flavored pool — tagged RONIN (sword/strength theme)
	# ============================================================
	all_cards["iron_wave"] = _make_card("iron_wave", "Iron Wave", "Deal {D} damage.\nGain {B} Block.", 1, A, CO, SE, 5, 5, 0, 0, false, false, 2, 2, 0, 0, 0, RON)
	all_cards["pommel_strike"] = _make_card("pommel_strike", "Pommel Strike", "Deal {D} damage.\nDraw {M} card(s).", 1, A, CO, SE, 9, 0, 1, 0, false, false, 1, 0, 0, 1, 0, RON)
	all_cards["shrug_it_off"] = _make_card("shrug_it_off", "Shrug It Off", "Gain {B} Block.\nDraw 1 card.", 1, S, CO, SL, 0, 8, 1, 0, false, false, 0, 3, 0, 0, 0, RON)
	all_cards["clothesline"] = _make_card("clothesline", "Clothesline", "Deal {D} damage.\nApply {M} Weak.", 2, A, CO, SE, 12, 0, 2, 0, false, false, 2, 0, 0, 1, 0, RON)
	all_cards["twin_strike"] = _make_card("twin_strike", "Twin Strike", "Deal {D} damage twice.", 1, A, CO, SE, 5, 0, 0, 1, false, false, 2, 0, 0, 0, 0, RON)
	all_cards["armaments"] = _make_card("armaments", "Armaments", "Gain {B} Block.", 1, S, CO, SL, 0, 5, 0, 0, false, false, 0, 3, 0, 0, 0, RON)
	all_cards["inflame"] = _make_card("inflame", "Inflame", "Gain {M} Strength.", 1, P, UC, SL, 0, 0, 2, 0, false, false, 0, 0, 0, 1, 0, RON)
	all_cards["bloodletting"] = _make_card("bloodletting", "Bloodletting", "Lose {M} HP.\nGain 2 Energy.", 0, S, UC, SL, 0, 0, 3, 0, false, false, 0, 0, 0, -1, 0, RON)
	all_cards["carnage"] = _make_card("carnage", "Carnage", "Ethereal.\nDeal {D} damage.", 2, A, UC, SE, 20, 0, 0, 0, false, true, 8, 0, 0, 0, 0, RON)
	all_cards["uppercut"] = _make_card("uppercut", "Uppercut", "Deal {D} damage.\nApply {M} Weak.\nApply {M} Vulnerable.", 2, A, UC, SE, 13, 0, 1, 0, false, false, 0, 0, 0, 1, 0, RON)
	all_cards["headbutt"] = _make_card("headbutt", "Headbutt", "Deal {D} damage.\nPut a card from discard on top of draw.", 1, A, UC, SE, 9, 0, 0, 0, false, false, 3, 0, 0, 0, 0, RON)
	all_cards["body_slam"] = _make_card("body_slam", "Body Slam", "Deal damage equal to your Block.", 1, A, UC, SE, 0, 0, 0, 0, false, false, 0, 0, 1, 0, 0, RON)
	all_cards["rage"] = _make_card("rage", "Rage", "Gain {B} Block.\nGain {M} Strength this turn.", 1, S, UC, SL, 0, 5, 2, 0, false, false, 0, 3, 0, 1, 0, RON)
	all_cards["rampage"] = _make_card("rampage", "Rampage", "Deal {D} damage.\nIncrease this card's damage by 5.", 1, A, UC, SE, 8, 0, 5, 0, false, false, 3, 0, 0, 0, 0, RON)
	all_cards["seeing_red"] = _make_card("seeing_red", "Seeing Red", "Gain 2 Energy. Exhaust.", 1, S, UC, SL, 0, 0, 2, 0, true, false, 0, 0, 1, 0, 0, RON)
	all_cards["disarm"] = _make_card("disarm", "Disarm", "Enemy loses {M} Strength. Exhaust.", 1, S, UC, SE, 0, 0, 2, 0, true, false, 0, 0, 0, 1, 0, RON)
	all_cards["flame_barrier"] = _make_card("flame_barrier", "Flame Barrier", "Gain {B} Block.\nWhen hit this turn, deal {M} damage back.", 2, S, UC, SL, 0, 12, 4, 0, false, false, 0, 4, 0, 2, 0, RON)
	all_cards["power_through"] = _make_card("power_through", "Power Through", "Gain {B} Block. Add 2 Wounds to hand.", 1, S, UC, SL, 0, 15, 0, 0, false, false, 0, 5, 0, 0, 0, RON)
	all_cards["spot_weakness"] = _make_card("spot_weakness", "Spot Weakness", "If enemy intends to attack, gain {M} Strength.", 1, S, UC, SE, 0, 0, 3, 0, false, false, 0, 0, 0, 1, 0, RON)
	all_cards["sever_soul"] = _make_card("sever_soul", "Sever Soul", "Deal {D} damage.\nExhaust all non-Attack cards in hand.", 2, A, UC, SE, 16, 0, 0, 0, false, false, 6, 0, 0, 0, 0, RON)
	all_cards["sentinel"] = _make_card("sentinel", "Sentinel", "Gain {B} Block.\nIf Exhausted, gain 2 Energy.", 1, S, UC, SL, 0, 5, 0, 0, false, false, 0, 3, 0, 0, 0, RON)
	all_cards["bludgeon"] = _make_card("bludgeon", "Bludgeon", "Deal {D} damage.", 3, A, RA, SE, 32, 0, 0, 0, false, false, 10, 0, 0, 0, 0, RON)
	all_cards["demon_form"] = _make_card("demon_form", "Demon Form", "POWER: At the start of each turn, gain {M} Strength.", 3, P, RA, SL, 0, 0, 2, 0, false, false, 0, 0, 0, 1, 0, RON)
	all_cards["offering"] = _make_card("offering", "Offering", "Lose 6 HP.\nGain 2 Energy.\nDraw {M} cards. Exhaust.", 0, S, RA, SL, 0, 0, 3, 0, true, false, 0, 0, 0, 2, 0, RON)
	all_cards["limit_break"] = _make_card("limit_break", "Limit Break", "Double your Strength. Exhaust.", 1, S, RA, SL, 0, 0, 0, 0, true, false, 0, 0, 0, 0, 0, RON)

	# Legacy AOE / multi-hit cards — tagged YUMI (ranged volley feel)
	all_cards["cleave"] = _make_card("cleave", "Cleave", "Deal {D} damage to ALL enemies.", 1, A, CO, AE, 8, 0, 0, 0, false, false, 3, 0, 0, 0, 0, YUM)
	all_cards["battle_trance"] = _make_card("battle_trance", "Battle Trance", "Draw {M} cards.", 0, S, UC, SL, 0, 0, 3, 0, false, false, 0, 0, 0, 1, 0, YUM)
	all_cards["whirlwind"] = _make_card("whirlwind", "Whirlwind", "Deal {D} damage to ALL enemies X times.\n(X = current Energy)", 0, A, UC, AE, 5, 0, 0, 0, false, false, 3, 0, 0, 0, 0, YUM)
	all_cards["reaper"] = _make_card("reaper", "Reaper", "Deal {D} damage to ALL enemies.\nHeal HP equal to damage dealt.", 2, A, RA, AE, 4, 0, 0, 0, false, false, 4, 0, 0, 0, 0, YUM)

	# Legacy tank / power cards — tagged BANNER
	all_cards["metallicize"] = _make_card("metallicize", "Metallicize", "POWER: Gain {M} Block at the end of each turn.", 1, P, UC, SL, 0, 0, 3, 0, false, false, 0, 0, 0, 1, 0, BAN)
	all_cards["barricade"] = _make_card("barricade", "Barricade", "POWER: Block no longer expires.", 3, P, RA, SL, 0, 0, 1, 0, false, false, 0, 0, 1, 0, 0, BAN)
	all_cards["immolate"] = _make_card("immolate", "Immolate", "Deal {D} damage to ALL enemies.", 2, A, RA, AE, 21, 0, 0, 0, false, false, 7, 0, 0, 0, 0, BAN)

	# Status / Curse cards (added to deck by enemies or events)
	all_cards["wound"] = _make_card("wound", "Wound", "Unplayable.", 99, CardData.CardType.STATUS, CardData.CardRarity.SPECIAL, SL, 0, 0, 0)
	all_cards["dazed"] = _make_card("dazed", "Dazed", "Unplayable. Ethereal.", 99, CardData.CardType.STATUS, CardData.CardRarity.SPECIAL, SL, 0, 0, 0, 0, false, true)
	all_cards["burn"] = _make_card("burn", "Burn", "Unplayable.\nAt end of turn, take 2 damage.", 99, CardData.CardType.STATUS, CardData.CardRarity.SPECIAL, SL, 0, 0, 2)
	all_cards["curse_pain"] = _make_card("curse_pain", "Pain", "While in hand, lose 1 HP when another card is played.", 99, CardData.CardType.CURSE, CardData.CardRarity.SPECIAL, SL, 0, 0, 1)


func _make_enemy(id: String, ename: String, etype: EnemyData.EnemyType,
		hp_min: int, hp_max: int, col: Color, pattern: String,
		moves_arr: Array, sprite: String = "") -> EnemyData:
	if all_enemies.has(id):
		return all_enemies[id]
	var e = EnemyData.new()
	e.id = id
	e.enemy_name = ename
	e.enemy_type = etype
	e.min_hp = hp_min
	e.max_hp = hp_max
	e.color = col
	e.ai_pattern = pattern
	e.moves = moves_arr
	e.idle_sprite_path = sprite
	return e


func _create_enemies_in_code() -> void:
	var jaw_worm = EnemyData.new()
	jaw_worm.id = "jaw_worm"
	jaw_worm.enemy_name = "Jaw Worm"
	jaw_worm.enemy_type = EnemyData.EnemyType.NORMAL
	jaw_worm.min_hp = 40
	jaw_worm.max_hp = 44
	jaw_worm.color = Color(0.6, 0.15, 0.15)
	jaw_worm.ai_pattern = "sequential"
	jaw_worm.moves = [
		{"name": "Chomp", "type": "attack", "damage": 11, "block": 0, "times": 1},
		{"name": "Thrash", "type": "attack", "damage": 7, "block": 0, "times": 1},
		{"name": "Bellow", "type": "buff", "damage": 0, "block": 5, "effect_name": "strength", "effect_value": 3, "times": 1}
	]
	all_enemies["jaw_worm"] = jaw_worm

	var cultist = EnemyData.new()
	cultist.id = "cultist"
	cultist.enemy_name = "Cultist"
	cultist.enemy_type = EnemyData.EnemyType.NORMAL
	cultist.min_hp = 48
	cultist.max_hp = 54
	cultist.color = Color(0.5, 0.2, 0.6)
	cultist.ai_pattern = "sequential"
	cultist.moves = [
		{"name": "Incantation", "type": "buff", "damage": 0, "block": 0, "effect_name": "strength", "effect_value": 3, "times": 1},
		{"name": "Dark Strike", "type": "attack", "damage": 6, "block": 0, "times": 1}
	]
	all_enemies["cultist"] = cultist

	var louse = EnemyData.new()
	louse.id = "louse_red"
	louse.enemy_name = "Red Louse"
	louse.enemy_type = EnemyData.EnemyType.NORMAL
	louse.min_hp = 10
	louse.max_hp = 15
	louse.color = Color(0.7, 0.3, 0.1)
	louse.ai_pattern = "random_no_repeat"
	louse.moves = [
		{"name": "Bite", "type": "attack", "damage": 6, "block": 0, "times": 1},
		{"name": "Grow", "type": "buff", "damage": 0, "block": 0, "effect_name": "strength", "effect_value": 3, "times": 1}
	]
	all_enemies["louse_red"] = louse

	var nob = EnemyData.new()
	nob.id = "gremlin_nob"
	nob.enemy_name = "Gremlin Nob"
	nob.enemy_type = EnemyData.EnemyType.ELITE
	nob.min_hp = 82
	nob.max_hp = 86
	nob.color = Color(0.2, 0.5, 0.15)
	nob.ai_pattern = "sequential"
	nob.moves = [
		{"name": "Bellow", "type": "buff", "damage": 0, "block": 0, "effect_name": "strength", "effect_value": 2, "times": 1},
		{"name": "Rush", "type": "attack", "damage": 14, "block": 0, "times": 1},
		{"name": "Skull Bash", "type": "attack_debuff", "damage": 8, "block": 0, "effect_name": "vulnerable", "effect_value": 2, "times": 1}
	]
	all_enemies["gremlin_nob"] = nob

	# --- More Normal Enemies ---
	var slime_m = EnemyData.new()
	slime_m.id = "acid_slime_m"
	slime_m.enemy_name = "Acid Slime"
	slime_m.enemy_type = EnemyData.EnemyType.NORMAL
	slime_m.min_hp = 28
	slime_m.max_hp = 32
	slime_m.color = Color(0.2, 0.6, 0.15)
	slime_m.ai_pattern = "random_no_repeat"
	slime_m.moves = [
		{"name": "Tackle", "type": "attack", "damage": 10, "block": 0, "times": 1},
		{"name": "Corrosive Spit", "type": "attack_debuff", "damage": 7, "block": 0, "effect_name": "weak", "effect_value": 1, "times": 1},
		{"name": "Lick", "type": "debuff", "damage": 0, "block": 0, "effect_name": "weak", "effect_value": 2, "times": 1}
	]
	all_enemies["acid_slime_m"] = slime_m

	var fungi = EnemyData.new()
	fungi.id = "fungi_beast"
	fungi.enemy_name = "Fungi Beast"
	fungi.enemy_type = EnemyData.EnemyType.NORMAL
	fungi.min_hp = 22
	fungi.max_hp = 28
	fungi.color = Color(0.45, 0.35, 0.55)
	fungi.ai_pattern = "sequential"
	fungi.moves = [
		{"name": "Bite", "type": "attack", "damage": 6, "block": 0, "times": 1},
		{"name": "Grow", "type": "buff", "damage": 0, "block": 0, "effect_name": "strength", "effect_value": 3, "times": 1},
		{"name": "Bite", "type": "attack", "damage": 6, "block": 0, "times": 2}
	]
	all_enemies["fungi_beast"] = fungi

	var blue_slaver = EnemyData.new()
	blue_slaver.id = "blue_slaver"
	blue_slaver.enemy_name = "Blue Slaver"
	blue_slaver.enemy_type = EnemyData.EnemyType.NORMAL
	blue_slaver.min_hp = 46
	blue_slaver.max_hp = 50
	blue_slaver.color = Color(0.2, 0.3, 0.7)
	blue_slaver.ai_pattern = "sequential"
	blue_slaver.moves = [
		{"name": "Stab", "type": "attack", "damage": 12, "block": 0, "times": 1},
		{"name": "Rake", "type": "attack_debuff", "damage": 7, "block": 0, "effect_name": "weak", "effect_value": 1, "times": 1}
	]
	all_enemies["blue_slaver"] = blue_slaver

	# --- More Elites ---
	var lagavulin = EnemyData.new()
	lagavulin.id = "lagavulin"
	lagavulin.enemy_name = "Lagavulin"
	lagavulin.enemy_type = EnemyData.EnemyType.ELITE
	lagavulin.min_hp = 109
	lagavulin.max_hp = 112
	lagavulin.color = Color(0.25, 0.25, 0.35)
	lagavulin.ai_pattern = "sequential"
	lagavulin.moves = [
		{"name": "Attack", "type": "attack", "damage": 18, "block": 0, "times": 1},
		{"name": "Siphon Soul", "type": "debuff", "damage": 0, "block": 0, "effect_name": "weak", "effect_value": 1, "times": 1},
		{"name": "Attack", "type": "attack", "damage": 18, "block": 0, "times": 1}
	]
	all_enemies["lagavulin"] = lagavulin

	var sentries = EnemyData.new()
	sentries.id = "sentry"
	sentries.enemy_name = "Sentry"
	sentries.enemy_type = EnemyData.EnemyType.ELITE
	sentries.min_hp = 38
	sentries.max_hp = 42
	sentries.color = Color(0.6, 0.5, 0.2)
	sentries.ai_pattern = "sequential"
	sentries.moves = [
		{"name": "Bolt", "type": "attack", "damage": 9, "block": 0, "times": 1},
		{"name": "Beam", "type": "attack", "damage": 9, "block": 0, "times": 1}
	]
	all_enemies["sentry"] = sentries

	# --- Bosses ---
	var guardian = EnemyData.new()
	guardian.id = "the_guardian"
	guardian.enemy_name = "The Guardian"
	guardian.enemy_type = EnemyData.EnemyType.BOSS
	guardian.min_hp = 240
	guardian.max_hp = 250
	guardian.color = Color(0.8, 0.7, 0.2)
	guardian.ai_pattern = "sequential"
	guardian.moves = [
		{"name": "Fierce Bash", "type": "attack", "damage": 32, "block": 0, "times": 1},
		{"name": "Vent Steam", "type": "debuff", "damage": 0, "block": 0, "effect_name": "weak", "effect_value": 2, "times": 1},
		{"name": "Whirlwind", "type": "attack", "damage": 5, "block": 0, "times": 4},
		{"name": "Defend Mode", "type": "defend", "damage": 0, "block": 20, "times": 1}
	]
	all_enemies["the_guardian"] = guardian

	var hexaghost = EnemyData.new()
	hexaghost.id = "hexaghost"
	hexaghost.enemy_name = "Hexaghost"
	hexaghost.enemy_type = EnemyData.EnemyType.BOSS
	hexaghost.min_hp = 250
	hexaghost.max_hp = 264
	hexaghost.color = Color(0.8, 0.2, 0.6)
	hexaghost.ai_pattern = "sequential"
	hexaghost.moves = [
		{"name": "Activate", "type": "buff", "damage": 0, "block": 0, "effect_name": "strength", "effect_value": 2, "times": 1},
		{"name": "Divider", "type": "attack", "damage": 6, "block": 0, "times": 6},
		{"name": "Sear", "type": "attack", "damage": 6, "block": 0, "times": 1},
		{"name": "Inferno", "type": "attack", "damage": 2, "block": 0, "times": 6},
		{"name": "Tackle", "type": "attack", "damage": 12, "block": 0, "times": 2}
	]
	all_enemies["hexaghost"] = hexaghost

	# ============================================================
	# ROBOTS — mechanical, armoured feel
	# ============================================================
	var N = EnemyData.EnemyType.NORMAL
	var EL = EnemyData.EnemyType.ELITE
	var BO = EnemyData.EnemyType.BOSS

	all_enemies["robot_swordsman"] = _make_enemy(
		"robot_swordsman", "Iron Swordsman", N, 50, 56,
		Color(0.5, 0.55, 0.65), "sequential",
		[
			{"name": "Slash", "type": "attack", "damage": 12, "block": 0, "times": 1},
			{"name": "Charge", "type": "buff", "damage": 0, "block": 0, "effect_name": "strength", "effect_value": 1, "times": 1},
			{"name": "Slash", "type": "attack", "damage": 12, "block": 0, "times": 1},
			{"name": "Guard", "type": "defend", "damage": 0, "block": 10, "times": 1}
		],
		"res://assets/enemis/mobs/robots/Swordsman/Idle.png"
	)

	all_enemies["robot_infantryman"] = _make_enemy(
		"robot_infantryman", "Infantryman", N, 38, 44,
		Color(0.45, 0.5, 0.6), "random_no_repeat",
		[
			{"name": "Shot", "type": "attack", "damage": 5, "block": 0, "times": 3},
			{"name": "Aim", "type": "buff", "damage": 0, "block": 0, "effect_name": "strength", "effect_value": 1, "times": 1},
			{"name": "Cover", "type": "defend", "damage": 0, "block": 8, "times": 1}
		],
		"res://assets/enemis/mobs/robots/Infantryman/Idle.png"
	)

	all_enemies["robot_destroyer"] = _make_enemy(
		"robot_destroyer", "Destroyer", EL, 90, 100,
		Color(0.35, 0.4, 0.5), "sequential",
		[
			{"name": "Power Up", "type": "buff", "damage": 0, "block": 0, "effect_name": "strength", "effect_value": 2, "times": 1},
			{"name": "Heavy Slam", "type": "attack", "damage": 22, "block": 0, "times": 1},
			{"name": "Shield Mode", "type": "defend", "damage": 0, "block": 14, "times": 1},
			{"name": "Blast", "type": "attack", "damage": 10, "block": 0, "times": 2}
		],
		"res://assets/enemis/mobs/robots/Destroyer/Idle.png"
	)

	# ============================================================
	# VAMPIRES — life drain, weakness debuffs
	# ============================================================
	all_enemies["vampire_girl"] = _make_enemy(
		"vampire_girl", "Vampire Girl", N, 42, 48,
		Color(0.55, 0.15, 0.35), "random_no_repeat",
		[
			{"name": "Scratch", "type": "attack", "damage": 8, "block": 0, "times": 1},
			{"name": "Hiss", "type": "debuff", "damage": 0, "block": 0, "effect_name": "weak", "effect_value": 1, "times": 1},
			{"name": "Blood Drain", "type": "attack_debuff", "damage": 6, "block": 0, "effect_name": "vulnerable", "effect_value": 1, "times": 1}
		],
		"res://assets/enemis/mobs/vamps/Vampire_Girl/Idle.png"
	)

	all_enemies["converted_vampire"] = _make_enemy(
		"converted_vampire", "Converted Vampire", N, 52, 58,
		Color(0.5, 0.1, 0.3), "sequential",
		[
			{"name": "Claw", "type": "attack", "damage": 10, "block": 0, "times": 1},
			{"name": "Blood Rush", "type": "attack_debuff", "damage": 12, "block": 0, "effect_name": "vulnerable", "effect_value": 1, "times": 1},
			{"name": "Claw", "type": "attack", "damage": 10, "block": 0, "times": 1}
		],
		"res://assets/enemis/mobs/vamps/Converted_Vampire/Idle.png"
	)

	all_enemies["countess_vampire"] = _make_enemy(
		"countess_vampire", "Countess Vampire", EL, 78, 86,
		Color(0.6, 0.05, 0.25), "sequential",
		[
			{"name": "Mesmerize", "type": "debuff", "damage": 0, "block": 0, "effect_name": "weak", "effect_value": 2, "times": 1},
			{"name": "Slash", "type": "attack", "damage": 18, "block": 0, "times": 1},
			{"name": "Blood Surge", "type": "buff", "damage": 0, "block": 0, "effect_name": "strength", "effect_value": 2, "times": 1},
			{"name": "Grand Slash", "type": "attack", "damage": 22, "block": 0, "times": 1}
		],
		"res://assets/enemis/mobs/vamps/Countess_Vampire/Idle.png"
	)

	# ============================================================
	# YOUKAI — supernatural, curse and fear
	# ============================================================
	all_enemies["gotoku"] = _make_enemy(
		"gotoku", "Gotoku", N, 40, 46,
		Color(0.25, 0.45, 0.35), "sequential",
		[
			{"name": "Scratch", "type": "attack", "damage": 7, "block": 0, "times": 1},
			{"name": "Scream", "type": "debuff", "damage": 0, "block": 0, "effect_name": "weak", "effect_value": 2, "times": 1},
			{"name": "Lunge", "type": "attack", "damage": 10, "block": 0, "times": 1}
		],
		"res://assets/enemis/mobs/youkai/Gotoku/Idle.png"
	)

	all_enemies["onre"] = _make_enemy(
		"onre", "Onre", N, 44, 50,
		Color(0.2, 0.35, 0.5), "random_no_repeat",
		[
			{"name": "Curse", "type": "debuff", "damage": 0, "block": 0, "effect_name": "vulnerable", "effect_value": 2, "times": 1},
			{"name": "Spirit Strike", "type": "attack", "damage": 11, "block": 0, "times": 1},
			{"name": "Float", "type": "defend", "damage": 0, "block": 10, "times": 1}
		],
		"res://assets/enemis/mobs/youkai/Onre/Idle.png"
	)

	all_enemies["yurei"] = _make_enemy(
		"yurei", "Yurei", EL, 85, 95,
		Color(0.15, 0.3, 0.55), "sequential",
		[
			{"name": "Wail", "type": "debuff", "damage": 0, "block": 0, "effect_name": "weak", "effect_value": 2, "times": 1},
			{"name": "Surge", "type": "attack", "damage": 6, "block": 0, "times": 3},
			{"name": "Charge Up", "type": "buff", "damage": 0, "block": 8, "effect_name": "strength", "effect_value": 2, "times": 1},
			{"name": "Strike", "type": "attack", "damage": 16, "block": 0, "times": 1}
		],
		"res://assets/enemis/mobs/youkai/Yurei/Idle.png"
	)

	# ============================================================
	# BOSS — NightBorne
	# ============================================================
	all_enemies["nightborne"] = _make_enemy(
		"nightborne", "NightBorne", BO, 300, 320,
		Color(0.1, 0.05, 0.2), "sequential",
		[
			{"name": "Shadow Aura", "type": "buff", "damage": 0, "block": 0, "effect_name": "strength", "effect_value": 2, "times": 1},
			{"name": "Night Slash", "type": "attack", "damage": 22, "block": 0, "times": 1},
			{"name": "Drain Soul", "type": "attack_debuff", "damage": 16, "block": 0, "effect_name": "vulnerable", "effect_value": 1, "times": 1},
			{"name": "Dark Wave", "type": "attack", "damage": 8, "block": 0, "times": 3},
			{"name": "Shadow Shroud", "type": "buff", "damage": 0, "block": 18, "effect_name": "strength", "effect_value": 1, "times": 1}
		],
		"res://assets/enemis/bosses/NightBorne/NightBorne.png"
	)


func _create_relics_in_code() -> void:
	var bb = RelicData.new()
	bb.id = "burning_blood"
	bb.relic_name = "Burning Blood"
	bb.description = "At the end of combat, heal 6 HP."
	bb.rarity = RelicData.RelicRarity.STARTER
	bb.trigger = "on_combat_end"
	bb.effect_value = 6
	bb.effect_type = "heal"
	all_relics["burning_blood"] = bb

	# Class starter relics
	var whetstone = RelicData.new()
	whetstone.id = "whetstone"
	whetstone.relic_name = "Whetstone"
	whetstone.description = "At the start of combat, gain 2 Strength."
	whetstone.rarity = RelicData.RelicRarity.STARTER
	whetstone.trigger = "on_combat_start"
	whetstone.effect_value = 2
	whetstone.effect_type = "strength"
	all_relics["whetstone"] = whetstone

	var quiver = RelicData.new()
	quiver.id = "quiver"
	quiver.relic_name = "Quiver"
	quiver.description = "At the start of each turn, draw 1 additional card."
	quiver.rarity = RelicData.RelicRarity.STARTER
	quiver.trigger = "on_turn_start"
	quiver.effect_value = 1
	quiver.effect_type = "draw"
	all_relics["quiver"] = quiver

	var standard = RelicData.new()
	standard.id = "standard"
	standard.relic_name = "Standard"
	standard.description = "At the start of combat, gain 5 Block."
	standard.rarity = RelicData.RelicRarity.STARTER
	standard.trigger = "on_combat_start"
	standard.effect_value = 5
	standard.effect_type = "block"
	all_relics["standard"] = standard

	# Common relics
	var vajra = RelicData.new()
	vajra.id = "vajra"
	vajra.relic_name = "Vajra"
	vajra.description = "At the start of combat, gain 1 Strength."
	vajra.rarity = RelicData.RelicRarity.COMMON
	vajra.trigger = "on_combat_start"
	vajra.effect_value = 1
	vajra.effect_type = "strength"
	all_relics["vajra"] = vajra

	var anchor = RelicData.new()
	anchor.id = "anchor"
	anchor.relic_name = "Anchor"
	anchor.description = "At the start of combat, gain 10 Block."
	anchor.rarity = RelicData.RelicRarity.COMMON
	anchor.trigger = "on_combat_start"
	anchor.effect_value = 10
	anchor.effect_type = "block"
	all_relics["anchor"] = anchor

	var bag_of_marbles = RelicData.new()
	bag_of_marbles.id = "bag_of_marbles"
	bag_of_marbles.relic_name = "Bag of Marbles"
	bag_of_marbles.description = "At the start of combat, apply 1 Vulnerable to ALL enemies."
	bag_of_marbles.rarity = RelicData.RelicRarity.COMMON
	bag_of_marbles.trigger = "on_combat_start"
	bag_of_marbles.effect_value = 1
	bag_of_marbles.effect_type = "vulnerable_all"
	all_relics["bag_of_marbles"] = bag_of_marbles

	var lantern = RelicData.new()
	lantern.id = "lantern"
	lantern.relic_name = "Lantern"
	lantern.description = "Gain 1 Energy on the first turn of combat."
	lantern.rarity = RelicData.RelicRarity.COMMON
	lantern.trigger = "on_combat_start"
	lantern.effect_value = 1
	lantern.effect_type = "energy"
	all_relics["lantern"] = lantern

	var oddly_smooth_stone = RelicData.new()
	oddly_smooth_stone.id = "oddly_smooth_stone"
	oddly_smooth_stone.relic_name = "Oddly Smooth Stone"
	oddly_smooth_stone.description = "At the start of combat, gain 1 Dexterity."
	oddly_smooth_stone.rarity = RelicData.RelicRarity.COMMON
	oddly_smooth_stone.trigger = "on_combat_start"
	oddly_smooth_stone.effect_value = 1
	oddly_smooth_stone.effect_type = "dexterity"
	all_relics["oddly_smooth_stone"] = oddly_smooth_stone

	# Uncommon relics
	var ornamental_fan = RelicData.new()
	ornamental_fan.id = "ornamental_fan"
	ornamental_fan.relic_name = "Ornamental Fan"
	ornamental_fan.description = "Every 3 attacks played, gain 4 Block."
	ornamental_fan.rarity = RelicData.RelicRarity.UNCOMMON
	ornamental_fan.trigger = "on_attack_played"
	ornamental_fan.effect_value = 4
	ornamental_fan.effect_type = "block_every_3"
	all_relics["ornamental_fan"] = ornamental_fan

	var pen_nib = RelicData.new()
	pen_nib.id = "pen_nib"
	pen_nib.relic_name = "Pen Nib"
	pen_nib.description = "Every 10 attacks played, deal double damage."
	pen_nib.rarity = RelicData.RelicRarity.UNCOMMON
	pen_nib.trigger = "on_attack_played"
	pen_nib.effect_value = 10
	pen_nib.effect_type = "double_damage"
	all_relics["pen_nib"] = pen_nib

	var meat_on_the_bone = RelicData.new()
	meat_on_the_bone.id = "meat_on_the_bone"
	meat_on_the_bone.relic_name = "Meat on the Bone"
	meat_on_the_bone.description = "If HP is at or below 50% at end of combat, heal 12."
	meat_on_the_bone.rarity = RelicData.RelicRarity.UNCOMMON
	meat_on_the_bone.trigger = "on_combat_end"
	meat_on_the_bone.effect_value = 12
	meat_on_the_bone.effect_type = "heal_low"
	all_relics["meat_on_the_bone"] = meat_on_the_bone

	var bag_of_preparation = RelicData.new()
	bag_of_preparation.id = "bag_of_preparation"
	bag_of_preparation.relic_name = "Bag of Preparation"
	bag_of_preparation.description = "Draw 2 additional cards on your first turn."
	bag_of_preparation.rarity = RelicData.RelicRarity.UNCOMMON
	bag_of_preparation.trigger = "on_combat_start"
	bag_of_preparation.effect_value = 2
	bag_of_preparation.effect_type = "draw"
	all_relics["bag_of_preparation"] = bag_of_preparation

	# Rare relics
	var thread_and_needle = RelicData.new()
	thread_and_needle.id = "thread_and_needle"
	thread_and_needle.relic_name = "Thread and Needle"
	thread_and_needle.description = "At the start of combat, gain 4 Plated Armor."
	thread_and_needle.rarity = RelicData.RelicRarity.RARE
	thread_and_needle.trigger = "on_combat_start"
	thread_and_needle.effect_value = 4
	thread_and_needle.effect_type = "metallicize"
	all_relics["thread_and_needle"] = thread_and_needle

	var shovel = RelicData.new()
	shovel.id = "shovel"
	shovel.relic_name = "Shovel"
	shovel.description = "You can now Dig at Rest Sites to find relics."
	shovel.rarity = RelicData.RelicRarity.RARE
	shovel.trigger = "passive"
	shovel.effect_value = 0
	shovel.effect_type = "dig"
	all_relics["shovel"] = shovel

	var red_skull = RelicData.new()
	red_skull.id = "red_skull"
	red_skull.relic_name = "Red Skull"
	red_skull.description = "While HP is at or below 50%, gain 3 Strength."
	red_skull.rarity = RelicData.RelicRarity.RARE
	red_skull.trigger = "on_combat_start"
	red_skull.effect_value = 3
	red_skull.effect_type = "strength_low_hp"
	all_relics["red_skull"] = red_skull
