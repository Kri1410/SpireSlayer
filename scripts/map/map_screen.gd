extends Control
## Displays the procedural map and handles node selection.

const CARD_UI_SCENE = preload("res://scenes/ui/card_ui.tscn")

const NODE_SIZE   := 88
const FLOOR_STEP  := 130.0
const MAP_W       := 1100.0
const NODE_SPACE  := 200.0

var map_data: Array = []
var current_floor: int = 0
var deck_overlay_open: bool = false

# PNG icon textures keyed by MapGenerator.NodeType
var _icon_textures: Dictionary = {}

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

	_load_icons()

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
	var target_scroll := scroll_container.get_v_scroll_bar().max_value
	if current_floor > 0:
		var map_height := map_data.size() * FLOOR_STEP
		target_scroll = max(0, map_height - current_floor * FLOOR_STEP - 300)
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


func _load_icons() -> void:
	# Sprite sheet: monster | chest(shop) | ?(event) | elite | boss
	var sheet_path := "res://assets/icons/monster,chest,questionmark,elite,boss.png"
	var sheet_img: Image
	if ResourceLoader.exists(sheet_path):
		var t = load(sheet_path)
		if t is Texture2D:
			sheet_img = t.get_image()
	if not sheet_img:
		sheet_img = Image.load_from_file(ProjectSettings.globalize_path(sheet_path))

	if sheet_img and not sheet_img.is_empty():
		var fw := sheet_img.get_width() / 5
		var fh := sheet_img.get_height()
		var types := [
			MapGenerator.NodeType.MONSTER,
			MapGenerator.NodeType.SHOP,
			MapGenerator.NodeType.EVENT,
			MapGenerator.NodeType.ELITE,
			MapGenerator.NodeType.BOSS,
		]
		for i in range(5):
			var crop := sheet_img.get_region(Rect2i(i * fw, 0, fw, fh))
			_icon_textures[types[i]] = ImageTexture.create_from_image(crop)

	var rest_path := "res://assets/icons/rest.png"
	var rest_img: Image
	if ResourceLoader.exists(rest_path):
		var t = load(rest_path)
		if t is Texture2D:
			rest_img = t.get_image()
	if not rest_img:
		rest_img = Image.load_from_file(ProjectSettings.globalize_path(rest_path))
	if rest_img and not rest_img.is_empty():
		_icon_textures[MapGenerator.NodeType.REST] = ImageTexture.create_from_image(rest_img)


func _draw_map() -> void:
	for child in map_container.get_children():
		child.queue_free()

	var start_y := map_data.size() * FLOOR_STEP + 40.0
	map_container.custom_minimum_size = Vector2(MAP_W + 220, start_y + 80)

	# Connections
	for floor_idx in range(map_data.size() - 1):
		var floor_nodes = map_data[floor_idx]
		var next_floor  = map_data[floor_idx + 1]
		var half := NODE_SIZE / 2.0
		for node in floor_nodes:
			var from_pos := Vector2(
				_node_x(node["index"], floor_nodes.size()) + half,
				start_y - floor_idx * FLOOR_STEP + half
			)
			for conn_idx in node.get("connections_to", []):
				if conn_idx < next_floor.size():
					var to_pos := Vector2(
						_node_x(conn_idx, next_floor.size()) + half,
						start_y - (floor_idx + 1) * FLOOR_STEP + half
					)
					_draw_connection(from_pos, to_pos, _is_connection_on_path(floor_idx, node, conn_idx))

	# Floor number labels (left gutter)
	for floor_idx in range(1, map_data.size()):
		var y := start_y - floor_idx * FLOOR_STEP + NODE_SIZE / 2.0 - 8
		var lbl := Label.new()
		lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if floor_idx == map_data.size() - 1:
			lbl.text = "BOSS"
			lbl.add_theme_font_size_override("font_size", 11)
			lbl.add_theme_color_override("font_color", Color(0.85, 0.25, 0.2, 0.7))
		else:
			lbl.text = str(floor_idx)
			lbl.add_theme_font_size_override("font_size", 11)
			lbl.add_theme_color_override("font_color", Color(0.4, 0.36, 0.3, 0.45))
		lbl.position = Vector2(8, y)
		map_container.add_child(lbl)

	# Nodes
	for floor_idx in range(map_data.size()):
		for node in map_data[floor_idx]:
			var x := _node_x(node["index"], map_data[floor_idx].size())
			var y := start_y - floor_idx * FLOOR_STEP
			_create_map_node(node, Vector2(x, y), floor_idx)



