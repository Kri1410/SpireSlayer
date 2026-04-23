extends Control
## Main combat scene - manages the battlefield UI, card interactions, and animations.

const CARD_UI_SCENE = preload("res://scenes/ui/card_ui.tscn")
const ENEMY_NODE_SCENE = preload("res://scenes/combat/enemy_node.tscn")

const UNDERCITY_BACKGROUND = preload("res://assets/textures/undercity1.png")
const PLAYER_IDLE_SCALE = Vector2(2.0, 2.0)
const PLAYER_ATTACK_SCALE = Vector2(2.0, 2.0)

var selected_card: CardUI = null
var targeting_mode: bool = false
var enemy_nodes: Array = []
var idle_texture: Texture2D = null
var idle_hframes: int = 1
var attack_texture: Texture2D = null
var attack_hframes: int = 1
var is_processing_turn: bool = false
var idle_anim_timer: float = 0.0
var idle_frame_index: int = 0
var is_attacking: bool = false
var breath_tween: Tween = null

@onready var hand_container: HBoxContainer = $UILayer/HandContainer
@onready var background: ColorRect = $Background
@onready var background_texture: TextureRect = $BackgroundTexture
@onready var energy_label: Label = $UILayer/EnergyOrb/EnergyLabel
@onready var player_hp_bar: ProgressBar = $BattleArea/PlayerBody/PlayerHPContainer/PlayerHPBar
@onready var player_hp_label: Label = $BattleArea/PlayerBody/PlayerHPContainer/PlayerHPLabel
@onready var player_block_label: Label = $BattleArea/PlayerBody/PlayerBlockIcon
@onready var player_status_label: Label = $UILayer/StatusLabel
@onready var player_body: Control = $BattleArea/PlayerBody
@onready var player_sprite: Sprite2D = $BattleArea/PlayerBody/PlayerSprite
@onready var enemy_container: HBoxContainer = $BattleArea/EnemyContainer
@onready var end_turn_button: Button = $UILayer/EndTurnButton
@onready var draw_pile_label: Label = $UILayer/DrawPileLabel
@onready var discard_pile_label: Label = $UILayer/DiscardPileLabel
@onready var target_line: Line2D = $UILayer/TargetLine
@onready var turn_banner: Label = $UILayer/TurnBanner
@onready var damage_number_container: Control = $UILayer/DamageNumberContainer
@onready var top_hp_label: Label = $UILayer/TopBar/HPTopLabel
@onready var top_gold_label: Label = $UILayer/TopBar/GoldIcon
@onready var energy_orb: Control = $UILayer/EnergyOrb
@onready var player_block_bg: Panel = $BattleArea/PlayerBody/PlayerBlockBg
@onready var relics_row: HBoxContainer = $UILayer/TopBar/RelicsRow
@onready var act_label: Label = $UILayer/TopBar/ActLabel
@onready var player_name_label: Label = $UILayer/TopBar/PlayerNameLabel


func _ready() -> void:
	end_turn_button.pressed.connect(_on_end_turn_pressed)
	_load_player_textures()
	_set_player_idle_sprite()
	_configure_background()

	EventBus.combat_started.connect(_on_combat_started)
	EventBus.combat_ended.connect(_on_combat_ended)
	EventBus.hand_updated.connect(_on_hand_updated)
	EventBus.player_hp_changed.connect(_on_player_hp_changed)
	EventBus.player_block_changed.connect(_on_player_block_changed)
	EventBus.player_energy_changed.connect(_on_player_energy_changed)
	EventBus.turn_started.connect(_on_turn_started)
	EventBus.enemy_died.connect(_on_enemy_died)
	EventBus.enemy_damaged.connect(_on_enemy_damaged)
	EventBus.player_damaged.connect(_on_player_damaged)
	EventBus.player_block_gained.connect(_on_player_block_gained)
	CombatManager.combat_state_changed.connect(_update_pile_counts)

	target_line.visible = false
	target_line.z_index = 100

	_update_top_bar()

	_spawn_enemies()
	call_deferred("_start_combat_deferred")


func _configure_background() -> void:
	if not background or not background_texture:
		return

	if GameManager.should_use_undercity_background():
		background_texture.texture = UNDERCITY_BACKGROUND
		background_texture.visible = true
		background.visible = false
	else:
		background_texture.visible = false
		background.visible = true


func _start_combat_deferred() -> void:
	CombatManager.start_combat(enemy_nodes)


