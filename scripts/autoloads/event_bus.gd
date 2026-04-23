extends Node
## Global event bus for decoupled communication between systems.

@warning_ignore_start("unused_signal")
# Combat signals
signal combat_started
signal combat_ended(victory: bool)
signal turn_started(is_player_turn: bool)
signal turn_ended(is_player_turn: bool)

# Card signals
signal card_played(card_data: CardData)
signal card_drawn(card_data: CardData)
signal card_discarded(card_data: CardData)
signal card_exhausted(card_data: CardData)
signal hand_updated

# Player signals
signal player_hp_changed(current_hp: int, max_hp: int)
signal player_block_changed(block: int)
signal player_damaged(amount: int)
signal player_block_gained(amount: int)
signal player_energy_changed(current: int, max_energy: int)
signal player_gold_changed(gold: int)

# Enemy signals
signal enemy_intent_revealed(enemy: Node, intent: Dictionary)
signal enemy_damaged(enemy: Node, amount: int)
signal enemy_died(enemy: Node)

# Status effect signals
signal status_applied(target: Node, status_name: String, stacks: int)
signal status_removed(target: Node, status_name: String)

# Map signals
signal map_node_selected(node_data: Dictionary)
signal act_completed(act_number: int)

# Reward signals
signal card_reward_chosen(card_data: CardData)
signal relic_obtained(relic_data: Resource)

# UI signals
signal screen_changed(screen_name: String)
@warning_ignore_restore("unused_signal")
