extends Control
## Displays the procedural map and handles node selection.
## Styled after STS2: parchment background, icon nodes, dashed lines, legend.

const CARD_UI_SCENE = preload("res://scenes/ui/card_ui.tscn")

var map_data: Array = []
var current_floor: int = 0
var deck_overlay_open: bool = false

@onready var map_container: Control = $ScrollContainer/MapContainer
@onready var scroll_container: ScrollContainer = $ScrollContainer
@onready var floor_label: Label = $UILayer/FloorLabel
@onready var hp_label: Label = $UILayer/HPLabel
@onready var gold_label: Label = $UILayer/GoldLabel
@onready var deck_button: Button = $UILayer/DeckButton
@onready var act_label: Label = $UILayer/ActLabel
@onready var deck_overlay: Control = $UILayer/DeckOverlay
@onready var deck_grid: GridContainer = $UILayer/DeckOverlay/ScrollContainer/DeckGrid
@onready var deck_close_button: Button = $UILayer/DeckOverlay/CloseButton
@onready var deck_count_label: Label = $UILayer/DeckOverlay/DeckCountLabel
@onready var relic_container: HBoxContainer = $UILayer/RelicContainer


func _ready() -> void:
	deck_button.pressed.connect(_on_deck_button_pressed)
	deck_close_button.pressed.connect(_close_deck_overlay)
	deck_overlay.visible = false

	if GameManager.map_data.is_empty():
		GameManager.map_data = MapGenerator.generate_act(GameManager.current_act)

	map_data = GameManager.map_data
	current_floor = GameManager.current_floor

	_update_ui()
	_draw_map()
	_update_relics()

	# Scroll to current floor area
	await get_tree().process_frame
	await get_tree().process_frame
	var target_scroll = scroll_container.get_v_scroll_bar().max_value
	if current_floor > 0:
		var floor_spacing = 120.0
		var map_height = map_data.size() * floor_spacing
		target_scroll = max(0, map_height - current_floor * floor_spacing - 300)
	scroll_container.scroll_vertical = int(target_scroll)

	# Fade in
	modulate.a = 0.0
	var tween = create_tween()
	tween.tween_property(self, "modulate:a", 1.0, 0.3)


func _update_ui() -> void:
	floor_label.text = "Floor: " + str(current_floor)
	hp_label.text = "HP: " + str(GameManager.current_hp) + "/" + str(GameManager.max_hp)
	gold_label.text = "Gold: " + str(GameManager.gold)
	act_label.text = "Act " + str(GameManager.current_act)
	deck_button.text = "Deck (" + str(GameManager.deck.size()) + ")"


func _update_relics() -> void:
	for child in relic_container.get_children():
		child.queue_free()

	for relic in GameManager.relics:
		var relic_label = Label.new()
		relic_label.text = relic.relic_name
		relic_label.add_theme_font_size_override("font_size", 14)
		relic_label.add_theme_color_override("font_color", Color(1, 0.85, 0.3))
		relic_label.tooltip_text = relic.description
		relic_container.add_child(relic_label)


func _draw_map() -> void:
	for child in map_container.get_children():
		child.queue_free()

	var floor_spacing = 120.0
	var node_spacing = 200.0
	var map_width = 1200.0
	var start_y = (map_data.size()) * floor_spacing + 40

	map_container.custom_minimum_size = Vector2(map_width, start_y + 100)

	# Draw connections as dashed lines
	for floor_idx in range(map_data.size() - 1):
		var floor_nodes = map_data[floor_idx]
		var next_floor = map_data[floor_idx + 1]
		for node in floor_nodes:
			var from_pos = Vector2(
				_node_x(node["index"], floor_nodes.size(), map_width, node_spacing) + 25,
				start_y - floor_idx * floor_spacing
			)
			for conn_idx in node.get("connections_to", []):
				if conn_idx < next_floor.size():
					var to_pos = Vector2(
						_node_x(conn_idx, next_floor.size(), map_width, node_spacing) + 25,
						start_y - (floor_idx + 1) * floor_spacing + 50
					)

					var on_path = _is_connection_on_path(floor_idx, node, conn_idx)
					_draw_dashed_line(from_pos, to_pos, on_path)

	# Draw floor labels on the left
	for floor_idx in range(map_data.size()):
		var y = start_y - floor_idx * floor_spacing
		var floor_lbl = Label.new()
		if floor_idx == 0:
			floor_lbl.text = ""
		elif floor_idx == map_data.size() - 1:
			floor_lbl.text = "BOSS"
			floor_lbl.add_theme_color_override("font_color", Color(0.8, 0.25, 0.2, 0.8))
			floor_lbl.add_theme_font_size_override("font_size", 13)
		else:
			floor_lbl.text = str(floor_idx)
		floor_lbl.position = Vector2(-10, y + 12)
		if floor_lbl.text != "BOSS":
			floor_lbl.add_theme_font_size_override("font_size", 11)
			floor_lbl.add_theme_color_override("font_color", Color(0.35, 0.3, 0.25, 0.5))
		floor_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		map_container.add_child(floor_lbl)

	# Draw nodes as icons
	for floor_idx in range(map_data.size()):
		var floor_nodes = map_data[floor_idx]
		for node in floor_nodes:
			var x = _node_x(node["index"], floor_nodes.size(), map_width, node_spacing)
			var y = start_y - floor_idx * floor_spacing
			_create_map_node_icon(node, Vector2(x, y), floor_idx)

	# Draw legend panel
	_draw_legend(Vector2(map_width + 30, start_y - (map_data.size() / 2) * floor_spacing))