func _spawn_enemies() -> void:
	for enemy_data in GameManager.current_encounter_enemies:
		var enemy_node: EnemyNode = ENEMY_NODE_SCENE.instantiate()
		enemy_container.add_child(enemy_node)
		enemy_node.setup(enemy_data)
		enemy_nodes.append(enemy_node)
		enemy_node.gui_input.connect(_on_enemy_clicked.bind(enemy_node))


func _update_top_bar() -> void:
	top_hp_label.text = str(GameManager.current_hp) + "/" + str(GameManager.max_hp)
	top_gold_label.text = str(GameManager.gold)
	if act_label:
		act_label.text = "Act %d  —  Floor %d" % [GameManager.current_act, GameManager.current_floor]
	if player_name_label:
		player_name_label.text = GameManager.player_name
	_populate_relics()


func _populate_relics() -> void:
	if not relics_row:
		return
	for child in relics_row.get_children():
		child.queue_free()
	for relic in GameManager.relics:
		var relic_panel := _make_relic_icon(relic)
		relics_row.add_child(relic_panel)


func _make_relic_icon(relic: RelicData) -> Control:
	var holder := Panel.new()
	holder.custom_minimum_size = Vector2(34, 34)
	holder.tooltip_text = "%s\n%s" % [relic.relic_name, relic.description]

	var sb := StyleBoxFlat.new()
	sb.bg_color = _relic_color_for(relic)
	sb.corner_radius_top_left = 17
	sb.corner_radius_top_right = 17
	sb.corner_radius_bottom_left = 17
	sb.corner_radius_bottom_right = 17
	sb.border_width_left = 2
	sb.border_width_top = 2
	sb.border_width_right = 2
	sb.border_width_bottom = 2
	sb.border_color = Color(0.945, 0.768, 0.058, 0.8)
	sb.shadow_color = Color(0, 0, 0, 0.7)
	sb.shadow_size = 3
	holder.add_theme_stylebox_override("panel", sb)

	var label := Label.new()
	label.text = _relic_glyph_for(relic)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 18)
	label.add_theme_color_override("font_color", Color(1, 0.97, 0.85))
	label.add_theme_constant_override("outline_size", 2)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	label.set_anchors_preset(Control.PRESET_FULL_RECT)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(label)
	return holder


func _relic_color_for(relic: RelicData) -> Color:
	match relic.rarity:
		RelicData.RelicRarity.RARE:
			return Color(0.55, 0.18, 0.62, 0.95)
		RelicData.RelicRarity.UNCOMMON:
			return Color(0.18, 0.42, 0.55, 0.95)
		RelicData.RelicRarity.STARTER:
			return Color(0.55, 0.12, 0.12, 0.95)
		_:
			return Color(0.32, 0.22, 0.18, 0.95)


func _relic_glyph_for(relic: RelicData) -> String:
	match relic.effect_type:
		"heal", "heal_low": return "♥"
		"strength", "strength_low_hp": return "✪"
		"block", "metallicize": return "◆"
		"dexterity": return "✦"
		"energy": return "⚡"
		"draw": return "✎"
		"vulnerable_all": return "☠"
		"double_damage", "block_every_3": return "⚔"
		"dig": return "⛏"
		_: return "●"


# --- CARD INTERACTION ---

func _on_hand_updated() -> void:
	call_deferred("_refresh_hand_deferred")


func _refresh_hand_deferred() -> void:
	for child in hand_container.get_children():
		hand_container.remove_child(child)
		child.queue_free()

	for i in range(CombatManager.hand.size()):
		var card_data = CombatManager.hand[i]
		var card_ui: CardUI = CARD_UI_SCENE.instantiate()
		hand_container.add_child(card_ui)
		card_ui.setup(card_data)
		card_ui.original_index = i
		card_ui.card_clicked.connect(_on_card_clicked)
		card_ui.card_hovered.connect(_on_card_hovered)

	_animate_hand_draw()
	_update_pile_counts()


func _on_card_clicked(card_ui: CardUI) -> void:
	if is_processing_turn:
		return
	if not CombatManager.player_turn:
		return

	if not CombatManager.can_play_card(card_ui.card_data):
		_animate_cant_play(card_ui)
		return

	var card = card_ui.card_data

	if card.target_type == CardData.TargetType.SINGLE_ENEMY:
		if selected_card == card_ui:
			_cancel_targeting()
		else:
			_cancel_targeting()
			selected_card = card_ui
			targeting_mode = true
			card_ui.modulate = Color(1.0, 1.0, 0.6)
			var tween = create_tween()
			tween.tween_property(card_ui, "scale", Vector2(1.15, 1.15), 0.12).set_ease(Tween.EASE_OUT)
	else:
		await _animate_card_play(card_ui, null)
		CombatManager.play_card(card, null)
		_cancel_targeting()
		_check_combat_over()


