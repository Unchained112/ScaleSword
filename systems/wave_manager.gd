class_name WaveManager
extends Node

signal round_started(round_index: int)
signal enemy_spawned(enemy: EnemyBase)
signal enemy_killed(enemy: EnemyBase, hit_data: HitData)
signal remaining_changed(remaining: int)
signal boss_spawned(boss: EnemyBase)
signal wave_cleared(round_index: int, was_boss_round: bool)
signal deferred_enemy_spawned(enemy: EnemyBase, spawn_context: StringName, source_instance_id: int)
signal deferred_enemy_spawn_cancelled(spawn_context: StringName, source_instance_id: int)

const ENEMY_SCENES := {
	&"chaser": preload("res://actors/enemies/chaser.tscn"),
	&"shooter": preload("res://actors/enemies/shooter.tscn"),
	&"charger": preload("res://actors/enemies/charger.tscn"),
	&"splitter": preload("res://actors/enemies/splitter.tscn"),
	&"heavy": preload("res://actors/enemies/heavy_charger.tscn"),
	&"skirmisher": preload("res://actors/enemies/skirmisher.tscn"),
	&"boss_void": preload("res://actors/bosses/void_charger.tscn"),
	&"boss_core": preload("res://actors/bosses/proliferation_core.tscn"),
	&"boss_rift": preload("res://actors/bosses/rift_weaver.tscn"),
}
const THREAT := {
	&"chaser": 1,
	&"shooter": 2,
	&"charger": 3,
	&"splitter": 3,
	&"skirmisher": 4,
	&"heavy": 5,
}
var _definitions: Array[WaveDefinition] = []
var _container: Node2D
var _player: PlayerController
var _arena_bounds: ArenaBounds
var _spawn_queue: Array[StringName] = []
var _round_index := 0
var _current_definition: WaveDefinition
var _active := false
var _spawning := false
var _batch_delay := 0.0
var _clear_emitted := false
var _rng := RandomNumberGenerator.new()
var _connected_enemy_ids: Dictionary = {}
var _generation := 0
var _pending_deferred_spawns := 0
var _next_spawn_request_id := 1
var _deferred_spawn_requests: Dictionary = {}


func _ready() -> void:
	add_to_group("wave_manager")
	_build_definitions()
	_rng.randomize()


func setup(container: Node2D, player: PlayerController, arena_bounds: ArenaBounds = null) -> void:
	_container = container
	_player = player
	_arena_bounds = arena_bounds
	if _arena_bounds == null:
		_arena_bounds = get_tree().get_first_node_in_group("arena_bounds") as ArenaBounds
	if not _container.child_entered_tree.is_connected(_on_container_child_entered):
		_container.child_entered_tree.connect(_on_container_child_entered)


func start_round(round_index: int) -> void:
	if round_index < 1 or round_index > _definitions.size():
		return
	stop()
	_round_index = round_index
	_current_definition = _definitions[round_index - 1]
	_active = true
	_clear_emitted = false
	round_started.emit(round_index)
	if _current_definition.is_boss_round():
		_spawn_boss(_current_definition.boss_id)
	else:
		_build_spawn_queue(_current_definition)
		_spawn_next_batch()
	_emit_remaining()


func stop() -> void:
	_generation += 1
	_active = false
	_spawning = false
	_spawn_queue.clear()
	for request_id in _deferred_spawn_requests.keys():
		_cancel_deferred_spawn(int(request_id))
	_pending_deferred_spawns = 0
	_batch_delay = 0.0
	_clear_emitted = false


func clear_all() -> void:
	stop()
	if not is_instance_valid(_container):
		return
	for child in _container.get_children():
		child.queue_free()
	for bullet in get_tree().get_nodes_in_group("enemy_bullet"):
		bullet.queue_free()
	_connected_enemy_ids.clear()
	remaining_changed.emit(0)


func get_round_index() -> int:
	return _round_index


func get_round_count() -> int:
	return _definitions.size()


func is_active() -> bool:
	return _active


func get_remaining() -> int:
	return _spawn_queue.size() + _get_alive_enemies().size() + _pending_deferred_spawns


func get_pending_deferred_spawn_count() -> int:
	return _pending_deferred_spawns


func request_deferred_enemy_spawn(
	scene: PackedScene,
	world_position: Vector2,
	spawn_context: StringName = &"split",
	source: Node = null
) -> bool:
	if scene == null or not _active or not is_instance_valid(_container):
		return false
	var request_id := _next_spawn_request_id
	_next_spawn_request_id += 1
	var source_id := source.get_instance_id() if is_instance_valid(source) else 0
	_deferred_spawn_requests[request_id] = {
		"scene": scene,
		"world_position": world_position,
		"spawn_context": spawn_context,
		"generation": _generation,
		"source_id": source_id,
		"source_ref": weakref(source) if is_instance_valid(source) else null,
	}
	_pending_deferred_spawns += 1
	_emit_remaining()
	_complete_deferred_enemy_spawn.call_deferred(request_id)
	return true


