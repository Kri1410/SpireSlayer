extends Node
## Manages all combat state and logic for a single encounter.

signal combat_state_changed

# Combat state
var in_combat: bool = false
var player_turn: bool = false
var turn_number: int = 0

# Energy
var max_energy: int = 3
var current_energy: int = 3

# Block
var player_block: int = 0

# Status effects on player: { "strength": 2, "vulnerable": 1, ... }
var player_statuses: Dictionary = {}

# Card piles
var draw_pile: Array[CardData] = []
var hand: Array[CardData] = []
var discard_pile: Array[CardData] = []
var exhaust_pile: Array[CardData] = []

# Living enemies in current combat (references to EnemyNode instances)
var enemies: Array = []

# Hand size
var hand_size: int = 5


func start_combat(enemy_nodes: Array) -> void:
	in_combat = true
	turn_number = 0
	current_energy = max_energy
	player_block = 0
	player_statuses.clear()
	hand.clear()
	discard_pile.clear()
	exhaust_pile.clear()
	enemies = enemy_nodes

	# Build draw pile from player's deck, shuffled
	draw_pile.clear()
	for card in GameManager.deck:
		draw_pile.append(card.duplicate_card())
	draw_pile.shuffle()

	# Draw innate cards first
	var innate_cards: Array[CardData] = []
	for card in draw_pile:
		if card.innate:
			innate_cards.append(card)
	for card in innate_cards:
		draw_pile.erase(card)
		hand.append(card)

	# Process combat-start relics
	_process_combat_start_relics()

	EventBus.combat_started.emit()
	start_player_turn()


func start_player_turn() -> void:
	turn_number += 1
	player_turn = true
	current_energy = max_energy
	# Block resets unless Barricade is active
	if not player_statuses.has("barricade"):
		player_block = 0
	EventBus.player_block_changed.emit(player_block)
	EventBus.player_energy_changed.emit(current_energy, max_energy)

	# Apply start-of-turn status effects
	_process_start_of_turn_statuses()

	# Check start-of-turn relics
	_process_start_of_turn_relics()

	# Draw cards (hand should be empty at start of turn)
	var extra_draw = 0
	if turn_number == 1:
		for relic in GameManager.relics:
			if relic.trigger == "on_combat_start" and relic.effect_type == "draw":
				extra_draw += relic.effect_value
	draw_cards(hand_size + extra_draw)

	EventBus.turn_started.emit(true)
	combat_state_changed.emit()


func end_player_turn() -> void:
	if not player_turn:
		return

	player_turn = false

	# Steel Plate (Banner): gain block at end of turn
	var steel_plate = get_player_status("steel_plate")
	if steel_plate > 0:
		add_player_block(steel_plate)

	# Discard hand (exhaust ethereal cards)
	var cards_to_discard = hand.duplicate()
	for card in cards_to_discard:
		if card.ethereal:
			exhaust_card(card)
		else:
			discard_card_from_hand(card)

	EventBus.turn_ended.emit(true)
	EventBus.hand_updated.emit()

	# Enemy turn
	await _execute_enemy_turns()

	# Check if player died during enemy turn
	if GameManager.current_hp <= 0:
		end_combat(false)
		return

	# Check if combat is over
	if _all_enemies_dead():
		end_combat(true)
		return

	# Start next player turn
	start_player_turn()


func draw_cards(count: int) -> void:
	for i in range(count):
		if hand.size() >= 10:  # Max hand size
			break
		if draw_pile.is_empty():
			_shuffle_discard_into_draw()
		if draw_pile.is_empty():
			break  # No cards left anywhere
		var card = draw_pile.pop_back()
		hand.append(card)
		EventBus.card_drawn.emit(card)
	EventBus.hand_updated.emit()