func _draw_dashed_line(from: Vector2, to: Vector2, on_path: bool) -> void:
	# Create a dashed line effect using multiple small Line2D segments
	var direction = (to - from)
	var length = direction.length()
	var norm = direction.normalized()
	var dash_length = 8.0
	var gap_length = 6.0
	var traveled = 0.0

	# Create a slight curve through a midpoint
	var mid = (from + to) / 2.0
	var perp = Vector2(-norm.y, norm.x)
	mid += perp * (to.x - from.x) * 0.08  # Slight curve

	while traveled < length:
		var t1 = traveled / length
		var t2 = minf((traveled + dash_length) / length, 1.0)

		# Quadratic bezier interpolation
		var p1_a = from.lerp(mid, t1)
		var p1_b = mid.lerp(to, t1)
		var point1 = p1_a.lerp(p1_b, t1)

		var p2_a = from.lerp(mid, t2)
		var p2_b = mid.lerp(to, t2)
		var point2 = p2_a.lerp(p2_b, t2)

		var seg = Line2D.new()
		seg.add_point(point1)
		seg.add_point(point2)

		if on_path:
			seg.default_color = Color(0.75, 0.6, 0.25, 0.85)
			seg.width = 3.0
		else:
			seg.default_color = Color(0.4, 0.35, 0.3, 0.35)
			seg.width = 1.5
		map_container.add_child(seg)

		traveled += dash_length + gap_length


func _draw_legend(pos: Vector2) -> void:
	var panel = ColorRect.new()
	panel.position = pos
	panel.size = Vector2(170, 240)
	panel.color = Color(0.85, 0.8, 0.7, 0.15)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	map_container.add_child(panel)

	var title = Label.new()
	title.text = "Legend"
	title.position = pos + Vector2(15, 10)
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", Color(0.6, 0.55, 0.45))
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	map_container.add_child(title)

	var entries = [
		[_get_node_icon(MapGenerator.NodeType.EVENT), "Unknown", MapGenerator.get_node_type_color(MapGenerator.NodeType.EVENT)],
		[_get_node_icon(MapGenerator.NodeType.SHOP), "Merchant", MapGenerator.get_node_type_color(MapGenerator.NodeType.SHOP)],
		[_get_node_icon(MapGenerator.NodeType.REST), "Rest", MapGenerator.get_node_type_color(MapGenerator.NodeType.REST)],
		[_get_node_icon(MapGenerator.NodeType.MONSTER), "Enemy", MapGenerator.get_node_type_color(MapGenerator.NodeType.MONSTER)],
		[_get_node_icon(MapGenerator.NodeType.ELITE), "Elite", MapGenerator.get_node_type_color(MapGenerator.NodeType.ELITE)],
		[_get_node_icon(MapGenerator.NodeType.BOSS), "Boss", MapGenerator.get_node_type_color(MapGenerator.NodeType.BOSS)],
	]

	for i in range(entries.size()):
		var entry = entries[i]
		var y_off = 40 + i * 30

		var icon_lbl = Label.new()
		icon_lbl.text = entry[0]
		icon_lbl.position = pos + Vector2(15, y_off)
		icon_lbl.add_theme_font_size_override("font_size", 18)
		icon_lbl.add_theme_color_override("font_color", entry[2])
		icon_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		map_container.add_child(icon_lbl)

		var name_lbl = Label.new()
		name_lbl.text = entry[1]
		name_lbl.position = pos + Vector2(50, y_off + 2)
		name_lbl.add_theme_font_size_override("font_size", 14)
		name_lbl.add_theme_color_override("font_color", Color(0.55, 0.5, 0.4))
		name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		map_container.add_child(name_lbl)


func _node_x(index: int, count: int, total_width: float, spacing: float) -> float:
	var total = count * spacing
	var offset = (total_width - total) / 2.0
	return offset + index * spacing


