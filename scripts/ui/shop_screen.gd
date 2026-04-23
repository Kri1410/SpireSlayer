extends Control
## Shop screen: buy cards, relics, or remove a card from your deck.

const CARD_UI_SCENE = preload("res://scenes/ui/card_ui.tscn")

var card_remove_cost: int = 75
var card_remove_overlay_open: bool = false

# Shop inventory
var shop_cards: Array[Dictionary] = []  # [{card: CardData, price: int}]
var shop_relics: Array[Dictionary] = []  # [{relic: RelicData, price: int}]

@onready var gold_label: Label = $UILayer/GoldLabel
@onready var card_container: HBoxContainer = $UILayer/CardContainer
@onready var relic_container: HBoxContainer = $UILayer/RelicContainer
@onready var remove_card_button: Button = $UILayer/RemoveCardButton
@onready var leave_button: Button = $UILayer/LeaveButton
@onready var card_remove_overlay: Control = $UILayer/CardRemoveOverlay
@onready var remove_grid: GridContainer = $UILayer/CardRemoveOverlay/ScrollContainer/RemoveGrid
@onready var cancel_remove_button: Button = $UILayer/CardRemoveOverlay/CancelRemoveButton


func _ready() -> void:
	leave_button.pressed.connect(_on_leave)
	remove_card_button.pressed.connect(_on_remove_card_pressed)
	cancel_remove_button.pressed.connect(_close_remove_overlay)

	_generate_shop_inventory()
	_populate_cards()
	_populate_relics()
	_update_gold()
	_update_remove_button()

	# Animate in
	modulate.a = 0.0
	var tween = create_tween()
	tween.tween_property(self, "modulate:a", 1.0, 0.4)

	# Stagger card appearances
	await get_tree().process_frame
	for i in range(card_container.get_child_count()):
		var child = card_container.get_child(i)
		child.modulate.a = 0.0
		child.scale = Vector2(0.6, 0.6)
		var ct = create_tween().set_parallel(true)
		var delay = 0.2 + i * 0.12
		ct.tween_property(child, "modulate:a", 1.0, 0.25).set_delay(delay)
		ct.tween_property(child, "scale", Vector2(1.0, 1.0), 0.25).set_delay(delay).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)

	# Stagger relic appearances
	for i in range(relic_container.get_child_count()):
		var child = relic_container.get_child(i)
		child.modulate.a = 0.0
		var rt = create_tween()
		rt.tween_property(child, "modulate:a", 1.0, 0.2).set_delay(0.5 + i * 0.1)


func _generate_shop_inventory() -> void:
	# Generate 5 cards for sale — filtered to selected class
	var class_map := {
		"ronin": CardData.CardClass.RONIN,
		"yumi": CardData.CardClass.YUMI,
		"banner": CardData.CardClass.BANNER,
	}
	var player_class: int = class_map.get(GameManager.selected_class, CardData.CardClass.ANY)
	var available: Array[CardData] = []
	for card in GameManager.all_cards.values():
		if card.rarity == CardData.CardRarity.STARTER or card.rarity == CardData.CardRarity.SPECIAL:
			continue
		if card.card_class != CardData.CardClass.ANY and card.card_class != player_class:
			continue
		available.append(card)
	available.shuffle()

	var chosen_ids: Array[String] = []
	for card in available:
		if chosen_ids.size() >= 5:
			break
		if card.id in chosen_ids:
			continue
		chosen_ids.append(card.id)

		var price: int
		match card.rarity:
			CardData.CardRarity.COMMON:
				price = randi_range(45, 55)
			CardData.CardRarity.UNCOMMON:
				price = randi_range(68, 82)
			CardData.CardRarity.RARE:
				price = randi_range(145, 165)
			_:
				price = 50
		shop_cards.append({"card": card.duplicate_card(), "price": price})

	# Generate 3 relics for sale
	var available_relics: Array[RelicData] = []
	var owned_ids: Array[String] = []
	for r in GameManager.relics:
		owned_ids.append(r.id)

	for relic in GameManager.all_relics.values():
		if relic.rarity == RelicData.RelicRarity.STARTER:
			continue
		if relic.rarity == RelicData.RelicRarity.BOSS:
			continue
		if relic.id in owned_ids:
			continue
		available_relics.append(relic)
	available_relics.shuffle()

	for i in range(mini(3, available_relics.size())):
		var relic = available_relics[i]
		var price: int
		match relic.rarity:
			RelicData.RelicRarity.COMMON:
				price = randi_range(140, 160)
			RelicData.RelicRarity.UNCOMMON:
				price = randi_range(220, 260)
			RelicData.RelicRarity.RARE:
				price = randi_range(280, 320)
			_:
				price = 200
		shop_relics.append({"relic": relic, "price": price})


