extends Control
## Rest site: heal or upgrade a card.

@onready var rest_button: Button = $VBoxContainer/RestButton
@onready var upgrade_button: Button = $VBoxContainer/UpgradeButton
@onready var info_label: Label = $VBoxContainer/InfoLabel


func _ready() -> void:
	var heal_amount = int(GameManager.max_hp * 0.3)
	rest_button.text = "Rest (Heal " + str(heal_amount) + " HP)"
	rest_button.pressed.connect(_on_rest)
	upgrade_button.pressed.connect(_on_upgrade)
	info_label.text = "HP: " + str(GameManager.current_hp) + "/" + str(GameManager.max_hp)

	# Check if any upgradeable cards exist
	var has_upgradeable = false
	for card in GameManager.deck:
		if not card.upgraded and card.rarity != CardData.CardRarity.SPECIAL:
			has_upgradeable = true
			break
	if not has_upgradeable:
		upgrade_button.disabled = true
		upgrade_button.text = "Smith (no upgradeable cards)"

	# Animate in
	modulate.a = 0.0
	var tween = create_tween()
	tween.tween_property(self, "modulate:a", 1.0, 0.4)

	rest_button.modulate.a = 0.0
	upgrade_button.modulate.a = 0.0
	var btn_tween = create_tween()
	btn_tween.tween_property(rest_button, "modulate:a", 1.0, 0.3).set_delay(0.3)
	btn_tween.tween_property(upgrade_button, "modulate:a", 1.0, 0.3).set_delay(0.1)


func _on_rest() -> void:
	var heal_amount = int(GameManager.max_hp * 0.3)
	GameManager.heal(heal_amount)

	# Healing animation
	var tween = create_tween()
	tween.tween_property(info_label, "modulate", Color(0.3, 1.5, 0.3), 0.2)
	tween.tween_property(info_label, "modulate", Color.WHITE, 0.3)

	info_label.text = "Healed " + str(heal_amount) + " HP! Now at " + str(GameManager.current_hp) + "/" + str(GameManager.max_hp)
	rest_button.disabled = true
	upgrade_button.disabled = true

	var fade = create_tween()
	fade.tween_interval(1.2)
	fade.tween_property(self, "modulate:a", 0.0, 0.3)
	fade.tween_callback(func():
		get_tree().change_scene_to_file("res://scenes/map/map_screen.tscn")
	)


func _on_upgrade() -> void:
	# Find first non-upgraded card and upgrade it
	for card in GameManager.deck:
		if not card.upgraded and card.rarity != CardData.CardRarity.SPECIAL:
			card.upgraded = true

			# Upgrade animation
			var tween = create_tween()
			tween.tween_property(info_label, "modulate", Color(1.5, 1.2, 0.3), 0.2)
			tween.tween_property(info_label, "modulate", Color.WHITE, 0.3)

			info_label.text = "Upgraded " + card.card_name + " to " + card.get_display_name() + "!"
			break

	rest_button.disabled = true
	upgrade_button.disabled = true

	var fade = create_tween()
	fade.tween_interval(1.2)
	fade.tween_property(self, "modulate:a", 0.0, 0.3)
	fade.tween_callback(func():
		get_tree().change_scene_to_file("res://scenes/map/map_screen.tscn")
	)