func _is_connection_on_path(floor_idx: int, node: Dictionary, target_idx: int) -> bool:
	if node.get("visited", false):
		if floor_idx + 1 < map_data.size():
			for next_node in map_data[floor_idx + 1]:
				if next_node["index"] == target_idx and next_node.get("visited", false):
					return true
	return false


func _get_node_icon(type: MapGenerator.NodeType) -> String:
	match type:
		MapGenerator.NodeType.MONSTER: return "M"
		MapGenerator.NodeType.ELITE: return "E"
		MapGenerator.NodeType.REST: return "R"
		MapGenerator.NodeType.SHOP: return "$"
		MapGenerator.NodeType.EVENT: return "?"
		MapGenerator.NodeType.BOSS: return "B"
		MapGenerator.NodeType.START: return "S"
		_: return ""


func _create_map_node_icon(node_data: Dictionary, pos: Vector2, floor_idx: int) -> void:
	var type = node_data["type"] as MapGenerator.NodeType
	var type_color = MapGenerator.get_node_type_color(type)
	var icon_text = _get_node_icon(type)
	var is_visited = node_data.get("visited", false)
	var is_selectable = _is_node_selectable(floor_idx, node_data)

	# Node container button
	var btn = Button.new()
	btn.position = pos
	btn.size = Vector2(50, 50)
	btn.text = ""

	# Create icon-style node
	var style = StyleBoxFlat.new()
	style.set_corner_radius_all(25)  # Circle

	if is_visited:
		style.bg_color = Color(0.2, 0.18, 0.15, 0.5)
		style.border_color = Color(0.35, 0.3, 0.25, 0.5)
		style.set_border_width_all(1)
		btn.disabled = true
	elif is_selectable:
		style.bg_color = type_color.darkened(0.5)
		style.border_color = type_color
		style.set_border_width_all(2)
		btn.pressed.connect(_on_map_node_pressed.bind(node_data, floor_idx))

		# Pulse glow animation
		var tween = create_tween().set_loops()
		tween.tween_property(btn, "modulate:a", 0.65, 0.7)
		tween.tween_property(btn, "modulate:a", 1.0, 0.7)
	else:
		style.bg_color = Color(0.15, 0.13, 0.1, 0.35)
		style.border_color = Color(0.25, 0.22, 0.18, 0.3)
		style.set_border_width_all(1)
		btn.disabled = true

	btn.add_theme_stylebox_override("normal", style)
	btn.add_theme_stylebox_override("disabled", style)

	# Hover style
	if is_selectable:
		var hover_style = style.duplicate()
		hover_style.bg_color = type_color.darkened(0.25)
		hover_style.border_color = type_color.lightened(0.2)
		hover_style.set_border_width_all(3)
		btn.add_theme_stylebox_override("hover", hover_style)

		var pressed_style = style.duplicate()
		pressed_style.bg_color = type_color.darkened(0.15)
		btn.add_theme_stylebox_override("pressed", pressed_style)

	map_container.add_child(btn)

	# Icon label on top
	var icon_label = Label.new()
	icon_label.text = icon_text
	icon_label.position = pos
	icon_label.size = Vector2(50, 50)
	icon_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	icon_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	icon_label.add_theme_font_size_override("font_size", 22)
	icon_label.mouse_filter = Control.MOUSE_FILTER_IGNORE

	if is_visited:
		icon_label.add_theme_color_override("font_color", Color(0.4, 0.35, 0.3, 0.5))
	elif is_selectable:
		icon_label.add_theme_color_override("font_color", Color.WHITE)
	else:
		icon_label.add_theme_color_override("font_color", Color(0.45, 0.4, 0.35, 0.4))

	map_container.add_child(icon_label)

	# Type name below node (small, subtle)
	if type != MapGenerator.NodeType.START:
		var name_label = Label.new()
		name_label.text = MapGenerator.get_node_type_name(type)
		name_label.position = pos + Vector2(-10, 52)
		name_label.size = Vector2(70, 20)
		name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name_label.add_theme_font_size_override("font_size", 10)
		name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE

		if is_visited:
			name_label.add_theme_color_override("font_color", Color(0.35, 0.3, 0.25, 0.4))
		elif is_selectable:
			name_label.add_theme_color_override("font_color", type_color.lightened(0.1))
		else:
			name_label.add_theme_color_override("font_color", Color(0.35, 0.3, 0.25, 0.3))

		map_container.add_child(name_label)


func _is_node_selectable(floor_idx: int, node_data: Dictionary) -> bool:
	if node_data.get("visited", false):
		return false

	if floor_idx != current_floor + 1:
		return false

	if current_floor == 0 and floor_idx == 1:
		if map_data[0].size() > 0:
			var start_node = map_data[0][0]
			return node_data["index"] in start_node.get("connections_to", [])

	for prev_node in map_data[current_floor]:
		if prev_node.get("visited", false):
			if node_data["index"] in prev_node.get("connections_to", []):
				return true

	return false