func _populate_cards() -> void:
	for child in card_container.get_children():
		child.queue_free()

	for entry in shop_cards:
		var wrapper = VBoxContainer.new()
		wrapper.alignment = BoxContainer.ALIGNMENT_CENTER

		var card_ui: CardUI = CARD_UI_SCENE.instantiate()
		wrapper.add_child(card_ui)
		card_ui.setup(entry["card"])
		card_ui.mouse_filter = Control.MOUSE_FILTER_IGNORE

		var buy_btn = Button.new()
		buy_btn.text = str(entry["price"]) + " Gold"
		buy_btn.add_theme_font_size_override("font_size", 16)
		if GameManager.gold < entry["price"]:
			buy_btn.disabled = true
			buy_btn.add_theme_color_override("font_color", Color(0.5, 0.3, 0.3))
		else:
			buy_btn.add_theme_color_override("font_color", Color(1, 0.85, 0.2))
		buy_btn.pressed.connect(_on_buy_card.bind(entry, wrapper))
		wrapper.add_child(buy_btn)

		card_container.add_child(wrapper)


func _populate_relics() -> void:
	for child in relic_container.get_children():
		child.queue_free()

	for entry in shop_relics:
		var relic: RelicData = entry["relic"]
		var panel = PanelContainer.new()

		var style = StyleBoxFlat.new()
		style.bg_color = Color(0.14, 0.12, 0.2)
		style.border_color = relic.color.darkened(0.3)
		style.set_border_width_all(2)
		style.set_corner_radius_all(6)
		style.set_content_margin_all(12)
		panel.add_theme_stylebox_override("panel", style)

		var vbox = VBoxContainer.new()
		vbox.add_theme_constant_override("separation", 6)

		var name_label = Label.new()
		name_label.text = relic.relic_name
		name_label.add_theme_font_size_override("font_size", 20)
		match relic.rarity:
			RelicData.RelicRarity.COMMON:
				name_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
			RelicData.RelicRarity.UNCOMMON:
				name_label.add_theme_color_override("font_color", Color(0.4, 0.7, 1.0))
			RelicData.RelicRarity.RARE:
				name_label.add_theme_color_override("font_color", Color(1, 0.85, 0.2))
		vbox.add_child(name_label)

		var desc_label = Label.new()
		desc_label.text = relic.description
		desc_label.add_theme_font_size_override("font_size", 14)
		desc_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.65))
		desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		desc_label.custom_minimum_size = Vector2(200, 0)
		vbox.add_child(desc_label)

		var buy_btn = Button.new()
		buy_btn.text = str(entry["price"]) + " Gold"
		buy_btn.add_theme_font_size_override("font_size", 16)
		if GameManager.gold < entry["price"]:
			buy_btn.disabled = true
			buy_btn.add_theme_color_override("font_color", Color(0.5, 0.3, 0.3))
		else:
			buy_btn.add_theme_color_override("font_color", Color(1, 0.85, 0.2))
		buy_btn.pressed.connect(_on_buy_relic.bind(entry, panel))
		vbox.add_child(buy_btn)

		panel.add_child(vbox)
		relic_container.add_child(panel)


func _on_buy_card(entry: Dictionary, wrapper: Control) -> void:
	if not GameManager.spend_gold(entry["price"]):
		return

	GameManager.add_card_to_deck(entry["card"])
	shop_cards.erase(entry)

	# Animate purchase
	var tween = create_tween().set_parallel(true)
	tween.tween_property(wrapper, "modulate", Color(0.3, 1.5, 0.3), 0.15)
	tween.chain().tween_property(wrapper, "modulate", Color(0.3, 0.3, 0.3), 0.3)
	tween.chain().tween_callback(func():
		# Disable the buy button
		for child in wrapper.get_children():
			if child is Button:
				child.disabled = true
				child.text = "SOLD"
	)

	_update_gold()
	_refresh_buy_buttons()


