class_name CardUI
extends Control
## Visual representation of a card in hand.

signal card_clicked(card_ui: CardUI)
signal card_hovered(card_ui: CardUI, hovering: bool)

const CARD_SIZE := Vector2(170, 240)

# Type banner colors (StS2 spec)
const COLOR_ATTACK := Color(0.482, 0.094, 0.094, 0.97)   # dark red
const COLOR_SKILL := Color(0.137, 0.298, 0.396, 0.97)    # dark teal/steel blue
const COLOR_POWER := Color(0.310, 0.122, 0.471, 0.97)    # dark purple
const COLOR_STATUS := Color(0.25, 0.25, 0.30, 0.97)
const COLOR_CURSE := Color(0.25, 0.05, 0.30, 0.97)

# Frame border colors per type
const FRAME_ATTACK := Color(0.482, 0.125, 0.125, 1)
const FRAME_SKILL := Color(0.18, 0.42, 0.55, 1)
const FRAME_POWER := Color(0.42, 0.18, 0.62, 1)

# Inline keyword colors
const KEY_BLOCK := "#5dade2"
const KEY_VULNERABLE := "#e67e22"
const KEY_WEAK := "#f39c12"
const KEY_EXHAUST := "#e74c3c"
const KEY_ETHEREAL := "#a569bd"
const KEY_STRENGTH := "#e74c3c"
const KEY_DAMAGE := "#e74c3c"

var card_data: CardData
var is_hovering: bool = false
var original_index: int = 0
var rest_position: Vector2 = Vector2.ZERO
var hover_tween: Tween = null
var _glow_tween: Tween = null

@onready var upgrade_glow: Panel = $UpgradeGlow
@onready var outer_frame: Panel = $OuterFrame
@onready var type_banner: Panel = $TypeBanner
@onready var type_label: Label = $TypeBanner/TypeLabel
@onready var card_name_label: Label = $CardNameLabel
@onready var cost_label: Label = $CostMedallion/CostLabel
@onready var cost_medallion: Panel = $CostMedallion
@onready var description_label: RichTextLabel = $DescPanel/DescriptionLabel
@onready var replay_label: Label = $ReplayLabel
@onready var art_texture: TextureRect = $ArtPanel/ArtTexture


func _ready() -> void:
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)
	gui_input.connect(_on_gui_input)
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size = CARD_SIZE
	size = CARD_SIZE
	pivot_offset = CARD_SIZE / 2.0
	call_deferred("_cache_rest_position")
	z_index = original_index


func setup(data: CardData) -> void:
	card_data = data
	call_deferred("_cache_rest_position")
	if is_node_ready():
		_update_visuals()
	else:
		ready.connect(_update_visuals, CONNECT_ONE_SHOT)


func _cache_rest_position() -> void:
	if is_hovering:
		return
	rest_position = position


func _update_visuals() -> void:
	if not card_data:
		return

	_apply_type_colors()
	_apply_card_name()
	_apply_cost()
	_apply_description()
	_apply_art_tint()
	_apply_replay()
	_apply_upgrade_glow()
	_apply_playable_dim()


func _apply_type_colors() -> void:
	var banner_color: Color
	var frame_color: Color
	var type_text: String

	match card_data.card_type:
		CardData.CardType.ATTACK:
			banner_color = COLOR_ATTACK
			frame_color = FRAME_ATTACK
			type_text = "Attack"
		CardData.CardType.SKILL:
			banner_color = COLOR_SKILL
			frame_color = FRAME_SKILL
			type_text = "Skill"
		CardData.CardType.POWER:
			banner_color = COLOR_POWER
			frame_color = FRAME_POWER
			type_text = "Power"
		CardData.CardType.STATUS:
			banner_color = COLOR_STATUS
			frame_color = Color(0.4, 0.4, 0.45, 1)
			type_text = "Status"
		CardData.CardType.CURSE:
			banner_color = COLOR_CURSE
			frame_color = Color(0.45, 0.15, 0.5, 1)
			type_text = "Curse"

	type_label.text = type_text

	var banner_style: StyleBoxFlat = type_banner.get_theme_stylebox("panel")
	if banner_style:
		var banner_copy: StyleBoxFlat = banner_style.duplicate()
		banner_copy.bg_color = banner_color
		type_banner.add_theme_stylebox_override("panel", banner_copy)

	var frame_style: StyleBoxFlat = outer_frame.get_theme_stylebox("panel")
	if frame_style:
		var frame_copy: StyleBoxFlat = frame_style.duplicate()
		frame_copy.border_color = frame_color
		outer_frame.add_theme_stylebox_override("panel", frame_copy)


func _apply_card_name() -> void:
	card_name_label.text = card_data.get_display_name()

	# Upgraded -> bright green/lime
	if card_data.upgraded:
		card_name_label.add_theme_color_override("font_color", Color(0.55, 1.0, 0.45, 1))
	else:
		match card_data.rarity:
			CardData.CardRarity.RARE:
				card_name_label.add_theme_color_override("font_color", Color(1, 0.85, 0.3, 1))
			CardData.CardRarity.UNCOMMON:
				card_name_label.add_theme_color_override("font_color", Color(0.55, 0.85, 1.0, 1))
			_:
				card_name_label.add_theme_color_override("font_color", Color(1, 0.97, 0.9, 1))