func _on_map_node_pressed(node_data: Dictionary, floor_idx: int) -> void:
	if current_floor == 0:
		map_data[0][0]["visited"] = true

	node_data["visited"] = true
	GameManager.current_floor = floor_idx

	# Transition animation
	var tween = create_tween()
	tween.tween_property(self, "modulate:a", 0.0, 0.25)
	tween.tween_callback(func():
		var type = node_data["type"] as MapGenerator.NodeType
		match type:
			MapGenerator.NodeType.MONSTER:
				_start_monster_encounter()
			MapGenerator.NodeType.ELITE:
				_start_elite_encounter()
			MapGenerator.NodeType.REST:
				get_tree().change_scene_to_file("res://scenes/rest_site/rest_site.tscn")
			MapGenerator.NodeType.SHOP:
				get_tree().change_scene_to_file("res://scenes/shop/shop_screen.tscn")
			MapGenerator.NodeType.EVENT:
				get_tree().change_scene_to_file("res://scenes/event/event_screen.tscn")
			MapGenerator.NodeType.BOSS:
				_start_boss_encounter()
	)


func _start_monster_encounter() -> void:
	var normal_enemies: Array[EnemyData] = []
	for enemy in GameManager.all_enemies.values():
		if enemy.enemy_type == EnemyData.EnemyType.NORMAL:
			normal_enemies.append(enemy)

	GameManager.current_encounter_enemies.clear()
	if normal_enemies.is_empty():
		push_error("No normal enemies defined!")
		return

	var count = randi_range(1, 2)
	for i in range(count):
		GameManager.current_encounter_enemies.append(
			normal_enemies[randi() % normal_enemies.size()]
		)
	GameManager.register_combat_start()
	get_tree().change_scene_to_file("res://scenes/combat/combat_scene.tscn")


func _start_elite_encounter() -> void:
	var elites: Array[EnemyData] = []
	for enemy in GameManager.all_enemies.values():
		if enemy.enemy_type == EnemyData.EnemyType.ELITE:
			elites.append(enemy)

	GameManager.current_encounter_enemies.clear()
	if elites.is_empty():
		_start_monster_encounter()
		return

	var chosen = elites[randi() % elites.size()]
	GameManager.current_encounter_enemies.append(chosen)

	# Sentries come in pairs
	if chosen.id == "sentry":
		GameManager.current_encounter_enemies.append(chosen)

	GameManager.register_combat_start()
	get_tree().change_scene_to_file("res://scenes/combat/combat_scene.tscn")


func _start_boss_encounter() -> void:
	var bosses: Array[EnemyData] = []
	for enemy in GameManager.all_enemies.values():
		if enemy.enemy_type == EnemyData.EnemyType.BOSS:
			bosses.append(enemy)

	GameManager.current_encounter_enemies.clear()
	if bosses.is_empty():
		_start_monster_encounter()
		return

	GameManager.current_encounter_enemies.append(bosses[randi() % bosses.size()])
	GameManager.register_combat_start()
	get_tree().change_scene_to_file("res://scenes/combat/combat_scene.tscn")


# --- Deck Viewer ---

func _on_deck_button_pressed() -> void:
	if deck_overlay_open:
		_close_deck_overlay()
	else:
		_open_deck_overlay()


func _open_deck_overlay() -> void:
	deck_overlay_open = true
	deck_overlay.visible = true
	deck_overlay.modulate.a = 0.0

	deck_count_label.text = "Deck (" + str(GameManager.deck.size()) + " cards)"

	for child in deck_grid.get_children():
		child.queue_free()

	# Sort deck: attacks, skills, powers
	var sorted_deck = GameManager.deck.duplicate()
	sorted_deck.sort_custom(func(a, b):
		if a.card_type != b.card_type:
			return a.card_type < b.card_type
		return a.energy_cost < b.energy_cost
	)

	for card_data in sorted_deck:
		var card_ui = CARD_UI_SCENE.instantiate()
		deck_grid.add_child(card_ui)
		card_ui.setup(card_data)
		card_ui.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var tween = create_tween()
	tween.tween_property(deck_overlay, "modulate:a", 1.0, 0.2)


func _close_deck_overlay() -> void:
	var tween = create_tween()
	tween.tween_property(deck_overlay, "modulate:a", 0.0, 0.15)
	tween.tween_callback(func():
		deck_overlay.visible = false
		deck_overlay_open = false
	)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		if deck_overlay_open:
			_close_deck_overlay()
			get_viewport().set_input_as_handled()
