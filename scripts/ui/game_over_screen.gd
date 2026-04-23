extends Control
## Game over screen showing run statistics and score.

@onready var title_label: Label = $UILayer/TitleLabel
@onready var floors_label: Label = $UILayer/StatsContainer/FloorsLabel
@onready var enemies_label: Label = $UILayer/StatsContainer/EnemiesLabel
@onready var gold_label: Label = $UILayer/StatsContainer/GoldLabel
@onready var cards_label: Label = $UILayer/StatsContainer/CardsLabel
@onready var relics_label: Label = $UILayer/StatsContainer/RelicsLabel
@onready var score_label: Label = $UILayer/StatsContainer/ScoreLabel
@onready var return_button: Button = $UILayer/ReturnButton


func _ready() -> void:
	return_button.pressed.connect(_on_return)

	var floors = GameManager.current_floor
	var deck_size = GameManager.deck.size()
	var relic_count = GameManager.relics.size()
	var gold = GameManager.gold

	# Calculate score
	var score = floors * 10 + deck_size * 2 + relic_count * 20 + gold

	# Check if it was a victory (HP > 0 and beat boss)
	var is_victory = GameManager.current_hp > 0 and floors >= MapGenerator.FLOORS_PER_ACT
	if is_victory:
		title_label.text = "Victory!"
		title_label.add_theme_color_override("font_color", Color(1, 0.85, 0.3))
		score += 200  # Victory bonus
	else:
		title_label.text = "You are Slain!"
		title_label.add_theme_color_override("font_color", Color(0.8, 0.2, 0.2))

	floors_label.text = "Floors Climbed: " + str(floors)
	enemies_label.text = "Act: " + str(GameManager.current_act)
	gold_label.text = "Gold: " + str(gold)
	cards_label.text = "Cards in Deck: " + str(deck_size)
	relics_label.text = "Relics: " + str(relic_count)
	score_label.text = "Score: " + str(score)

	# Animate everything in
	modulate.a = 0.0
	var tween = create_tween()
	tween.tween_property(self, "modulate:a", 1.0, 0.5)

	# Stagger stat labels
	await get_tree().process_frame
	var stats = $UILayer/StatsContainer
	for i in range(stats.get_child_count()):
		var child = stats.get_child(i)
		child.modulate.a = 0.0
		var st = create_tween()
		st.tween_property(child, "modulate:a", 1.0, 0.3).set_delay(0.5 + i * 0.15)

	# Title dramatic entrance
	title_label.scale = Vector2(0.5, 0.5)
	title_label.modulate.a = 0.0
	var tt = create_tween().set_parallel(true)
	tt.tween_property(title_label, "scale", Vector2(1.1, 1.1), 0.3).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	tt.tween_property(title_label, "modulate:a", 1.0, 0.3)
	tt.chain().tween_property(title_label, "scale", Vector2.ONE, 0.15)


func _on_return() -> void:
	var tween = create_tween()
	tween.tween_property(self, "modulate:a", 0.0, 0.3)
	tween.tween_callback(func():
		get_tree().change_scene_to_file("res://scenes/main_menu/main_menu.tscn")
	)
