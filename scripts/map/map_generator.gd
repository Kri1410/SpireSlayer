class_name MapGenerator
extends RefCounted
## Generates a procedural map for one act.

enum NodeType { MONSTER, ELITE, REST, SHOP, EVENT, BOSS, START }

const FLOORS_PER_ACT = 15
const PATHS_COUNT = 4  # Number of distinct paths through the map
const MIN_NODES_PER_FLOOR = 2
const MAX_NODES_PER_FLOOR = 5


static func generate_act(act_number: int) -> Array:
	## Returns a 2D array: map[floor][node_index] = node_data Dictionary
	var map: Array = []

	# Floor 0: Start node
	map.append([_create_node(NodeType.START, 0, 0)])

	# Generate regular floors (1 to FLOORS_PER_ACT - 1)
	for floor_idx in range(1, FLOORS_PER_ACT):
		var node_count = _get_floor_node_count(floor_idx)
		var floor_nodes: Array = []
		for i in range(node_count):
			var node_type = _pick_node_type(floor_idx, act_number)
			floor_nodes.append(_create_node(node_type, floor_idx, i))
		map.append(floor_nodes)

	# Boss floor
	map.append([_create_node(NodeType.BOSS, FLOORS_PER_ACT, 0)])

	# Generate path-based connections (more organic, branching paths)
	_generate_path_connections(map)

	# Enforce structural rules
	_enforce_rules(map)

	return map


static func _get_floor_node_count(floor_idx: int) -> int:
	# Vary width: narrow at start, wider in mid, narrow before boss
	if floor_idx <= 1:
		return randi_range(2, 3)
	elif floor_idx <= 3:
		return randi_range(3, 4)
	elif floor_idx <= 6:
		return randi_range(3, MAX_NODES_PER_FLOOR)
	elif floor_idx <= 10:
		return randi_range(3, MAX_NODES_PER_FLOOR)
	elif floor_idx <= 13:
		return randi_range(2, 4)
	else:
		return randi_range(2, 3)  # Narrow before boss


static func _create_node(type: NodeType, floor_idx: int, node_idx: int) -> Dictionary:
	return {
		"type": type,
		"floor": floor_idx,
		"index": node_idx,
		"connections_to": [],
		"visited": false
	}


static func _pick_node_type(floor_idx: int, act_number: int) -> NodeType:
	var weights: Dictionary = {}

	if floor_idx <= 2:
		# Early: mostly monsters and events, no elites or rest
		weights = {
			NodeType.MONSTER: 55,
			NodeType.EVENT: 30,
			NodeType.SHOP: 15
		}
	elif floor_idx <= 5:
		# Early-mid: introduce elites and rest
		weights = {
			NodeType.MONSTER: 35,
			NodeType.EVENT: 20,
			NodeType.ELITE: 15,
			NodeType.REST: 18,
			NodeType.SHOP: 12
		}
	elif floor_idx <= 9:
		# Mid: balanced, more elites
		weights = {
			NodeType.MONSTER: 25,
			NodeType.ELITE: 22,
			NodeType.EVENT: 18,
			NodeType.REST: 18,
			NodeType.SHOP: 17
		}
	elif floor_idx <= 12:
		# Late-mid: harder
		weights = {
			NodeType.MONSTER: 20,
			NodeType.ELITE: 28,
			NodeType.REST: 22,
			NodeType.EVENT: 15,
			NodeType.SHOP: 15
		}
	else:
		# Pre-boss: rest and preparation
		weights = {
			NodeType.MONSTER: 15,
			NodeType.ELITE: 20,
			NodeType.REST: 30,
			NodeType.EVENT: 15,
			NodeType.SHOP: 20
		}

	# Scale elite difficulty by act
	if act_number > 1:
		weights[NodeType.ELITE] = weights.get(NodeType.ELITE, 0) + 5 * (act_number - 1)

	return _weighted_random(weights)


static func _weighted_random(weights: Dictionary) -> NodeType:
	var total = 0
	for w in weights.values():
		total += w
	var roll = randi() % total
	var cumulative = 0
	for type in weights:
		cumulative += weights[type]
		if roll < cumulative:
			return type
	return weights.keys()[0]