func _node_x(index: int, count: int) -> float:
	var total := count * NODE_SPACE
	var offset := (MAP_W - total) / 2.0 + 40.0
	return offset + index * NODE_SPACE


func _draw_connection(from: Vector2, to: Vector2, on_path: bool) -> void:
	var dir  := to - from
	var len  := dir.length()
	var norm := dir.normalized()
	var perp := Vector2(-norm.y, norm.x)
	var mid  := (from + to) / 2.0 + perp * (to.x - from.x) * 0.07

	var dash := 7.0
	var gap  := 5.0
	var t    := 0.0

	while t < len:
		var t1 := t / len
		var t2 := minf((t + dash) / len, 1.0)
		var p1 := from.lerp(mid, t1).lerp(mid.lerp(to, t1), t1)
		var p2 := from.lerp(mid, t2).lerp(mid.lerp(to, t2), t2)

		var seg := Line2D.new()
		seg.add_point(p1)
		seg.add_point(p2)
		if on_path:
			seg.default_color = Color(0.88, 0.68, 0.22, 0.9)
			seg.width = 3.5
		else:
			seg.default_color = Color(0.38, 0.33, 0.28, 0.28)
			seg.width = 1.5
		map_container.add_child(seg)
		t += dash + gap


func _draw_legend(pos: Vector2) -> void:
	var bg := ColorRect.new()
	bg.position = pos
	bg.size = Vector2(160, 230)
	bg.color = Color(0.06, 0.05, 0.09, 0.82)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	map_container.add_child(bg)

	# thin border
	for side in [Vector2(0,0), Vector2(159,0), Vector2(0,229), Vector2(159,229)]:
		pass  # skip — ColorRect only; a real border would need StyleBox

	var title := Label.new()
	title.text = "Legend"
	title.position = pos + Vector2(12, 8)
	title.add_theme_font_size_override("font_size", 15)
	title.add_theme_color_override("font_color", Color(0.65, 0.6, 0.5, 0.9))
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	map_container.add_child(title)

	var entries := [
		[MapGenerator.NodeType.MONSTER, "Monster"],
		[MapGenerator.NodeType.ELITE,   "Elite"],
		[MapGenerator.NodeType.BOSS,    "Boss"],
		[MapGenerator.NodeType.REST,    "Rest Site"],
		[MapGenerator.NodeType.SHOP,    "Merchant"],
		[MapGenerator.NodeType.EVENT,   "Unknown"],
	]
	for i in range(entries.size()):
		var ntype: MapGenerator.NodeType = entries[i][0]
		var label_text: String = entries[i][1]
		var col := MapGenerator.get_node_type_color(ntype)
		var y_off := 34.0 + i * 32.0

		var icon_tex: Texture2D = _icon_textures.get(ntype, null)
		if icon_tex:
			var tr := TextureRect.new()
			tr.texture = icon_tex
			tr.position = pos + Vector2(10, y_off)
			tr.size = Vector2(24, 24)
			tr.custom_minimum_size = Vector2(24, 24)
			tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
			map_container.add_child(tr)
		else:
			var fallback := Label.new()
			fallback.text = _get_node_letter(ntype)
			fallback.position = pos + Vector2(10, y_off)
			fallback.add_theme_font_size_override("font_size", 16)
			fallback.add_theme_color_override("font_color", col)
			fallback.mouse_filter = Control.MOUSE_FILTER_IGNORE
			map_container.add_child(fallback)

		var name_lbl := Label.new()
		name_lbl.text = label_text
		name_lbl.position = pos + Vector2(40, y_off + 3)
		name_lbl.add_theme_font_size_override("font_size", 13)
		name_lbl.add_theme_color_override("font_color", col.lightened(0.15))
		name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		map_container.add_child(name_lbl)


func _get_node_letter(type: MapGenerator.NodeType) -> String:
	match type:
		MapGenerator.NodeType.MONSTER: return "M"
		MapGenerator.NodeType.ELITE:   return "E"
		MapGenerator.NodeType.REST:    return "R"
		MapGenerator.NodeType.SHOP:    return "$"
		MapGenerator.NodeType.EVENT:   return "?"
		MapGenerator.NodeType.BOSS:    return "B"
		_: return ""