func _on_enemy_clicked(event: InputEvent, enemy_node: EnemyNode) -> void:
	if not (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT):
		return
	if not targeting_mode or not selected_card:
		return
	if is_processing_turn or not CombatManager.player_turn:
		return
	if enemy_node.is_dead:
		return

	var card = selected_card.card_data
	var card_ui = selected_card
	_cancel_targeting()
	await _animate_card_play(card_ui, enemy_node)
	CombatManager.play_card(card, enemy_node)
	_check_combat_over()
	accept_event()


func _on_card_hovered(_card_ui: CardUI, _hovering: bool) -> void:
	# Card lifts itself on hover - no separate preview needed
	pass


func _cancel_targeting() -> void:
	if selected_card and is_instance_valid(selected_card):
		selected_card.reset_visual_state()
	selected_card = null
	targeting_mode = false
	target_line.visible = false
	for enemy in enemy_nodes:
		if enemy and is_instance_valid(enemy):
			enemy.modulate = Color.WHITE


func _unhandled_input(event: InputEvent) -> void:
	if not CombatManager.player_turn or is_processing_turn:
		return

	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		if targeting_mode:
			_cancel_targeting()
			get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if player_sprite and not is_attacking and idle_texture and (player_sprite.texture != idle_texture or player_sprite.hframes != idle_hframes):
		_set_player_idle_sprite()
	elif player_sprite and not is_attacking and idle_texture:
		idle_anim_timer += delta
		if idle_anim_timer >= 0.18:
			idle_anim_timer = 0.0
			idle_frame_index = (idle_frame_index + 1) % idle_hframes
			player_sprite.frame = idle_frame_index

	if targeting_mode and selected_card and is_instance_valid(selected_card):
		target_line.visible = true
		var start_pos = selected_card.global_position + selected_card.size * selected_card.scale / 2
		var end_pos = get_global_mouse_position()

		# Curved targeting line
		target_line.clear_points()
		var mid = (start_pos + end_pos) / 2.0
		mid.y -= 80
		var steps = 16
		for s in range(steps + 1):
			var t = float(s) / steps
			var p1 = start_pos.lerp(mid, t)
			var p2 = mid.lerp(end_pos, t)
			var point = p1.lerp(p2, t)
			target_line.add_point(point)

		# Highlight enemy under mouse
		for enemy in enemy_nodes:
			if enemy and is_instance_valid(enemy) and not enemy.is_dead:
				var rect = enemy.get_global_rect()
				if rect.has_point(get_global_mouse_position()):
					enemy.modulate = Color(1.4, 0.9, 0.9)
				else:
					enemy.modulate = Color.WHITE
	elif target_line.visible:
		target_line.visible = false


# --- TURN MANAGEMENT ---

func _on_end_turn_pressed() -> void:
	if not CombatManager.player_turn or is_processing_turn:
		return

	_cancel_targeting()
	is_processing_turn = true
	end_turn_button.disabled = true

	await CombatManager.end_player_turn()

	is_processing_turn = false


func _check_combat_over() -> void:
	var all_dead = true
	for enemy in enemy_nodes:
		if enemy and is_instance_valid(enemy) and not enemy.is_dead:
			all_dead = false
			break
	if all_dead:
		CombatManager.end_combat(true)


# --- ANIMATIONS ---

func _animate_card_play(card_ui: CardUI, target_enemy: EnemyNode) -> void:
	if not is_instance_valid(card_ui):
		return

	var tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(card_ui, "scale", Vector2(1.3, 1.3), 0.08).set_ease(Tween.EASE_OUT)
	tween.tween_property(card_ui, "modulate", Color(2, 2, 2, 1), 0.08)
	tween.chain().tween_property(card_ui, "scale", Vector2(0.2, 0.2), 0.12).set_ease(Tween.EASE_IN)
	tween.chain().tween_property(card_ui, "modulate:a", 0.0, 0.12)
	await tween.finished

	if target_enemy and is_instance_valid(target_enemy):
		await _animate_player_attack(target_enemy)
	elif not target_enemy:
		await _animate_player_buff()