static func _generate_path_connections(map: Array) -> void:
	## Creates PATHS_COUNT distinct paths from start to boss,
	## then adds cross-connections for route variety.

	var total_floors = map.size()

	# Initialize all connection arrays
	for floor_idx in range(total_floors):
		for node in map[floor_idx]:
			node["connections_to"] = []

	# Step 1: Create distinct paths through the map
	for _p in range(PATHS_COUNT):
		var current_idx = 0  # Start node is always index 0
		for floor_idx in range(total_floors - 1):
			var next_floor = map[floor_idx + 1]
			# Pick a target on the next floor, biased by path number
			var target_idx: int
			if next_floor.size() == 1:
				target_idx = 0
			else:
				# Spread paths across the width
				var base = float(_p) / PATHS_COUNT * next_floor.size()
				target_idx = clampi(int(base) + randi_range(-1, 1), 0, next_floor.size() - 1)

			# Add connection if not already present
			if target_idx not in map[floor_idx][current_idx]["connections_to"]:
				map[floor_idx][current_idx]["connections_to"].append(target_idx)

			current_idx = target_idx

	# Step 2: Ensure every node has at least one incoming connection
	for floor_idx in range(1, total_floors):
		var next_floor = map[floor_idx]
		var connected: Array[bool] = []
		for i in range(next_floor.size()):
			connected.append(false)

		# Check which nodes on this floor have incoming connections
		for prev_node in map[floor_idx - 1]:
			for conn in prev_node["connections_to"]:
				if conn < connected.size():
					connected[conn] = true

		# Connect orphaned nodes
		for i in range(next_floor.size()):
			if not connected[i]:
				# Connect from the nearest node on previous floor
				var prev_floor = map[floor_idx - 1]
				var nearest = clampi(
					int(float(i) / next_floor.size() * prev_floor.size()),
					0, prev_floor.size() - 1
				)
				if i not in prev_floor[nearest]["connections_to"]:
					prev_floor[nearest]["connections_to"].append(i)

	# Step 3: Add cross-connections for branching (25% chance per node)
	for floor_idx in range(total_floors - 1):
		var current_floor = map[floor_idx]
		var next_floor = map[floor_idx + 1]
		for node in current_floor:
			if node["connections_to"].size() < 2 and next_floor.size() > 1 and randf() < 0.3:
				# Add a connection to an adjacent node
				var existing = node["connections_to"][0] if not node["connections_to"].is_empty() else 0
				var offset = 1 if randf() > 0.5 else -1
				var new_target = clampi(existing + offset, 0, next_floor.size() - 1)
				if new_target != existing and new_target not in node["connections_to"]:
					node["connections_to"].append(new_target)

	# Step 4: Ensure every node on non-boss/start floors has at least one outgoing connection
	for floor_idx in range(total_floors - 1):
		for node in map[floor_idx]:
			if node["connections_to"].is_empty():
				var next_floor = map[floor_idx + 1]
				var target = randi() % next_floor.size()
				node["connections_to"].append(target)

	# Sort connections for consistency
	for floor_idx in range(total_floors):
		for node in map[floor_idx]:
			node["connections_to"].sort()


static func _enforce_rules(map: Array) -> void:
	# Floor 1 is always monsters
	if map.size() > 1:
		for node in map[1]:
			node["type"] = NodeType.MONSTER

	# No elites in first 3 floors
	for floor_idx in range(1, mini(4, map.size())):
		for node in map[floor_idx]:
			if node["type"] == NodeType.ELITE:
				node["type"] = NodeType.MONSTER

	# No rest before floor 4
	for floor_idx in range(1, mini(4, map.size())):
		for node in map[floor_idx]:
			if node["type"] == NodeType.REST:
				if randf() < 0.5:
					node["type"] = NodeType.EVENT
				else:
					node["type"] = NodeType.MONSTER

	# Floor before boss should have at least one rest
	var pre_boss = map.size() - 2
	if pre_boss > 0:
		var has_rest = false
		for node in map[pre_boss]:
			if node["type"] == NodeType.REST:
				has_rest = true
				break
		if not has_rest and map[pre_boss].size() > 0:
			map[pre_boss][0]["type"] = NodeType.REST

	# Guarantee at least one shop between floors 4-8
	var has_shop_early = false
	for floor_idx in range(4, mini(9, map.size())):
		for node in map[floor_idx]:
			if node["type"] == NodeType.SHOP:
				has_shop_early = true
				break
		if has_shop_early:
			break
	if not has_shop_early and map.size() > 5:
		# Put a shop on floor 5 or 6
		var target_floor = randi_range(5, mini(6, map.size() - 2))
		if map[target_floor].size() > 0:
			map[target_floor][map[target_floor].size() - 1]["type"] = NodeType.SHOP

	# No consecutive rest sites on the same path (too easy)
	for floor_idx in range(1, map.size() - 1):
		for node in map[floor_idx]:
			if node["type"] == NodeType.REST:
				for conn_idx in node.get("connections_to", []):
					if floor_idx + 1 < map.size() and conn_idx < map[floor_idx + 1].size():
						var next_node = map[floor_idx + 1][conn_idx]
						if next_node["type"] == NodeType.REST:
							next_node["type"] = NodeType.EVENT

	# Guarantee at least 2 elites in the act (floors 4+)
	var elite_count = 0
	for floor_idx in range(map.size()):
		for node in map[floor_idx]:
			if node["type"] == NodeType.ELITE:
				elite_count += 1
	var attempts = 0
	while elite_count < 2 and attempts < 10:
		var target_floor = randi_range(5, mini(12, map.size() - 2))
		if target_floor < map.size() and map[target_floor].size() > 0:
			var target_node = map[target_floor][randi() % map[target_floor].size()]
			if target_node["type"] == NodeType.MONSTER:
				target_node["type"] = NodeType.ELITE
				elite_count += 1
		attempts += 1


static func get_node_type_name(type: NodeType) -> String:
	match type:
		NodeType.MONSTER: return "Monster"
		NodeType.ELITE: return "Elite"
		NodeType.REST: return "Rest"
		NodeType.SHOP: return "Shop"
		NodeType.EVENT: return "Event"
		NodeType.BOSS: return "Boss"
		NodeType.START: return "Start"
	return "Unknown"


static func get_node_type_color(type: NodeType) -> Color:
	match type:
		NodeType.MONSTER: return Color(0.8, 0.3, 0.3)
		NodeType.ELITE: return Color(1.0, 0.8, 0.2)
		NodeType.REST: return Color(0.3, 0.8, 0.3)
		NodeType.SHOP: return Color(0.3, 0.6, 0.9)
		NodeType.EVENT: return Color(0.7, 0.5, 0.8)
		NodeType.BOSS: return Color(1.0, 0.2, 0.2)
		NodeType.START: return Color(0.5, 0.5, 0.5)
	return Color.WHITE