func _is_connection_on_path(floor_idx: int, node: Dictionary, target_idx: int) -> bool:
	if node.get("visited", false):
		if floor_idx + 1 < map_data.size():
			for next_node in map_data[floor_idx + 1]:
				if next_node["index"] == target_idx and next_node.get("visited", false):
					return true
	return false


func _create_map_node(node_data: Dictionary, pos: Vector2, floor_idx: int) -> void:
	var type        := node_data["type"] as MapGenerator.NodeType
	var type_color  := MapGenerator.get_node_type_color(type)
	var is_visited: bool = node_data.get("visited", false)
	var is_select:  bool = _is_node_selectable(floor_idx, node_data)
	var half: float = NODE_SIZE / 2.0

	# --- Circle button ---
	var btn := Button.new()
	btn.position = pos
	btn.size = Vector2(NODE_SIZE, NODE_SIZE)
	btn.text = ""
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if is_select else Control.CURSOR_ARROW

	var style := StyleBoxFlat.new()
	style.set_corner_radius_all(int(half))

	if is_visited:
		style.bg_color = Color(0.12, 0.1, 0.1, 0.5)
		style.border_color = Color(0.3, 0.27, 0.22, 0.4)
		style.set_border_width_all(1)
		btn.disabled = true
	elif is_select:
		style.bg_color = type_color.darkened(0.55)
		style.border_color = type_color
		style.set_border_width_all(3)
		btn.pressed.connect(_on_map_node_pressed.bind(node_data, floor_idx))

		var hover := style.duplicate() as StyleBoxFlat
		hover.bg_color = type_color.darkened(0.3)
		hover.border_color = type_color.lightened(0.25)
		hover.set_border_width_all(4)
		var press := style.duplicate() as StyleBoxFlat
		press.bg_color = type_color.darkened(0.15)
		btn.add_theme_stylebox_override("hover",   hover)
		btn.add_theme_stylebox_override("pressed", press)

		# Subtle pulse
		var tween := create_tween().set_loops()
		tween.tween_property(btn, "modulate:a", 0.6, 0.8)
		tween.tween_property(btn, "modulate:a", 1.0, 0.8)
	else:
		style.bg_color = Color(0.1, 0.09, 0.08, 0.3)
		style.border_color = Color(0.22, 0.2, 0.17, 0.25)
		style.set_border_width_all(1)
		btn.disabled = true

	btn.add_theme_stylebox_override("normal",   style)
	btn.add_theme_stylebox_override("disabled", style)
	btn.clip_contents = true
	map_container.add_child(btn)

	# --- PNG icon inside the circle (child of btn so it's clipped to 62×62) ---
	var icon_tex: Texture2D = _icon_textures.get(type, null)
	if icon_tex:
		var tr := TextureRect.new()
		tr.texture = icon_tex
		tr.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 4)
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if is_visited:
			tr.modulate = Color(0.5, 0.5, 0.5, 0.6)
		elif not is_select:
			tr.modulate = Color(0.85, 0.85, 0.85, 0.75)
		btn.add_child(tr)
	else:
		# Fallback letter
		var lbl := Label.new()
		lbl.text = _get_node_letter(type)
		lbl.position = pos
		lbl.size = Vector2(NODE_SIZE, NODE_SIZE)
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		lbl.add_theme_font_size_override("font_size", 22)
		lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		lbl.add_theme_color_override("font_color",
			Color(0.38, 0.33, 0.28, 0.45) if is_visited else
			(Color.WHITE if is_select else Color(0.42, 0.38, 0.33, 0.38)))
		map_container.add_child(lbl)

	# --- Name label below ---
	if type != MapGenerator.NodeType.START:
		var name_lbl := Label.new()
		name_lbl.text = MapGenerator.get_node_type_name(type)
		name_lbl.position = pos + Vector2(-8, NODE_SIZE + 2)
		name_lbl.size = Vector2(NODE_SIZE + 16, 18)
		name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name_lbl.add_theme_font_size_override("font_size", 10)
		name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		name_lbl.add_theme_color_override("font_color",
			Color(0.32, 0.28, 0.24, 0.38) if is_visited else
			(type_color.lightened(0.1) if is_select else Color(0.32, 0.28, 0.24, 0.28)))
		map_container.add_child(name_lbl)


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
