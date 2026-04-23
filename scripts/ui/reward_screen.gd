extends Control
## Post-combat reward screen: gold + card choice.

const CARD_UI_SCENE = preload("res://scenes/ui/card_ui.tscn")

var reward_cards: Array[CardData] = []
var card_chosen: bool = false

@onready var gold_reward_label: Label = $VBoxContainer/GoldRewardLabel
@onready var card_container: HBoxContainer = $VBoxContainer/CardContainer
@onready var skip_button: Button = $VBoxContainer/SkipButton
@onready var proceed_button: Button = $VBoxContainer/ProceedButton


func _ready() -> void:
	skip_button.pressed.connect(_on_skip)
	proceed_button.pressed.connect(_on_proceed)
	proceed_button.visible = false
	_generate_rewards()
	_animate_intro()


func _animate_intro() -> void:
	# Fade in
	modulate.a = 0.0
	var tween = create_tween()
	tween.tween_property(self, "modulate:a", 1.0, 0.4)

	# Gold label counts up
	gold_reward_label.modulate.a = 0.0
	var gold_tween = create_tween()
	gold_tween.tween_property(gold_reward_label, "modulate:a", 1.0, 0.3).set_delay(0.3)
	gold_tween.tween_property(gold_reward_label, "scale", Vector2(1.1, 1.1), 0.1)
	gold_tween.tween_property(gold_reward_label, "scale", Vector2.ONE, 0.1)

	# Cards pop in one by one
	await get_tree().process_frame
	for i in range(card_container.get_child_count()):
		var card_ui = card_container.get_child(i)
		card_ui.modulate.a = 0.0
		card_ui.scale = Vector2(0.5, 0.5)
		var card_tween = create_tween()
		card_tween.set_parallel(true)
		var delay = 0.5 + i * 0.15
		card_tween.tween_property(card_ui, "modulate:a", 1.0, 0.25).set_delay(delay)
		card_tween.tween_property(card_ui, "scale", Vector2(1.05, 1.05), 0.25).set_delay(delay).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
		card_tween.chain().tween_property(card_ui, "scale", Vector2.ONE, 0.1)


func _generate_rewards() -> void:
	var gold_amount = randi_range(10, 20)
	GameManager.add_gold(gold_amount)
	gold_reward_label.text = "+" + str(gold_amount) + " Gold (Total: " + str(GameManager.gold) + ")"

	# Generate 3 card choices - weighted by rarity, filtered to selected class
	var class_map := {
		"ronin": CardData.CardClass.RONIN,
		"yumi": CardData.CardClass.YUMI,
		"banner": CardData.CardClass.BANNER,
	}
	var player_class: int = class_map.get(GameManager.selected_class, CardData.CardClass.ANY)
	var available_cards: Array[CardData] = []
	for card in GameManager.all_cards.values():
		if card.rarity == CardData.CardRarity.STARTER or card.rarity == CardData.CardRarity.SPECIAL:
			continue
		if card.card_class != CardData.CardClass.ANY and card.card_class != player_class:
			continue
		available_cards.append(card)

	available_cards.shuffle()

	# Pick 3 with rarity weighting (commons more likely)
	var chosen: Array[CardData] = []
	for card in available_cards:
		if chosen.size() >= 3:
			break
		# Duplicate check by id
		var already_chosen = false
		for c in chosen:
			if c.id == card.id:
				already_chosen = true
				break
		if already_chosen:
			continue

		var roll = randf()
		match card.rarity:
			CardData.CardRarity.COMMON:
				if roll < 0.75:
					chosen.append(card)
			CardData.CardRarity.UNCOMMON:
				if roll < 0.45:
					chosen.append(card)
			CardData.CardRarity.RARE:
				if roll < 0.15:
					chosen.append(card)

	# Fill remaining slots if needed
	while chosen.size() < 3 and available_cards.size() > chosen.size():
		for card in available_cards:
			if chosen.size() >= 3:
				break
			var already = false
			for c in chosen:
				if c.id == card.id:
					already = true
					break
			if not already:
				chosen.append(card)

	for card_data in chosen:
		var card = card_data.duplicate_card()
		reward_cards.append(card)

		var card_ui: CardUI = CARD_UI_SCENE.instantiate()
		card_container.add_child(card_ui)
		card_ui.setup(card)
		card_ui.card_clicked.connect(_on_reward_card_clicked.bind(card))


func _on_reward_card_clicked(_card_ui: CardUI, card: CardData) -> void:
	if card_chosen:
		return
	card_chosen = true

	GameManager.add_card_to_deck(card)

	# Animate chosen card
	if is_instance_valid(_card_ui):
		var tween = create_tween()
		tween.tween_property(_card_ui, "modulate", Color(1.5, 1.3, 0.8), 0.15)
		tween.tween_property(_card_ui, "modulate", Color.WHITE, 0.2)

	# Grey out other cards
	for child in card_container.get_children():
		if child is CardUI and child != _card_ui:
			var fade = create_tween()
			fade.tween_property(child, "modulate", Color(0.4, 0.4, 0.4), 0.3)
			child.mouse_filter = Control.MOUSE_FILTER_IGNORE

	skip_button.visible = false
	proceed_button.visible = true
	proceed_button.text = "Continue (added " + card.card_name + ")"

	# Animate proceed button
	proceed_button.modulate.a = 0.0
	var btn_tween = create_tween()
	btn_tween.tween_property(proceed_button, "modulate:a", 1.0, 0.3).set_delay(0.3)


func _on_skip() -> void:
	card_chosen = true

	# Fade all cards
	for child in card_container.get_children():
		var fade = create_tween()
		fade.tween_property(child, "modulate", Color(0.3, 0.3, 0.3), 0.3)

	proceed_button.visible = true
	proceed_button.text = "Continue (skipped card)"
	skip_button.visible = false


func _on_proceed() -> void:
	var tween = create_tween()
	tween.tween_property(self, "modulate:a", 0.0, 0.25)
	tween.tween_callback(func():
		get_tree().change_scene_to_file("res://scenes/map/map_screen.tscn")
	)