func can_play_card(card: CardData) -> bool:
	if not player_turn:
		return false
	# Status and Curse cards are unplayable
	if card.card_type == CardData.CardType.STATUS or card.card_type == CardData.CardType.CURSE:
		return false
	if card.get_effective_cost() > current_energy:
		return false
	return true


func play_card(card: CardData, target_enemy: Node = null) -> void:
	if not can_play_card(card):
		return

	# Whirlwind spends ALL energy
	var energy_cost = card.get_effective_cost()
	var whirlwind_hits = 0
	if card.id == "whirlwind":
		whirlwind_hits = current_energy
		energy_cost = current_energy

	# Spend energy
	current_energy -= energy_cost
	EventBus.player_energy_changed.emit(current_energy, max_energy)

	# Remove from hand
	hand.erase(card)

	# Pain curse: lose 1 HP for each Pain in hand when playing a card
	for hand_card in hand:
		if hand_card.id == "curse_pain":
			GameManager.take_damage(1)
			EventBus.player_damaged.emit(1)

	# Execute card effect (including Replay)
	var total_plays = 1 + card.get_effective_replay()
	if card.id == "whirlwind":
		total_plays = whirlwind_hits

	for i in range(total_plays):
		_execute_card_effect(card, target_enemy)

	# Handle card destination
	if card.exhaust:
		exhaust_pile.append(card)
		EventBus.card_exhausted.emit(card)
		# Sentinel: gain 2 energy when exhausted
		if card.id == "sentinel":
			current_energy += 2
			EventBus.player_energy_changed.emit(current_energy, max_energy)
	else:
		discard_pile.append(card)

	EventBus.card_played.emit(card)
	EventBus.hand_updated.emit()
	combat_state_changed.emit()

	# Check if any enemies died
	_check_dead_enemies()


