extends Control
## Random event screen with choices.

var events: Array[Dictionary] = [
	{
		"title": "The Shrine",
		"description": "You discover a small shrine glowing with ethereal light.",
		"choices": [
			{"text": "Pray (Heal 15 HP)", "effect": "heal", "value": 15},
			{"text": "Smash it (Gain 50 Gold)", "effect": "gold", "value": 50},
			{"text": "Leave", "effect": "none", "value": 0}
		]
	},
	{
		"title": "Mysterious Merchant",
		"description": "A cloaked figure offers you a deal...",
		"choices": [
			{"text": "Pay 50 Gold (Remove a card)", "effect": "remove_card", "value": 50},
			{"text": "Trade HP for Gold (Lose 10 HP, Gain 75 Gold)", "effect": "trade_hp_gold", "value": 0},
			{"text": "Decline", "effect": "none", "value": 0}
		]
	},
	{
		"title": "Ancient Writings",
		"description": "Runes carved into the wall pulse with power.",
		"choices": [
			{"text": "Study them (Upgrade a random card)", "effect": "upgrade_random", "value": 0},
			{"text": "Copy them (Gain a random card)", "effect": "gain_random_card", "value": 0},
			{"text": "Ignore", "effect": "none", "value": 0}
		]
	},
	{
		"title": "Trapped Chest",
		"description": "A chest sits in the corner, but you sense danger.",
		"choices": [
			{"text": "Open it (Gain 100 Gold, take 15 damage)", "effect": "chest_gold", "value": 0},
			{"text": "Disarm carefully (Gain 40 Gold)", "effect": "gold", "value": 40},
			{"text": "Walk away", "effect": "none", "value": 0}
		]
	}
]

var current_event: Dictionary

@onready var title_label: Label = $VBoxContainer/TitleLabel
@onready var desc_label: Label = $VBoxContainer/DescLabel
@onready var choice_container: VBoxContainer = $VBoxContainer/ChoiceContainer
@onready var result_label: Label = $VBoxContainer/ResultLabel


func _ready() -> void:
	result_label.visible = false
	current_event = events[randi() % events.size()]
	_display_event()


func _display_event() -> void:
	title_label.text = current_event["title"]
	desc_label.text = current_event["description"]

	for choice in current_event["choices"]:
		var btn = Button.new()
		btn.text = choice["text"]
		btn.custom_minimum_size = Vector2(400, 40)
		btn.pressed.connect(_on_choice_selected.bind(choice))
		choice_container.add_child(btn)


func _on_choice_selected(choice: Dictionary) -> void:
	# Disable all choices
	for child in choice_container.get_children():
		child.disabled = true

	var result_text = ""

	match choice["effect"]:
		"heal":
			GameManager.heal(choice["value"])
			result_text = "Healed " + str(choice["value"]) + " HP."
		"gold":
			GameManager.add_gold(choice["value"])
			result_text = "Gained " + str(choice["value"]) + " Gold."
		"remove_card":
			if GameManager.gold >= choice["value"] and GameManager.deck.size() > 5:
				GameManager.spend_gold(choice["value"])
				var removed = GameManager.deck[randi() % GameManager.deck.size()]
				GameManager.remove_card_from_deck(removed)
				result_text = "Paid " + str(choice["value"]) + " Gold. Removed " + removed.card_name + "."
			else:
				result_text = "Not enough gold or too few cards."
		"trade_hp_gold":
			GameManager.take_damage(10)
			GameManager.add_gold(75)
			result_text = "Lost 10 HP, gained 75 Gold."
		"upgrade_random":
			var upgradeable: Array[CardData] = []
			for card in GameManager.deck:
				if not card.upgraded:
					upgradeable.append(card)
			if upgradeable.size() > 0:
				var card = upgradeable[randi() % upgradeable.size()]
				card.upgraded = true
				result_text = "Upgraded " + card.card_name + "!"
			else:
				result_text = "No cards to upgrade."
		"gain_random_card":
			var cards = GameManager.all_cards.values()
			if cards.size() > 0:
				var card = cards[randi() % cards.size()].duplicate_card()
				GameManager.add_card_to_deck(card)
				result_text = "Gained " + card.card_name + "!"
		"chest_gold":
			GameManager.add_gold(100)
			GameManager.take_damage(15)
			result_text = "Gained 100 Gold but took 15 damage!"
		"none":
			result_text = "You move on."

	result_label.text = result_text
	result_label.visible = true

	await get_tree().create_timer(1.5).timeout
	get_tree().change_scene_to_file("res://scenes/map/map_screen.tscn")