func _animate_player_attack(_target_enemy: EnemyNode) -> void:
	if not player_sprite or not attack_texture:
		return

	is_attacking = true
	if breath_tween:
		breath_tween.kill()
		breath_tween = null

	player_sprite.texture = attack_texture
	player_sprite.hframes = attack_hframes
	player_sprite.frame = 0
	player_sprite.scale = PLAYER_ATTACK_SCALE

	var tween = create_tween()
	var per_frame := 0.05
	for i in range(attack_hframes):
		var idx := i
		tween.tween_callback(func(): _set_player_attack_frame(idx))
		tween.tween_interval(per_frame)
	tween.tween_callback(func():
		_set_player_idle_sprite()
		is_attacking = false
		_start_player_breathing()
	)
	await tween.finished

	_screen_shake(6.0, 0.12)


func _set_player_idle_sprite() -> void:
	if not player_sprite or not idle_texture:
		return

	player_sprite.texture = idle_texture
	player_sprite.hframes = idle_hframes
	player_sprite.frame = idle_frame_index % maxi(1, idle_hframes)
	player_sprite.scale = PLAYER_IDLE_SCALE
	player_sprite.centered = true
	player_sprite.offset = Vector2.ZERO


func _set_player_attack_frame(frame_index: int) -> void:
	if not player_sprite or not attack_texture:
		return
	if frame_index < 0 or frame_index >= attack_hframes:
		return

	player_sprite.frame = frame_index


func _load_player_textures() -> void:
	var cls = GameManager.get_class_data()
	idle_texture = _load_texture_safe(cls.idle_sprite)
	idle_hframes = int(cls.idle_frames)
	attack_texture = _load_texture_safe(cls.attack_sprite)
	attack_hframes = int(cls.attack_frames)


func _load_texture_safe(path: String) -> Texture2D:
	# Try ResourceLoader first (works if .import was generated)
	if ResourceLoader.exists(path):
		var t = load(path)
		if t is Texture2D:
			return t
	# Fall back to runtime image load (no .import needed)
	var absolute_path = ProjectSettings.globalize_path(path)
	var image = Image.load_from_file(absolute_path)
	if image and not image.is_empty():
		return ImageTexture.create_from_image(image)
	return null


func _start_player_breathing() -> void:
	if not player_sprite or is_attacking:
		return
	if breath_tween:
		breath_tween.kill()

	breath_tween = create_tween().set_loops()
	breath_tween.tween_property(player_sprite, "position:y", player_sprite.position.y + 4.0, 1.4).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
	breath_tween.tween_property(player_sprite, "position:y", player_sprite.position.y, 1.4).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)


func _animate_player_buff() -> void:
	if not player_body:
		return

	var target = player_sprite if player_sprite else player_body
	var tween = create_tween()
	tween.tween_property(target, "modulate", Color(0.6, 0.8, 1.5), 0.1)
	tween.tween_property(target, "modulate", Color.WHITE, 0.25)
	await tween.finished


func _animate_cant_play(card_ui: CardUI) -> void:
	var energy_tween = create_tween()
	energy_tween.tween_property(energy_orb, "modulate", Color(2.0, 0.3, 0.3), 0.1)
	energy_tween.tween_property(energy_orb, "modulate", Color.WHITE, 0.2)

	if is_instance_valid(card_ui):
		var shake_tween = create_tween()
		shake_tween.tween_property(card_ui, "modulate", Color(1.5, 0.4, 0.4), 0.08)
		shake_tween.tween_property(card_ui, "modulate", Color.WHITE, 0.15)


func _animate_hand_draw() -> void:
	for i in range(hand_container.get_child_count()):
		var card_ui = hand_container.get_child(i)
		if not is_instance_valid(card_ui):
			continue

		card_ui.modulate.a = 0.0
		card_ui.scale = Vector2(0.5, 0.5)

		var tween = create_tween()
		tween.set_parallel(true)
		var delay = i * 0.06
		tween.tween_property(card_ui, "modulate:a", 1.0, 0.15).set_delay(delay)
		tween.tween_property(card_ui, "scale", Vector2(1.05, 1.05), 0.15).set_delay(delay).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
		tween.chain().tween_property(card_ui, "scale", Vector2.ONE, 0.08)