func _execute_card_effect(card: CardData, target: Node) -> void:
	var damage = card.get_effective_damage()
	var block = card.get_effective_block()
	var magic = card.get_effective_magic()

	# Conditional damage overrides/bonuses (applied before strength/vuln math)
	match card.id:
		"killshot":
			if target and target.has_method("get_status") and target.get_status("vulnerable") > 0:
				damage += magic
		"honed_edge":
			if player_block > 0:
				damage += magic
		"true_shot":
			damage = 2 * hand.size()

	# Apply player strength to damage
	if damage > 0:
		damage += get_player_status("strength")

	# Apply vulnerability to target
	if damage > 0 and target and target.has_method("get_status"):
		if target.get_status("vulnerable") > 0:
			damage = int(damage * 1.5)

	# Apply weakness to player damage
	if damage > 0 and get_player_status("weak") > 0:
		damage = int(damage * 0.75)

	# --- Apply damage ---
	if card.card_type == CardData.CardType.ATTACK:
		if card.target_type == CardData.TargetType.ALL_ENEMIES:
			for enemy in enemies:
				if enemy and is_instance_valid(enemy) and not enemy.is_dead:
					enemy.take_damage(damage)
					EventBus.enemy_damaged.emit(enemy, damage)
		elif target and is_instance_valid(target):
			target.take_damage(damage)
			EventBus.enemy_damaged.emit(target, damage)

	# --- Apply block ---
	if block > 0:
		add_player_block(block)

	# --- Card-specific effects ---
	match card.id:
		"bash":
			if target and is_instance_valid(target):
				target.add_status("vulnerable", magic)
		"clothesline", "onslaught":
			if target and is_instance_valid(target):
				target.add_status("weak", magic)
		"uppercut":
			if target and is_instance_valid(target):
				target.add_status("weak", magic)
				target.add_status("vulnerable", magic)
		"pommel_strike":
			draw_cards(magic)
		"shrug_it_off":
			draw_cards(1)
		"battle_trance":
			draw_cards(magic)
		"bloodletting":
			GameManager.take_damage(magic)
			EventBus.player_damaged.emit(magic)
			current_energy += 2
			EventBus.player_energy_changed.emit(current_energy, max_energy)
		"inflame":
			add_player_status("strength", magic)
		"metallicize":
			add_player_status("metallicize", magic)
		"barricade":
			add_player_status("barricade", 1)
		"body_slam":
			# Damage equal to current block (override the normal damage which is 0)
			if target and is_instance_valid(target):
				var slam_dmg = player_block + get_player_status("strength")
				if get_player_status("weak") > 0:
					slam_dmg = int(slam_dmg * 0.75)
				if target.get_status("vulnerable") > 0:
					slam_dmg = int(slam_dmg * 1.5)
				target.take_damage(slam_dmg)
				EventBus.enemy_damaged.emit(target, slam_dmg)
		"rage":
			# Temporary strength (removed at end of turn)
			add_player_status("temp_strength", magic)
			add_player_status("strength", magic)
		"rampage":
			# Permanently increase this card's base damage
			card.damage += magic
		"headbutt":
			# Move top card of discard to top of draw pile
			if not discard_pile.is_empty():
				var top_card = discard_pile.pop_back()
				draw_pile.append(top_card)
		"seeing_red":
			current_energy += 2
			EventBus.player_energy_changed.emit(current_energy, max_energy)
		"disarm":
			if target and is_instance_valid(target):
				target.add_status("strength", -magic)
		"flame_barrier":
			add_player_status("flame_barrier", magic)
		"power_through":
			# Add 2 Wounds to hand
			if GameManager.all_cards.has("wound"):
				for i in range(2):
					var wound = GameManager.all_cards["wound"].duplicate_card()
					hand.append(wound)
		"spot_weakness":
			# If enemy intends to attack, gain strength
			if target and is_instance_valid(target) and target.current_intent.get("type", "") == "attack":
				add_player_status("strength", magic)
		"sever_soul":
			# Exhaust all non-Attack cards in hand
			var to_exhaust: Array[CardData] = []
			for hand_card in hand:
				if hand_card.card_type != CardData.CardType.ATTACK:
					to_exhaust.append(hand_card)
			for c in to_exhaust:
				exhaust_card(c)
		"demon_form":
			add_player_status("demon_form", magic)
		"offering":
			GameManager.take_damage(6)
			EventBus.player_damaged.emit(6)
			current_energy += 2
			EventBus.player_energy_changed.emit(current_energy, max_energy)
			draw_cards(magic)
		"reaper":
			# Heal equal to unblocked damage dealt (handled in damage section above)
			# We need special handling - damage was already dealt, so heal for it
			pass  # Healing handled below
		"limit_break":
			var current_str = get_player_status("strength")
			if current_str > 0:
				add_player_status("strength", current_str)
		"hunters_eye":
			if target and is_instance_valid(target):
				target.add_status("vulnerable", magic)
			draw_cards(1)
		"rally":
			for enemy in enemies:
				if enemy and is_instance_valid(enemy) and not enemy.is_dead:
					enemy.add_status("vulnerable", magic)
		"iaido", "heart_shot":
			# Refund 1 energy if the strike killed the target
			if target and is_instance_valid(target) and target.is_dead:
				current_energy += 1
				EventBus.player_energy_changed.emit(current_energy, max_energy)

		# --- YUMI (archer) effects ---
		"take_aim", "side_step":
			draw_cards(1)
		"quick_draw", "steady_aim":
			draw_cards(magic)
		"pinning_shot":
			if target and is_instance_valid(target):
				target.add_status("vulnerable", magic)
		"hunters_trap":
			if target and is_instance_valid(target):
				target.add_status("vulnerable", magic)
			draw_cards(1)
		"wind_slash":
			if target and is_instance_valid(target) and target.is_dead:
				draw_cards(2)
		"eagle_eye":
			add_player_status("eagle_eye", magic)

		# --- RONIN (swordsman) effects ---
		"focus_strike":
			add_player_status("strength", magic)
		"stoic_stance":
			add_player_status("strength", magic)
		"perfect_form":
			add_player_status("strength", magic)
		"bushido":
			add_player_status("bushido", magic)

		# --- BANNER (commander) effects ---
		"intimidate", "war_shout", "taunt":
			for enemy in enemies:
				if enemy and is_instance_valid(enemy) and not enemy.is_dead:
					enemy.add_status("weak", magic)
		"battle_cry", "banner_wave", "hunters_mark", "final_command":
			for enemy in enemies:
				if enemy and is_instance_valid(enemy) and not enemy.is_dead:
					enemy.add_status("vulnerable", magic)
		"iron_will", "rallying_cry", "reinforce", "iron_hide":
			add_player_status("strength", magic)
		"crushing_blow":
			if target and is_instance_valid(target) and target.get_status("vulnerable") > 0:
				target.add_status("weak", magic)
		"steel_plate":
			add_player_status("steel_plate", magic)
		"war_banner":
			add_player_status("war_banner", magic)

	# Reaper healing: damage was already dealt to all enemies above
	if card.id == "reaper":
		# Heal for the damage value (approximate - heals per enemy hit)
		for enemy in enemies:
			if enemy and is_instance_valid(enemy) and not enemy.is_dead:
				GameManager.heal(damage)
			elif enemy and is_instance_valid(enemy) and enemy.is_dead:
				GameManager.heal(damage)