func _on_buy_relic(entry: Dictionary, panel: Control) -> void:
	if not GameManager.spend_gold(entry["price"]):
		return

	var relic = entry["relic"].duplicate()
	GameManager.relics.append(relic)
	EventBus.relic_obtained.emit(relic)
	shop_relics.erase(entry)

	# Animate purchase
	var tween = create_tween()
	tween.tween_property(panel, "modulate", Color(1.5, 1.2, 0.3), 0.15)
	tween.tween_property(panel, "modulate", Color(0.3, 0.3, 0.3), 0.3)
	tween.tween_callback(func():
		for child_node in panel.get_children():
			if child_node is VBoxContainer:
				for sub in child_node.get_children():
					if sub is Button:
						sub.disabled = true
						sub.text = "SOLD"
	)

	_update_gold()
	_refresh_buy_buttons()


func _on_remove_card_pressed() -> void:
	if GameManager.gold < card_remove_cost:
		return
	_open_remove_overlay()


func _open_remove_overlay() -> void:
	card_remove_overlay_open = true
	card_remove_overlay.visible = true
	card_remove_overlay.modulate.a = 0.0

	for child in remove_grid.get_children():
		child.queue_free()

	# Sort deck by type then cost
	var sorted_deck = GameManager.deck.duplicate()
	sorted_deck.sort_custom(func(a, b):
		if a.card_type != b.card_type:
			return a.card_type < b.card_type
		return a.energy_cost < b.energy_cost
	)

	for card_data in sorted_deck:
		var card_ui = CARD_UI_SCENE.instantiate()
		remove_grid.add_child(card_ui)
		card_ui.setup(card_data)
		card_ui.card_clicked.connect(_on_remove_card_chosen.bind(card_data))

	var tween = create_tween()
	tween.tween_property(card_remove_overlay, "modulate:a", 1.0, 0.2)


func _close_remove_overlay() -> void:
	var tween = create_tween()
	tween.tween_property(card_remove_overlay, "modulate:a", 0.0, 0.15)
	tween.tween_callback(func():
		card_remove_overlay.visible = false
		card_remove_overlay_open = false
	)


func _on_remove_card_chosen(_card_ui: CardUI, card_data: CardData) -> void:
	if not GameManager.spend_gold(card_remove_cost):
		return

	GameManager.remove_card_from_deck(card_data)

	# Flash the chosen card red then close
	if is_instance_valid(_card_ui):
		var tween = create_tween()
		tween.tween_property(_card_ui, "modulate", Color(1.5, 0.2, 0.2), 0.15)
		tween.tween_property(_card_ui, "modulate", Color(0.1, 0.1, 0.1, 0.0), 0.3)
		tween.tween_callback(func():
			_close_remove_overlay()
			_update_gold()
			_update_remove_button()
			_refresh_buy_buttons()
		)


func _update_gold() -> void:
	gold_label.text = "Gold: " + str(GameManager.gold)


func _update_remove_button() -> void:
	if GameManager.gold < card_remove_cost or GameManager.deck.size() <= 1:
		remove_card_button.disabled = true
	else:
		remove_card_button.disabled = false
	remove_card_button.text = "Remove a Card (" + str(card_remove_cost) + " Gold)"


func _refresh_buy_buttons() -> void:
	# Refresh card buy buttons
	var card_idx = 0
	for wrapper in card_container.get_children():
		if card_idx >= shop_cards.size():
			break
		var entry = shop_cards[card_idx]
		for child in wrapper.get_children():
			if child is Button and child.text != "SOLD":
				child.disabled = GameManager.gold < entry["price"]
		card_idx += 1

	# Refresh relic buy buttons
	var relic_idx = 0
	for panel in relic_container.get_children():
		if relic_idx >= shop_relics.size():
			break
		var entry = shop_relics[relic_idx]
		for vbox in panel.get_children():
			if vbox is VBoxContainer:
				for child in vbox.get_children():
					if child is Button and child.text != "SOLD":
						child.disabled = GameManager.gold < entry["price"]
		relic_idx += 1

	_update_remove_button()


func _on_leave() -> void:
	var tween = create_tween()
	tween.tween_property(self, "modulate:a", 0.0, 0.25)
	tween.tween_callback(func():
		get_tree().change_scene_to_file("res://scenes/map/map_screen.tscn")
	)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		if card_remove_overlay_open:
			_close_remove_overlay()
			get_viewport().set_input_as_handled()