func _on_enemy_damaged(enemy: Node, amount: int) -> void:
	if not is_instance_valid(enemy):
		return

	_spawn_damage_number(enemy.global_position + Vector2(90, 60), amount, Color(1, 0.3, 0.2))

	if enemy.has_node("BodyContainer"):
		var body = enemy.get_node("BodyContainer")
		var original_pos = body.position
		var shake_tween = create_tween()
		shake_tween.tween_property(body, "position:x", original_pos.x + 14, 0.03)
		shake_tween.tween_property(body, "position:x", original_pos.x - 12, 0.03)
		shake_tween.tween_property(body, "position:x", original_pos.x + 8, 0.03)
		shake_tween.tween_property(body, "position:x", original_pos.x - 4, 0.03)
		shake_tween.tween_property(body, "position:x", original_pos.x, 0.04)


func _spawn_damage_number(pos: Vector2, amount: int, color: Color) -> void:
	var label = Label.new()
	label.text = str(amount)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 32)
	label.add_theme_color_override("font_color", color)
	label.global_position = pos + Vector2(randf_range(-12, 12), randf_range(-8, 8))
	label.z_index = 200
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_constant_override("outline_size", 4)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))

	damage_number_container.add_child(label)

	var tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(label, "position:y", label.position.y - 70, 0.8).set_ease(Tween.EASE_OUT)
	tween.tween_property(label, "position:x", label.position.x + randf_range(-15, 15), 0.8)
	tween.tween_property(label, "scale", Vector2(1.4, 1.4), 0.1).set_ease(Tween.EASE_OUT)
	tween.chain().tween_property(label, "scale", Vector2(1.0, 1.0), 0.12)
	tween.tween_property(label, "modulate:a", 0.0, 0.4).set_delay(0.45)
	tween.chain().tween_callback(label.queue_free)


func _screen_shake(intensity: float, duration: float) -> void:
	var battle_area = $BattleArea
	if not battle_area:
		return

	var original_pos = battle_area.position
	var shake_tween = create_tween()
	var steps = int(duration / 0.025)
	for i in range(steps):
		var decay = 1.0 - float(i) / steps
		var offset = Vector2(
			randf_range(-intensity, intensity) * decay,
			randf_range(-intensity, intensity) * decay
		)
		shake_tween.tween_property(battle_area, "position", original_pos + offset, 0.025)
	shake_tween.tween_property(battle_area, "position", original_pos, 0.025)


# --- PLAYER DAMAGE ANIMATION ---

func _animate_player_hit(amount: int) -> void:
	var target = player_sprite if player_sprite else player_body
	if target:
		var tween = create_tween()
		tween.tween_property(target, "modulate", Color(2.5, 0.4, 0.4), 0.08)
		tween.tween_property(target, "modulate", Color.WHITE, 0.25)

	if player_body:
		_spawn_damage_number(player_body.global_position + Vector2(100, 50), amount, Color(1, 0.2, 0.2))
	_screen_shake(5.0, 0.12)


func _on_player_damaged(amount: int) -> void:
	_animate_player_hit(amount)


func _on_player_block_gained(amount: int) -> void:
	_animate_player_block(amount)


func _animate_player_block(amount: int) -> void:
	var target = player_sprite if player_sprite else player_body
	if target:
		var tween = create_tween()
		tween.tween_property(target, "modulate", Color(0.5, 0.7, 2.0), 0.1)
		tween.tween_property(target, "modulate", Color.WHITE, 0.2)

	if player_body:
		_spawn_damage_number(player_body.global_position + Vector2(100, 80), amount, Color(0.3, 0.7, 1.0))


# --- EVENT HANDLERS ---

func _on_combat_started() -> void:
	_on_player_hp_changed(GameManager.current_hp, GameManager.max_hp)
	_on_player_energy_changed(CombatManager.current_energy, CombatManager.max_energy)
	_on_player_block_changed(0)
	_set_player_idle_sprite()
	_start_player_breathing()


func _on_combat_ended(victory: bool) -> void:
	is_processing_turn = true
	if breath_tween:
		breath_tween.kill()
		breath_tween = null

	if victory:
		_show_turn_banner("VICTORY!")
		if player_sprite:
			var tween = create_tween()
			tween.tween_property(player_sprite, "modulate", Color(1.5, 1.3, 0.8), 0.3)
			tween.tween_property(player_sprite, "modulate", Color.WHITE, 0.5)
		await get_tree().create_timer(1.2).timeout
		get_tree().change_scene_to_file("res://scenes/reward/reward_screen.tscn")
	else:
		_show_turn_banner("DEFEAT...")
		if player_sprite:
			var tween = create_tween()
			tween.tween_property(player_sprite, "modulate", Color(0.5, 0.2, 0.2, 0.3), 1.0)
		await get_tree().create_timer(1.8).timeout
		get_tree().change_scene_to_file("res://scenes/game_over/game_over_screen.tscn")