func add_player_block(amount: int) -> void:
	# Apply dexterity
	amount += get_player_status("dexterity")
	if amount > 0:
		player_block += amount
		EventBus.player_block_changed.emit(player_block)
		EventBus.player_block_gained.emit(amount)


func apply_damage_to_player(amount: int, attacker: Node = null) -> void:
	# Reduce by block first
	var remaining = amount
	if player_block > 0:
		var blocked = min(player_block, remaining)
		player_block -= blocked
		remaining -= blocked
		EventBus.player_block_changed.emit(player_block)

	if remaining > 0:
		# Check vulnerability
		if get_player_status("vulnerable") > 0:
			remaining = int(remaining * 1.5)
		GameManager.take_damage(remaining)
		EventBus.player_damaged.emit(remaining)

	# Flame Barrier: deal damage back to attacker
	var fb = get_player_status("flame_barrier")
	if fb > 0 and attacker and is_instance_valid(attacker) and attacker.has_method("take_damage"):
		attacker.take_damage(fb)
		EventBus.enemy_damaged.emit(attacker, fb)


func add_player_status(status_name: String, stacks: int) -> void:
	if player_statuses.has(status_name):
		player_statuses[status_name] += stacks
	else:
		player_statuses[status_name] = stacks
	EventBus.status_applied.emit(null, status_name, player_statuses[status_name])


func get_player_status(status_name: String) -> int:
	return player_statuses.get(status_name, 0)


func _process_start_of_turn_statuses() -> void:
	# Metallicize: gain block at start of turn
	var metallicize = get_player_status("metallicize")
	if metallicize > 0:
		player_block += metallicize
		EventBus.player_block_changed.emit(player_block)

	# Demon Form: gain strength at start of turn
	var demon_form = get_player_status("demon_form")
	if demon_form > 0:
		add_player_status("strength", demon_form)

	# Bushido (Ronin): gain strength at start of turn
	var bushido = get_player_status("bushido")
	if bushido > 0:
		add_player_status("strength", bushido)

	# Eagle Eye (Yumi): draw extra card at start of turn
	var eagle_eye = get_player_status("eagle_eye")
	if eagle_eye > 0:
		draw_cards(eagle_eye)

	# War Banner (Banner): apply vulnerable to all enemies at start of turn
	var war_banner = get_player_status("war_banner")
	if war_banner > 0:
		for enemy in enemies:
			if enemy and is_instance_valid(enemy) and not enemy.is_dead:
				enemy.add_status("vulnerable", war_banner)

	# Remove temporary strength from Rage
	var temp_str = get_player_status("temp_strength")
	if temp_str > 0:
		add_player_status("strength", -temp_str)
		player_statuses.erase("temp_strength")

	# Clear flame barrier
	if player_statuses.has("flame_barrier"):
		player_statuses.erase("flame_barrier")

	# Burn cards in hand: take damage for each
	for card in hand:
		if card.id == "burn":
			GameManager.take_damage(2)
			EventBus.player_damaged.emit(2)

	# Decrement temporary statuses
	for status_name in ["vulnerable", "weak", "frail"]:
		if player_statuses.has(status_name):
			player_statuses[status_name] -= 1
			if player_statuses[status_name] <= 0:
				player_statuses.erase(status_name)
				EventBus.status_removed.emit(null, status_name)