func cancel_deferred_spawns_for_source(source: Node) -> void:
	if not is_instance_valid(source):
		return
	var source_id := source.get_instance_id()
	for request_id in _deferred_spawn_requests.keys():
		var request: Dictionary = _deferred_spawn_requests[request_id]
		if int(request.get("source_id", 0)) == source_id:
			_cancel_deferred_spawn(int(request_id))


func get_definition(round_index: int) -> WaveDefinition:
	if round_index < 1 or round_index > _definitions.size():
		return null
	return _definitions[round_index - 1]


func is_current_boss_round() -> bool:
	return _current_definition != null and _current_definition.is_boss_round()


func _process(delta: float) -> void:
	if not _active or _clear_emitted or _current_definition == null:
		return
	var alive := _get_alive_enemies().size()
	if not _spawn_queue.is_empty():
		if not _spawning and alive <= 2:
			_batch_delay -= delta
			if _batch_delay <= 0.0:
				_spawn_next_batch()
	else:
		var clear_count := (
			_get_present_enemy_count() + _pending_deferred_spawns
			if _current_definition.is_boss_round()
			else alive + _pending_deferred_spawns
		)
		if not _spawning and clear_count == 0:
			_clear_emitted = true
			_active = false
			remaining_changed.emit(0)
			wave_cleared.emit(_round_index, _current_definition.is_boss_round())


func _build_spawn_queue(definition: WaveDefinition) -> void:
	_spawn_queue.clear()
	var remaining_budget := definition.threat_budget
	var safety := 0
	while remaining_budget > 0 and safety < 100:
		safety += 1
		var fitting: Array[StringName] = []
		for enemy_id in definition.enemy_ids:
			if int(THREAT[enemy_id]) <= remaining_budget:
				fitting.append(enemy_id)
		if fitting.is_empty():
			break
		var chosen := fitting[_rng.randi_range(0, fitting.size() - 1)]
		_spawn_queue.append(chosen)
		remaining_budget -= int(THREAT[chosen])
	_spawn_queue.shuffle()


func _spawn_next_batch() -> void:
	if _spawn_queue.is_empty() or _spawning:
		return
	_spawning = true
	var generation := _generation
	var open_slots := maxi(_current_definition.max_alive - _get_alive_enemies().size(), 0)
	var count := mini(_current_definition.batch_size, mini(open_slots, _spawn_queue.size()))
	for index in count:
		if generation != _generation or not _active or _spawn_queue.is_empty():
			break
		var enemy_id: StringName = _spawn_queue.pop_front()
		_spawn_enemy(enemy_id)
		if index < count - 1:
			await get_tree().create_timer(0.22).timeout
	if generation != _generation:
		return
	_spawning = false
	_batch_delay = 1.0
	_emit_remaining()


func _spawn_enemy(enemy_id: StringName) -> void:
	if not _active or not ENEMY_SCENES.has(enemy_id):
		return
	var enemy := (ENEMY_SCENES[enemy_id] as PackedScene).instantiate() as EnemyBase
	_container.add_child(enemy)
	enemy.global_position = _choose_spawn_point()
	_connect_enemy(enemy)
	enemy.begin_spawn_intro()
	enemy_spawned.emit(enemy)
	var audio := get_tree().get_first_node_in_group("audio_manager")
	if audio != null and audio.has_method("play_game_sfx"):
		audio.play_game_sfx(&"enemy_move", enemy.global_position, randf_range(0.92, 1.08))
	_emit_remaining()


func _spawn_boss(boss_id: StringName) -> void:
	if not ENEMY_SCENES.has(boss_id):
		return
	var boss := (ENEMY_SCENES[boss_id] as PackedScene).instantiate() as EnemyBase
	_container.add_child(boss)
	var safe_rect := _get_arena().get_safe_rect(boss.visual_safe_margin)
	boss.global_position = Vector2(
		lerpf(safe_rect.position.x, safe_rect.end.x, 0.78),
		safe_rect.get_center().y
	)
	boss.clamp_to_arena()
	_connect_enemy(boss)
	boss.begin_spawn_intro(0.65)
	enemy_spawned.emit(boss)
	boss_spawned.emit(boss)
	_emit_remaining()


func _complete_deferred_enemy_spawn(request_id: int) -> void:
	if not _deferred_spawn_requests.has(request_id):
		return
	var request: Dictionary = _deferred_spawn_requests[request_id]
	var source_ref: WeakRef = request.get("source_ref") as WeakRef
	var source: Node = source_ref.get_ref() as Node if source_ref != null else null
	if (
		int(request.get("generation", -1)) != _generation
		or not _active
		or not is_instance_valid(_container)
		or (int(request.get("source_id", 0)) != 0 and not is_instance_valid(source))
	):
		_cancel_deferred_spawn(request_id)
		return
	var scene := request.get("scene") as PackedScene
	var world_position: Vector2 = request.get("world_position", Vector2.ZERO)
	var spawn_context: StringName = request.get("spawn_context", &"split")
	var enemy := scene.instantiate() as EnemyBase
	if enemy == null:
		_cancel_deferred_spawn(request_id)
		return
	_container.add_child(enemy)
	enemy.global_position = world_position
	enemy.clamp_to_arena()
	_connect_enemy(enemy)
	_deferred_spawn_requests.erase(request_id)
	_pending_deferred_spawns = maxi(_pending_deferred_spawns - 1, 0)
	if spawn_context in [&"split", &"core_clone", &"core_clone_enraged"]:
		enemy.begin_spawn_intro(0.18 if spawn_context == &"split" else 0.45)
	if spawn_context == &"core_clone_enraged" and enemy.has_method("set_enraged"):
		enemy.set_enraged()
	enemy_spawned.emit(enemy)
	deferred_enemy_spawned.emit(enemy, spawn_context, int(request.get("source_id", 0)))
	_emit_remaining()


