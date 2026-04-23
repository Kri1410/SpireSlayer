class_name EnemyNode
extends Control
## A single enemy instance in combat.

var enemy_data: EnemyData
var current_hp: int = 0
var max_hp: int = 0
var block: int = 0
var is_dead: bool = false
var statuses: Dictionary = {}

# AI state
var current_move_index: int = -1
var current_intent: Dictionary = {}
var last_move_index: int = -1

@onready var body_container: Control = $BodyContainer
@onready var body_rect: ColorRect = $BodyContainer/BodyRect
@onready var head: ColorRect = $BodyContainer/Head
@onready var hp_bar: ProgressBar = $HPBar
@onready var hp_label: Label = $HPBar/HPLabel
@onready var name_label: Label = $NameLabel
@onready var intent_label: Label = $IntentLabel
@onready var intent_bg: Panel = $IntentBg
@onready var block_label: Label = $BlockLabel
@onready var block_bg: Panel = $BlockBg
@onready var status_label: Label = $StatusLabel


func setup(data: EnemyData) -> void:
	enemy_data = data
	max_hp = randi_range(data.min_hp, data.max_hp)
	current_hp = max_hp
	is_dead = false
	block = 0
	statuses.clear()
	current_move_index = -1
	last_move_index = -1
	_update_visuals()
	_color_body()
	choose_next_move()


func _color_body() -> void:
	if not is_node_ready():
		await ready
	var base_color: Color = enemy_data.color
	var lighter = base_color.lightened(0.15)
	var darker = base_color.darkened(0.15)

	body_rect.color = base_color
	head.color = darker
	$BodyContainer/LeftArm.color = lighter
	$BodyContainer/RightArm.color = lighter
	$BodyContainer/LeftLeg.color = darker
	$BodyContainer/RightLeg.color = darker

	if enemy_data.enemy_type == EnemyData.EnemyType.BOSS:
		body_container.scale = Vector2(1.4, 1.4)
	elif enemy_data.enemy_type == EnemyData.EnemyType.ELITE:
		body_container.scale = Vector2(1.2, 1.2)


func _update_visuals() -> void:
	if not is_node_ready():
		await ready

	name_label.text = enemy_data.enemy_name
	hp_bar.max_value = max_hp
	hp_bar.value = current_hp
	hp_label.text = str(current_hp) + "/" + str(max_hp)

	if block > 0:
		block_label.visible = true
		block_label.text = str(block)
		if block_bg:
			block_bg.visible = true
	else:
		block_label.visible = false
		if block_bg:
			block_bg.visible = false

	var status_text = ""
	for status_name in statuses:
		if statuses[status_name] > 0:
			status_text += status_name.capitalize() + " " + str(statuses[status_name]) + "  "
	status_label.text = status_text

	_update_intent_display()


func _update_intent_display() -> void:
	if current_intent.is_empty():
		intent_label.text = ""
		if intent_bg:
			intent_bg.visible = false
		return

	if intent_bg:
		intent_bg.visible = true

	# Apply player's vulnerable to projected damage from this enemy
	var raw_dmg: int = current_intent.get("damage", 0)
	raw_dmg += get_status("strength")
	if get_status("weak") > 0:
		raw_dmg = int(raw_dmg * 0.75)

	match current_intent.get("type", ""):
		"attack":
			var times = current_intent.get("times", 1)
			if times > 1:
				intent_label.text = "⚔ %d × %d" % [raw_dmg, times]
			else:
				intent_label.text = "⚔ %d" % raw_dmg
			intent_label.add_theme_color_override("font_color", Color(1, 0.4, 0.3))
		"defend":
			intent_label.text = "🛡 %d" % current_intent.get("block", 0)
			intent_label.add_theme_color_override("font_color", Color(0.45, 0.78, 1))
		"buff":
			intent_label.text = "✪ Buff"
			intent_label.add_theme_color_override("font_color", Color(1, 0.85, 0.3))
		"debuff":
			intent_label.text = "☠ Debuff"
			intent_label.add_theme_color_override("font_color", Color(0.85, 0.4, 0.95))
		"attack_debuff":
			intent_label.text = "⚔ %d  ☠" % raw_dmg
			intent_label.add_theme_color_override("font_color", Color(1, 0.55, 0.4))
		_:
			intent_label.text = "??"
			intent_label.add_theme_color_override("font_color", Color(0.85, 0.5, 1))


func take_damage(amount: int) -> void:
	var remaining = amount
	if block > 0:
		var blocked = min(block, remaining)
		block -= blocked
		remaining -= blocked

	if remaining > 0:
		current_hp -= remaining
		# Damage flash + shake
		if body_container:
			var tween = create_tween()
			tween.tween_property(body_container, "modulate", Color(3, 0.5, 0.5), 0.06)
			tween.tween_property(body_container, "modulate", Color.WHITE, 0.2)

			# Squash on impact
			var squash_tween = create_tween()
			squash_tween.tween_property(body_container, "scale:x", body_container.scale.x * 1.2, 0.05)
			squash_tween.tween_property(body_container, "scale:y", body_container.scale.y * 0.85, 0.05)
			squash_tween.tween_property(body_container, "scale", body_container.scale, 0.15).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_ELASTIC)

	if current_hp <= 0:
		current_hp = 0
		is_dead = true
		_on_death()

	_update_visuals()