func _process_combat_start_relics() -> void:
	for relic in GameManager.relics:
		if relic.trigger == "on_combat_start":
			match relic.effect_type:
				"strength":
					add_player_status("strength", relic.effect_value)
				"block":
					player_block += relic.effect_value
					EventBus.player_block_changed.emit(player_block)
				"dexterity":
					add_player_status("dexterity", relic.effect_value)
				"energy":
					current_energy += relic.effect_value
					EventBus.player_energy_changed.emit(current_energy, max_energy)
				"draw":
					# Extra draw on first turn handled in start_player_turn
					pass
				"metallicize":
					add_player_status("metallicize", relic.effect_value)
				"vulnerable_all":
					for enemy in enemies:
						if enemy and is_instance_valid(enemy) and not enemy.is_dead:
							enemy.add_status("vulnerable", relic.effect_value)
				"strength_low_hp":
					if GameManager.current_hp <= GameManager.max_hp / 2:
						add_player_status("strength", relic.effect_value)


func _process_start_of_turn_relics() -> void:
	for relic in GameManager.relics:
		if relic.trigger == "on_turn_start":
			match relic.effect_type:
				"draw":
					draw_cards(relic.effect_value)
				"energy":
					current_energy += relic.effect_value
					EventBus.player_energy_changed.emit(current_energy, max_energy)
				"block":
					add_player_block(relic.effect_value)


func _execute_enemy_turns() -> void:
	EventBus.turn_started.emit(false)
	for enemy in enemies:
		if enemy and is_instance_valid(enemy) and not enemy.is_dead:
			await enemy.execute_turn()
			await get_tree().create_timer(0.3).timeout
	EventBus.turn_ended.emit(false)


func _check_dead_enemies() -> void:
	for enemy in enemies:
		if enemy and is_instance_valid(enemy) and enemy.is_dead:
			EventBus.enemy_died.emit(enemy)


func _all_enemies_dead() -> bool:
	for enemy in enemies:
		if enemy and is_instance_valid(enemy) and not enemy.is_dead:
			return false
	return true


func end_combat(victory: bool) -> void:
	in_combat = false
	hand.clear()
	draw_pile.clear()
	discard_pile.clear()
	exhaust_pile.clear()

	# End-of-combat relics
	if victory:
		for relic in GameManager.relics:
			if relic.trigger == "on_combat_end":
				match relic.effect_type:
					"heal":
						GameManager.heal(relic.effect_value)
					"heal_low":
						if GameManager.current_hp <= GameManager.max_hp / 2:
							GameManager.heal(relic.effect_value)

	EventBus.combat_ended.emit(victory)


func discard_card_from_hand(card: CardData) -> void:
	hand.erase(card)
	discard_pile.append(card)
	EventBus.card_discarded.emit(card)


func exhaust_card(card: CardData) -> void:
	hand.erase(card)
	exhaust_pile.append(card)
	EventBus.card_exhausted.emit(card)


func _shuffle_discard_into_draw() -> void:
	draw_pile = discard_pile.duplicate()
	discard_pile.clear()
	draw_pile.shuffle()