func _choose_spawn_point() -> Vector2:
	var candidates: Array[Vector2] = []
	var all_candidates := _get_arena().get_spawn_candidates(10.0)
	for point in all_candidates:
		if not is_instance_valid(_player) or point.distance_to(_player.global_position) >= 55.0:
			candidates.append(point)
	if candidates.is_empty():
		var furthest := _get_arena().get_safe_rect(10.0).get_center()
		var furthest_distance := -1.0
		for point in all_candidates:
			var distance := point.distance_to(_player.global_position) if is_instance_valid(_player) else 0.0
			if distance > furthest_distance:
				furthest = point
				furthest_distance = distance
		return furthest
	return candidates[_rng.randi_range(0, candidates.size() - 1)]


func _cancel_deferred_spawn(request_id: int) -> void:
	if not _deferred_spawn_requests.has(request_id):
		return
	var request: Dictionary = _deferred_spawn_requests[request_id]
	_deferred_spawn_requests.erase(request_id)
	_pending_deferred_spawns = maxi(_pending_deferred_spawns - 1, 0)
	deferred_enemy_spawn_cancelled.emit(
		request.get("spawn_context", &"split"),
		int(request.get("source_id", 0))
	)
	_emit_remaining()


func _get_arena() -> ArenaBounds:
	if not is_instance_valid(_arena_bounds):
		_arena_bounds = get_tree().get_first_node_in_group("arena_bounds") as ArenaBounds
	return _arena_bounds


func _on_container_child_entered(node: Node) -> void:
	if node is EnemyBase:
		_connect_enemy(node as EnemyBase)
		_emit_remaining.call_deferred()


func _connect_enemy(enemy: EnemyBase) -> void:
	var id := enemy.get_instance_id()
	if _connected_enemy_ids.has(id):
		return
	_connected_enemy_ids[id] = true
	enemy.enemy_died.connect(_on_enemy_died)


func _on_enemy_died(enemy: EnemyBase, hit_data: HitData) -> void:
	enemy_killed.emit(enemy, hit_data)
	_connected_enemy_ids.erase(enemy.get_instance_id())
	_emit_remaining.call_deferred()


func _get_alive_enemies() -> Array[EnemyBase]:
	var result: Array[EnemyBase] = []
	if not is_instance_valid(_container):
		return result
	for child in _container.get_children():
		if child is EnemyBase and (child as EnemyBase).is_alive():
			result.append(child as EnemyBase)
	return result


func _get_present_enemy_count() -> int:
	var count := 0
	if not is_instance_valid(_container):
		return count
	for child in _container.get_children():
		if child is EnemyBase:
			count += 1
	return count


func _emit_remaining() -> void:
	remaining_changed.emit(get_remaining())


func _build_definitions() -> void:
	if not _definitions.is_empty():
		return
	_definitions = [
		WaveDefinition.new(1, 6, [&"chaser"], 3, 5),
		WaveDefinition.new(2, 10, [&"chaser", &"shooter"], 4, 5),
		WaveDefinition.new(3, 14, [&"chaser", &"charger"], 4, 5),
		WaveDefinition.new(4, 18, [&"shooter", &"charger", &"splitter"], 5, 6),
		WaveDefinition.new(5, 0, [], 1, 1, &"boss_void"),
		WaveDefinition.new(6, 20, [&"chaser", &"heavy", &"splitter"], 5, 6),
		WaveDefinition.new(7, 24, [&"skirmisher", &"splitter", &"chaser"], 5, 6),
		WaveDefinition.new(
			8,
			30,
			[&"shooter", &"charger", &"heavy", &"skirmisher", &"splitter"],
			6,
			7
		),
		WaveDefinition.new(9, 0, [], 1, 1, &"boss_core"),
		WaveDefinition.new(10, 24, [&"chaser", &"heavy", &"skirmisher"], 5, 6),
		WaveDefinition.new(
			11,
			28,
			[&"shooter", &"charger", &"heavy", &"skirmisher", &"splitter"],
			6,
			7
		),
		WaveDefinition.new(
			12,
			32,
			[&"chaser", &"shooter", &"charger", &"heavy", &"skirmisher", &"splitter"],
			6,
			7
		),
		WaveDefinition.new(13, 0, [], 1, 1, &"boss_rift"),
	]
