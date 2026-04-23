extends Control
## Main menu with character selection — pick one of three samurai classes.

const PANEL_IDS := {
	"RoninPanel": "ronin",
	"YumiPanel": "yumi",
	"BannerPanel": "banner"
}

@onready var title_label: Label = $UILayer/Title
@onready var subtitle_label: Label = $UILayer/Subtitle
@onready var class_row: HBoxContainer = $UILayer/ClassRow
@onready var new_run_button: Button = $UILayer/ButtonContainer/NewRunButton
@onready var quit_button: Button = $UILayer/ButtonContainer/QuitButton
@onready var particle_container: Control = $ParticleContainer

var _ember_timer: float = 0.0
var _title_time: float = 0.0
var _selected_class: String = "ronin"
var _panels: Dictionary = {}
var _idle_images: Dictionary = {}   # class_id -> Image (full sheet)
var _idle_frames: Dictionary = {}   # class_id -> int frame count
var _idle_timer: float = 0.0
var _idle_frame_index: int = 0


func _ready() -> void:
	new_run_button.pressed.connect(_on_new_run)
	quit_button.pressed.connect(_on_quit)

	for panel_name in PANEL_IDS:
		var panel: Panel = class_row.get_node_or_null(panel_name)
		if not panel:
			continue
		var class_id: String = PANEL_IDS[panel_name]
		_panels[class_id] = panel

		# Transparent button overlay — more reliable than gui_input on Panel
		var btn := Button.new()
		btn.flat = true
		btn.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		btn.add_theme_color_override("font_color", Color.TRANSPARENT)
		btn.add_theme_color_override("font_hover_color", Color.TRANSPARENT)
		btn.add_theme_color_override("font_pressed_color", Color.TRANSPARENT)
		btn.pressed.connect(_select_class.bind(class_id))
		panel.add_child(btn)

		_load_panel_sprite(panel, class_id)

	_select_class("ronin")
	_animate_intro()
	_spawn_initial_embers()


func _load_panel_sprite(panel: Panel, class_id: String) -> void:
	var sprite_rect: TextureRect = panel.get_node_or_null("Sprite")
	if not sprite_rect:
		return
	var cls = GameManager.CLASSES.get(class_id, {})
	var path: String = cls.get("idle_sprite", "")
	if path == "":
		return
	var img := _load_image(path)
	if not img or img.is_empty():
		return
	var hframes: int = int(cls.get("idle_frames", 1))
	_idle_images[class_id] = img
	_idle_frames[class_id] = hframes
	# Show frame 0
	_set_panel_frame(sprite_rect, img, hframes, 0)


func _load_image(path: String) -> Image:
	if ResourceLoader.exists(path):
		var t = load(path)
		if t is Texture2D:
			var i = t.get_image()
			if i:
				return i
	var absolute_path := ProjectSettings.globalize_path(path)
	return Image.load_from_file(absolute_path)


func _set_panel_frame(sprite_rect: TextureRect, img: Image, hframes: int, frame: int) -> void:
	var frame_w := img.get_width() / hframes
	var region := Rect2i(frame * frame_w, 0, frame_w, img.get_height())
	var frame_img := img.get_region(region)
	if not frame_img.is_empty():
		sprite_rect.texture = ImageTexture.create_from_image(frame_img)


func _select_class(class_id: String) -> void:
	_selected_class = class_id
	GameManager.selected_class = class_id
	for cid in _panels:
		var panel: Panel = _panels[cid]
		var is_selected: bool = cid == class_id

		# Bright border glow for selected, dim for others
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.07, 0.05, 0.09, 0.92)
		sb.corner_radius_top_left = 14
		sb.corner_radius_top_right = 14
		sb.corner_radius_bottom_right = 14
		sb.corner_radius_bottom_left = 14
		sb.shadow_color = Color(0, 0, 0, 0.6)
		sb.shadow_size = 10
		sb.shadow_offset = Vector2(0, 4)
		if is_selected:
			sb.border_width_left = 3
			sb.border_width_top = 3
			sb.border_width_right = 3
			sb.border_width_bottom = 3
			sb.border_color = Color(0.95, 0.55, 0.15, 1.0)
		else:
			sb.border_width_left = 2
			sb.border_width_top = 2
			sb.border_width_right = 2
			sb.border_width_bottom = 2
			sb.border_color = Color(0.45, 0.18, 0.18, 0.85)
		panel.add_theme_stylebox_override("panel", sb)

		panel.modulate = Color(1.12, 1.05, 0.88) if is_selected else Color(0.8, 0.75, 0.8)
		panel.pivot_offset = Vector2(220, 270)  # half of 440x540 minimum size
		var tween := create_tween()
		tween.tween_property(panel, "scale", Vector2(1.06, 1.06) if is_selected else Vector2.ONE, 0.18).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)