func _on_player_hp_changed(current: int, max_val: int) -> void:
	if player_hp_bar:
		player_hp_bar.max_value = max_val
		player_hp_bar.value = current
	if player_hp_label:
		player_hp_label.text = str(current) + "/" + str(max_val)
	if top_hp_label:
		top_hp_label.text = str(current) + "/" + str(max_val)

	if player_hp_bar and current < max_val:
		var hp_tween = create_tween()
		hp_tween.tween_property(player_hp_bar, "modulate", Color(2, 0.5, 0.5), 0.1)
		hp_tween.tween_property(player_hp_bar, "modulate", Color.WHITE, 0.3)


func _on_player_block_changed(block: int) -> void:
	if not player_block_label:
		return
	if block > 0:
		player_block_label.visible = true
		player_block_label.text = str(block)
		if player_block_bg:
			player_block_bg.visible = true
			player_block_bg.pivot_offset = player_block_bg.size / 2.0
			var bg_tween = create_tween()
			bg_tween.tween_property(player_block_bg, "scale", Vector2(1.25, 1.25), 0.1)
			bg_tween.tween_property(player_block_bg, "scale", Vector2.ONE, 0.15)
		var tween = create_tween()
		tween.tween_property(player_block_label, "scale", Vector2(1.3, 1.3), 0.1)
		tween.tween_property(player_block_label, "scale", Vector2.ONE, 0.15)
	else:
		player_block_label.visible = false
		if player_block_bg:
			player_block_bg.visible = false


func _on_player_energy_changed(current: int, max_val: int) -> void:
	if energy_label:
		energy_label.text = str(current) + "/" + str(max_val)
		if energy_orb:
			var tween = create_tween()
			tween.tween_property(energy_orb, "scale", Vector2(1.1, 1.1), 0.08)
			tween.tween_property(energy_orb, "scale", Vector2.ONE, 0.12)


func _on_turn_started(is_player: bool) -> void:
	if is_player:
		end_turn_button.disabled = false
		is_processing_turn = false
		_show_turn_banner("YOUR TURN")
	else:
		end_turn_button.disabled = true
		_show_turn_banner("ENEMY TURN")


func _on_enemy_died(enemy: Node) -> void:
	enemy_nodes.erase(enemy)


func _show_turn_banner(text: String) -> void:
	if not turn_banner:
		return
	turn_banner.text = text
	turn_banner.visible = true
	turn_banner.modulate = Color(1, 1, 1, 0)
	turn_banner.scale = Vector2(0.7, 0.7)

	if "ENEMY" in text:
		turn_banner.add_theme_color_override("font_color", Color(1, 0.5, 0.3, 1))
	elif "VICTORY" in text:
		turn_banner.add_theme_color_override("font_color", Color(1, 0.9, 0.3, 1))
	elif "DEFEAT" in text:
		turn_banner.add_theme_color_override("font_color", Color(0.8, 0.2, 0.2, 1))
	else:
		turn_banner.add_theme_color_override("font_color", Color(1, 0.85, 0.4, 1))

	var tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(turn_banner, "modulate:a", 1.0, 0.15)
	tween.tween_property(turn_banner, "scale", Vector2(1.1, 1.1), 0.15).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	tween.chain().tween_property(turn_banner, "scale", Vector2.ONE, 0.1)
	tween.chain().tween_interval(0.6)
	tween.chain().tween_property(turn_banner, "modulate:a", 0.0, 0.3)
	tween.chain().tween_callback(func(): turn_banner.visible = false)


func _update_pile_counts() -> void:
	if draw_pile_label:
		draw_pile_label.text = "Draw: " + str(CombatManager.draw_pile.size())
	if discard_pile_label:
		discard_pile_label.text = "Discard: " + str(CombatManager.discard_pile.size())

	if player_status_label:
		var status_text = ""
		for status_name in CombatManager.player_statuses:
			var stacks = CombatManager.player_statuses[status_name]
			if stacks > 0:
				status_text += status_name.capitalize() + " " + str(stacks) + "  "
		player_status_label.text = status_text