func _apply_cost() -> void:
	if card_data.card_type == CardData.CardType.STATUS or card_data.card_type == CardData.CardType.CURSE:
		cost_label.text = "-"
	else:
		cost_label.text = str(card_data.get_effective_cost())


func _apply_description() -> void:
	var desc := card_data.description
	desc = desc.replace("{D}", "[color=" + KEY_DAMAGE + "]" + str(card_data.get_effective_damage()) + "[/color]")
	desc = desc.replace("{B}", "[color=" + KEY_BLOCK + "]" + str(card_data.get_effective_block()) + "[/color]")
	desc = desc.replace("{M}", "[b]" + str(card_data.get_effective_magic()) + "[/b]")

	# Color-code keywords
	desc = _colorize_keyword(desc, "Block", KEY_BLOCK)
	desc = _colorize_keyword(desc, "Vulnerable", KEY_VULNERABLE)
	desc = _colorize_keyword(desc, "Weak", KEY_WEAK)
	desc = _colorize_keyword(desc, "Strength", KEY_STRENGTH)
	desc = _colorize_keyword(desc, "Exhaust", KEY_EXHAUST)
	desc = _colorize_keyword(desc, "Ethereal", KEY_ETHEREAL)

	if card_data.exhaust and "Exhaust" not in card_data.description:
		desc += "\n[color=" + KEY_EXHAUST + "][b]Exhaust.[/b][/color]"
	if card_data.ethereal and "Ethereal" not in card_data.description:
		desc += "\n[color=" + KEY_ETHEREAL + "][b]Ethereal.[/b][/color]"

	description_label.text = "[center]" + desc + "[/center]"
	description_label.add_theme_font_size_override("normal_font_size", 11)


func _colorize_keyword(text: String, keyword: String, hex_color: String) -> String:
	# Avoid double-coloring inside an existing tag
	var tag_open := "[color=" + hex_color + "][b]"
	var tag_close := "[/b][/color]"
	return text.replace(keyword, tag_open + keyword + tag_close)


func _apply_art_tint() -> void:
	# Tint the placeholder gradient art toward the type color
	if not art_texture:
		return
	match card_data.card_type:
		CardData.CardType.ATTACK:
			art_texture.modulate = Color(1.0, 0.55, 0.5, 1)
		CardData.CardType.SKILL:
			art_texture.modulate = Color(0.55, 0.85, 1.05, 1)
		CardData.CardType.POWER:
			art_texture.modulate = Color(0.85, 0.55, 1.1, 1)
		_:
			art_texture.modulate = Color(0.7, 0.7, 0.75, 1)


func _apply_replay() -> void:
	var replay = card_data.get_effective_replay()
	if replay > 0:
		replay_label.visible = true
		replay_label.text = "x" + str(replay + 1)
	else:
		replay_label.visible = false


func _apply_upgrade_glow() -> void:
	if not upgrade_glow:
		return
	if card_data.upgraded:
		upgrade_glow.visible = true
		if _glow_tween:
			_glow_tween.kill()
		_glow_tween = create_tween().set_loops()
		_glow_tween.tween_property(upgrade_glow, "modulate:a", 0.55, 0.7).set_trans(Tween.TRANS_SINE)
		_glow_tween.tween_property(upgrade_glow, "modulate:a", 1.0, 0.7).set_trans(Tween.TRANS_SINE)
	else:
		upgrade_glow.visible = false
		if _glow_tween:
			_glow_tween.kill()
			_glow_tween = null


func _apply_playable_dim() -> void:
	if CombatManager.in_combat and not CombatManager.can_play_card(card_data):
		modulate = Color(0.65, 0.6, 0.65, 1.0)
	else:
		modulate = Color.WHITE


func _on_mouse_entered() -> void:
	if is_hovering:
		return

	is_hovering = true
	pivot_offset = Vector2(size.x / 2.0, size.y)
	if hover_tween:
		hover_tween.kill()
	hover_tween = create_tween()
	hover_tween.set_parallel(true)
	hover_tween.tween_property(self, "scale", Vector2(1.22, 1.22), 0.22).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_SINE)
	hover_tween.tween_property(self, "position", rest_position + Vector2(0, -70), 0.22).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_SINE)
	z_index = 100
	card_hovered.emit(self, true)


func _on_mouse_exited() -> void:
	if not is_hovering:
		return

	is_hovering = false
	if hover_tween:
		hover_tween.kill()
	hover_tween = create_tween()
	hover_tween.set_parallel(true)
	hover_tween.tween_property(self, "scale", Vector2.ONE, 0.2).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_SINE)
	hover_tween.tween_property(self, "position", rest_position, 0.2).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_SINE)
	pivot_offset = Vector2(size.x / 2.0, size.y / 2.0)
	z_index = original_index
	hover_tween.finished.connect(_cache_rest_position, CONNECT_ONE_SHOT)
	card_hovered.emit(self, false)


func _on_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			card_clicked.emit(self)


func reset_visual_state() -> void:
	if hover_tween:
		hover_tween.kill()

	if is_hovering:
		pivot_offset = Vector2(size.x / 2.0, size.y)
		scale = Vector2(1.4, 1.4)
		position = rest_position + Vector2(0, -100)
		z_index = 100
	else:
		pivot_offset = Vector2(size.x / 2.0, size.y / 2.0)
		scale = Vector2.ONE
		position = rest_position
		z_index = original_index
	_apply_playable_dim()