func _process(delta: float) -> void:
	_title_time += delta
	if title_label:
		var glow = 0.85 + sin(_title_time * 1.5) * 0.15
		title_label.modulate = Color(glow, glow * 0.85, glow * 0.8, 1.0)

	_ember_timer += delta
	if _ember_timer > 0.15:
		_ember_timer = 0.0
		_spawn_ember()

	# Animate idle sprites on each panel
	_idle_timer += delta
	if _idle_timer >= 0.18:
		_idle_timer = 0.0
		_idle_frame_index += 1
		for class_id in _panels:
			var img: Image = _idle_images.get(class_id, null)
			var frames: int = int(_idle_frames.get(class_id, 1))
			if not img or frames <= 1:
				continue
			var sprite_rect: TextureRect = _panels[class_id].get_node_or_null("Sprite")
			if not sprite_rect:
				continue
			_set_panel_frame(sprite_rect, img, frames, _idle_frame_index % frames)


func _animate_intro() -> void:
	title_label.modulate.a = 0.0
	title_label.position.y -= 40
	var title_tween = create_tween()
	title_tween.tween_property(title_label, "modulate:a", 1.0, 0.6).set_delay(0.2)
	title_tween.parallel().tween_property(title_label, "position:y", title_label.position.y + 40, 0.6).set_delay(0.2).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)

	subtitle_label.modulate.a = 0.0
	var sub_tween = create_tween()
	sub_tween.tween_property(subtitle_label, "modulate:a", 1.0, 0.5).set_delay(0.6)

	class_row.modulate.a = 0.0
	var row_tween = create_tween()
	row_tween.tween_property(class_row, "modulate:a", 1.0, 0.6).set_delay(0.4)

	new_run_button.modulate.a = 0.0
	quit_button.modulate.a = 0.0
	new_run_button.scale = Vector2(0.85, 0.85)
	quit_button.scale = Vector2(0.85, 0.85)
	new_run_button.pivot_offset = new_run_button.size / 2.0
	quit_button.pivot_offset = quit_button.size / 2.0

	var btn1_tween = create_tween()
	btn1_tween.set_parallel(true)
	btn1_tween.tween_property(new_run_button, "modulate:a", 1.0, 0.4).set_delay(0.9)
	btn1_tween.tween_property(new_run_button, "scale", Vector2.ONE, 0.4).set_delay(0.9).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)

	var btn2_tween = create_tween()
	btn2_tween.set_parallel(true)
	btn2_tween.tween_property(quit_button, "modulate:a", 1.0, 0.4).set_delay(1.0)
	btn2_tween.tween_property(quit_button, "scale", Vector2.ONE, 0.4).set_delay(1.0).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)


func _spawn_initial_embers() -> void:
	for i in range(15):
		_spawn_ember(true)


func _spawn_ember(random_start: bool = false) -> void:
	if not particle_container:
		return

	var ember = ColorRect.new()
	var size_val = randf_range(2.0, 6.0)
	ember.size = Vector2(size_val, size_val)
	ember.color = Color(randf_range(0.8, 1.0), randf_range(0.2, 0.5), randf_range(0.05, 0.15), randf_range(0.4, 0.8))
	ember.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var start_x = randf_range(0, 1920)
	var start_y = 1100.0 if not random_start else randf_range(200, 1080)
	ember.position = Vector2(start_x, start_y)

	particle_container.add_child(ember)

	var duration = randf_range(3.0, 7.0)
	var drift_x = randf_range(-100, 100)
	var end_y = randf_range(-100, 300)

	var tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(ember, "position", Vector2(start_x + drift_x, end_y), duration)
	tween.tween_property(ember, "modulate:a", 0.0, duration * 0.4).set_delay(duration * 0.6)
	tween.tween_property(ember, "scale", Vector2(0.3, 0.3), duration)
	tween.chain().tween_callback(ember.queue_free)


func _on_new_run() -> void:
	var tween = create_tween()
	tween.tween_property(new_run_button, "scale", Vector2(0.9, 0.9), 0.08)
	tween.tween_property(new_run_button, "scale", Vector2(1.05, 1.05), 0.1)
	tween.tween_property(new_run_button, "scale", Vector2.ONE, 0.08)

	var fade = create_tween()
	fade.tween_property(self, "modulate:a", 0.0, 0.4).set_delay(0.2)
	fade.tween_callback(func():
		GameManager.selected_class = _selected_class
		GameManager.start_new_run()
		get_tree().change_scene_to_file("res://scenes/map/map_screen.tscn")
	)


func _on_quit() -> void:
	var tween = create_tween()
	tween.tween_property(self, "modulate:a", 0.0, 0.3)
	tween.tween_callback(func(): get_tree().quit())