func add_status(status_name: String, stacks: int) -> void:
	if statuses.has(status_name):
		statuses[status_name] += stacks
	else:
		statuses[status_name] = stacks
	EventBus.status_applied.emit(self, status_name, statuses[status_name])
	_update_visuals()


func get_status(status_name: String) -> int:
	return statuses.get(status_name, 0)


func choose_next_move() -> void:
	if enemy_data.moves.is_empty():
		current_intent = {}
		return

	match enemy_data.ai_pattern:
		"sequential":
			current_move_index = (current_move_index + 1) % enemy_data.moves.size()
		"random_no_repeat":
			var new_index = randi() % enemy_data.moves.size()
			while new_index == last_move_index and enemy_data.moves.size() > 1:
				new_index = randi() % enemy_data.moves.size()
			current_move_index = new_index
		"conditional":
			current_move_index = _choose_conditional_move()

	current_intent = enemy_data.moves[current_move_index]
	last_move_index = current_move_index
	_update_intent_display()
	EventBus.enemy_intent_revealed.emit(self, current_intent)


func _choose_conditional_move() -> int:
	if current_hp < max_hp * 0.5:
		for i in range(enemy_data.moves.size()):
			if enemy_data.moves[i].get("type", "") == "defend":
				return i
	return 0


func execute_turn() -> void:
	if is_dead:
		return

	block = 0

	# Decrement statuses
	for status_name in ["vulnerable", "weak", "frail"]:
		if statuses.has(status_name):
			statuses[status_name] -= 1
			if statuses[status_name] <= 0:
				statuses.erase(status_name)
				EventBus.status_removed.emit(self, status_name)

	var move = current_intent
	var move_type = move.get("type", "")
	var damage = move.get("damage", 0)
	var blk = move.get("block", 0)

	damage += get_status("strength")
	if get_status("weak") > 0:
		damage = int(damage * 0.75)

	match move_type:
		"attack":
			var times = move.get("times", 1)
			for i in range(times):
				await _animate_attack()
				CombatManager.apply_damage_to_player(damage, self)
				await get_tree().create_timer(0.1).timeout
		"defend":
			await _animate_defend()
			block += blk
		"buff":
			await _animate_buff()
			var buff_name = move.get("effect_name", "strength")
			var buff_amount = move.get("effect_value", 1)
			add_status(buff_name, buff_amount)
			if blk > 0:
				block += blk
		"debuff":
			await _animate_attack()
			var debuff_name = move.get("effect_name", "weak")
			var debuff_amount = move.get("effect_value", 1)
			CombatManager.add_player_status(debuff_name, debuff_amount)
		"attack_debuff":
			await _animate_attack()
			CombatManager.apply_damage_to_player(damage, self)
			var debuff_name = move.get("effect_name", "vulnerable")
			var debuff_amount = move.get("effect_value", 1)
			CombatManager.add_player_status(debuff_name, debuff_amount)

	_update_visuals()
	choose_next_move()


# --- ANIMATIONS ---

func _animate_attack() -> void:
	if not body_container:
		return
	var original_pos = body_container.position
	# Lunge left toward player
	var lunge_offset = Vector2(-40, 0)

	var tween = create_tween()
	tween.tween_property(body_container, "position", original_pos + lunge_offset, 0.1).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_BACK)
	tween.tween_property(body_container, "position", original_pos, 0.15).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_ELASTIC)
	await tween.finished


func _animate_defend() -> void:
	if not body_container:
		return
	# Brief blue flash and slight scale up
	var tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(body_container, "modulate", Color(0.5, 0.7, 2.0), 0.12)
	tween.tween_property(body_container, "scale", body_container.scale * 1.05, 0.12)
	tween.chain().tween_property(body_container, "modulate", Color.WHITE, 0.2)
	tween.chain().tween_property(body_container, "scale", body_container.scale, 0.15)
	await tween.finished


func _animate_buff() -> void:
	if not body_container:
		return
	# Gold flash and pulse
	var tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(body_container, "modulate", Color(1.5, 1.2, 0.5), 0.15)
	tween.tween_property(body_container, "scale", body_container.scale * 1.1, 0.15)
	tween.chain().tween_property(body_container, "modulate", Color.WHITE, 0.25)
	tween.chain().tween_property(body_container, "scale", body_container.scale, 0.2).set_trans(Tween.TRANS_ELASTIC)
	await tween.finished


func _on_death() -> void:
	# Death animation: shake, turn red, shrink and fade
	var tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(self, "modulate", Color(1.5, 0.3, 0.3, 0.0), 0.6)
	tween.tween_property(self, "scale", Vector2(0.5, 0.5), 0.6).set_ease(Tween.EASE_IN)

	# Shake during death
	if body_container:
		var shake_tween = create_tween()
		for i in range(8):
			var offset = Vector2(randf_range(-6, 6), randf_range(-3, 3))
			shake_tween.tween_property(body_container, "position", body_container.position + offset, 0.04)
		shake_tween.tween_property(body_container, "position", body_container.position, 0.04)

	await tween.finished
	queue_free()
