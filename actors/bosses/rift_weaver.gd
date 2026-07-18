class_name RiftWeaverBoss
extends EnemyBase

const BULLET_SCENE := preload("res://actors/enemies/enemy_bullet.tscn")
const AREA_TELEGRAPH := preload("res://combat/area_telegraph.tscn")
const DASH_TELEGRAPH := preload("res://combat/dash_telegraph.tscn")
const PATH_WINDUP_DURATION := 1.20
const AIM_REVEAL_DURATION := 0.20
const BOUNCE_REVEAL_DURATION := 0.55
const BOUNDARY_NUDGE := 1.0
const PATH_FILL_COLOR := Color(0.48, 0.12, 0.72, 0.34)
const PATH_EDGE_COLOR := Color(0.88, 0.38, 1.0, 0.94)

enum WeaverState {
	IDLE,
	PATH_WINDUP,
	PATH_DASH,
	RECOVERY,
}

var _state := WeaverState.IDLE
var _timer := 1.0
var _path_points: Array[Vector2] = []
var _path_index := 0
var _path_reflection_count := 0
var _path_telegraphs: Array[DashTelegraph] = []
var _path_segment_lengths: Array[float] = []
var _route_hit_player := false
var _rng := RandomNumberGenerator.new()
var _dash_speed := 190.0
var _segment_start := Vector2.ZERO
var _active_mines: Array[Node2D] = []
var _path_origin := Vector2.ZERO
var _initial_route_direction := Vector2.RIGHT
var _last_valid_route_direction := Vector2.RIGHT
var _telegraph_total_length := 0.0
var _telegraph_first_length := 0.0

@onready var route_damage_area: Area2D = $RouteDamageArea


func _enemy_ready() -> void:
	contact_damage = 0.0
	_rng.randomize()
	route_damage_area.monitoring = false
	route_damage_area.body_entered.connect(_on_route_damage_body_entered)


func _tick_behavior(delta: float) -> void:
	match _state:
		WeaverState.IDLE:
			set_desired_velocity(Vector2.ZERO)
			_timer -= delta
			if _timer <= 0.0:
				_begin_path_windup()
		WeaverState.PATH_WINDUP:
			set_desired_velocity(Vector2.ZERO)
			_timer = maxf(_timer - delta, 0.0)
			var elapsed := PATH_WINDUP_DURATION - _timer
			set_charge_visual(elapsed / PATH_WINDUP_DURATION, 1.30)
			_update_path_telegraph(elapsed)
			if _timer <= 0.0:
				_begin_path_dash()
		WeaverState.PATH_DASH:
			if _path_index >= _path_points.size():
				_finish_path()
				return
			var offset := _path_points[_path_index] - global_position
			if offset.length() <= 3.0:
				_reach_path_vertex()
			else:
				set_desired_velocity(offset.normalized() * _dash_speed)
		WeaverState.RECOVERY:
			set_desired_velocity(Vector2.ZERO)
			_timer = maxf(_timer - delta, 0.0)
			if _timer <= 0.0:
				_state = WeaverState.IDLE
				_timer = _get_path_idle_duration()


func _begin_path_windup() -> void:
	_state = WeaverState.PATH_WINDUP
	_timer = PATH_WINDUP_DURATION
	var arena := get_tree().get_first_node_in_group("arena_bounds") as ArenaBounds
	if arena != null:
		var route_start_rect := arena.get_safe_rect(visual_safe_margin).grow(-4.0)
		global_position = Vector2(
			clampf(global_position.x, route_start_rect.position.x, route_start_rect.end.x),
			clampf(global_position.y, route_start_rect.position.y, route_start_rect.end.y)
		)
	_path_origin = global_position
	var player := get_target()
	if player != null:
		var aim_offset := player.global_position - global_position
		if aim_offset.length_squared() > 0.0001:
			_last_valid_route_direction = aim_offset.normalized()
	_initial_route_direction = _last_valid_route_direction
	var reflection_count := 2 if get_health_ratio() > 0.70 else 3
	_path_reflection_count = reflection_count
	_path_points = _build_reflection_path(
		_path_origin,
		_initial_route_direction,
		reflection_count
	)
	_path_index = 0
	_segment_start = global_position
	_cache_telegraph_lengths()
	_create_path_telegraphs()
	_play_audio(&"enemy_spell")


func _begin_path_dash() -> void:
	_state = WeaverState.PATH_DASH
	_route_hit_player = false
	collision_mask = 1
	route_damage_area.set_deferred("monitoring", true)
	_dash_speed = 210.0 if get_health_ratio() <= 0.40 else 190.0
	clear_charge_visual()
	for telegraph in _path_telegraphs:
		if is_instance_valid(telegraph):
			telegraph.set_progress(1.0)
			telegraph.modulate.a = 1.0
	_play_audio(&"enemy_dash")


func _reach_path_vertex() -> void:
	var target_point := _path_points[_path_index]
	global_position = _path_points[_path_index]
	clamp_to_arena()
	if (
		_path_index < _path_reflection_count
		and _should_fire_vertex_fan(_path_index)
	):
		_fire_vertex_fan()
	if get_health_ratio() <= 0.70:
		_release_delayed_path_shockwave(_segment_start, target_point)
	_segment_start = target_point
	_path_index += 1
	if _path_index >= _path_points.size():
		_finish_path()


func _finish_path() -> void:
	set_desired_velocity(Vector2.ZERO)
	velocity = Vector2.ZERO
	collision_mask = 3
	route_damage_area.set_deferred("monitoring", false)
	_clear_path_telegraphs()
	if get_health_ratio() <= 0.40:
		_teleport_and_seed_mines()
	_state = WeaverState.RECOVERY
	_timer = _get_path_recovery_duration()


func _build_reflection_path(
	origin: Vector2,
	initial_direction: Vector2,
	reflection_count: int
) -> Array[Vector2]:
	var result: Array[Vector2] = []
	var arena := get_tree().get_first_node_in_group("arena_bounds") as ArenaBounds
	if arena == null:
		return result
	var direction := (
		initial_direction.normalized()
		if initial_direction.length_squared() > 0.0001
		else Vector2.RIGHT
	)
	var ray_origin := arena.clamp_position(origin, visual_safe_margin)
	for _reflection_index in range(maxi(reflection_count, 0)):
		var hit := arena.get_ray_boundary_hit(
			ray_origin,
			direction,
			visual_safe_margin
		)
		if hit.is_empty():
			break
		var hit_position: Vector2 = hit["position"]
		var normal: Vector2 = hit["normal"]
		if result.is_empty() and hit_position.distance_to(origin) < 2.0:
			break
		if not result.is_empty() and hit_position.distance_to(result[-1]) < 2.0:
			break
		result.append(hit_position)
		if not is_zero_approx(normal.x) and not is_zero_approx(normal.y):
			direction = -direction
		else:
			direction = direction.bounce(normal.normalized()).normalized()
		ray_origin = arena.clamp_position(
			hit_position + direction * BOUNDARY_NUDGE,
			visual_safe_margin
		)
	if result.size() != maxi(reflection_count, 0):
		return result
	var terminal_hit := arena.get_ray_boundary_hit(
		ray_origin,
		direction,
		visual_safe_margin
	)
	if terminal_hit.is_empty():
		return result
	var next_boundary: Vector2 = terminal_hit["position"]
	var available_distance := ray_origin.distance_to(next_boundary)
	var terminal_distance := minf(48.0, available_distance * 0.55)
	if terminal_distance > 1.0:
		result.append(arena.clamp_position(
			ray_origin + direction * terminal_distance,
			visual_safe_margin
		))
	return result


func _fire_vertex_fan() -> void:
	var player := get_target()
	if player == null or not is_instance_valid(player):
		return
	var ratio := get_health_ratio()
	var bullet_count := 3 if ratio > 0.70 or ratio <= 0.40 else 5
	var spread_degrees := 40.0 if ratio > 0.70 else 58.0 if ratio > 0.40 else 52.0
	var prediction_time := 0.0 if ratio > 0.70 else 0.18 if ratio > 0.40 else 0.22
	var bullet_speed := 62.0 if ratio > 0.70 else 66.0 if ratio > 0.40 else 68.0
	var target_position := player.global_position + player.velocity * prediction_time
	var arena := get_tree().get_first_node_in_group("arena_bounds") as ArenaBounds
	if arena != null:
		target_position = arena.clamp_position(target_position, 3.0)
	var aim_direction := target_position - global_position
	if aim_direction.length_squared() <= 0.0001:
		aim_direction = _initial_route_direction
	var center_angle := aim_direction.angle()
	var spread_radians := deg_to_rad(spread_degrees)
	for index in bullet_count:
		var fraction := float(index) / float(maxi(bullet_count - 1, 1))
		var angle := center_angle - spread_radians * 0.5 + spread_radians * fraction
		var bullet := BULLET_SCENE.instantiate() as EnemyBullet
		get_parent().add_child(bullet)
		bullet.global_position = global_position
		bullet.launch(Vector2.RIGHT.rotated(angle), bullet_speed, 12.0)


func _should_fire_vertex_fan(reflection_index: int) -> bool:
	if reflection_index < 0 or reflection_index >= _path_reflection_count:
		return false
	if get_health_ratio() > 0.70:
		return reflection_index == 0
	return reflection_index % 2 == 0


func _get_path_recovery_duration() -> float:
	if get_health_ratio() <= 0.40:
		return 1.80
	if get_health_ratio() <= 0.70:
		return 1.15
	return 1.05


func _get_path_idle_duration() -> float:
	return 1.15 if get_health_ratio() <= 0.40 else 0.85


func _cache_telegraph_lengths() -> void:
	_telegraph_total_length = 0.0
	_telegraph_first_length = 0.0
	_path_segment_lengths.clear()
	var previous := _path_origin
	for index in _path_points.size():
		var segment_length := previous.distance_to(_path_points[index])
		_path_segment_lengths.append(segment_length)
		if index == 0:
			_telegraph_first_length = segment_length
		_telegraph_total_length += segment_length
		previous = _path_points[index]


func _create_path_telegraphs() -> void:
	_clear_path_telegraphs()
	var previous := _path_origin
	var route_width := _get_route_damage_width()
	for point in _path_points:
		var offset := point - previous
		if offset.length_squared() <= 0.0001:
			previous = point
			continue
		var telegraph := DASH_TELEGRAPH.instantiate() as DashTelegraph
		get_parent().add_child(telegraph)
		telegraph.global_position = previous
		telegraph.z_index = 8
		telegraph.configure(
			offset.normalized(),
			offset.length(),
			route_width,
			false,
			PATH_FILL_COLOR,
			PATH_EDGE_COLOR
		)
		telegraph.set_progress(0.0)
		_path_telegraphs.append(telegraph)
		previous = point


func _update_path_telegraph(elapsed: float) -> void:
	if _path_telegraphs.is_empty() or _path_points.is_empty():
		return
	var visible_length := 0.0
	if elapsed < AIM_REVEAL_DURATION:
		visible_length = _telegraph_first_length * clampf(
			elapsed / AIM_REVEAL_DURATION,
			0.0,
			1.0
		)
	elif elapsed < AIM_REVEAL_DURATION + BOUNCE_REVEAL_DURATION:
		var reveal_progress := (
			(elapsed - AIM_REVEAL_DURATION) / BOUNCE_REVEAL_DURATION
		)
		visible_length = lerpf(
			_telegraph_first_length,
			_telegraph_total_length,
			clampf(reveal_progress, 0.0, 1.0)
		)
	else:
		visible_length = _telegraph_total_length
	var consumed_length := 0.0
	for index in _path_telegraphs.size():
		var segment_length := _path_segment_lengths[index]
		var segment_progress := clampf(
			(visible_length - consumed_length) / maxf(segment_length, 0.001),
			0.0,
			1.0
		)
		_path_telegraphs[index].set_progress(segment_progress)
		consumed_length += segment_length
	var telegraph_alpha := (
		0.62 + sin(Time.get_ticks_msec() * 0.025) * 0.24
		if elapsed >= AIM_REVEAL_DURATION + BOUNCE_REVEAL_DURATION
		else 1.0
	)
	for telegraph in _path_telegraphs:
		if is_instance_valid(telegraph):
			telegraph.modulate.a = telegraph_alpha


func _get_route_damage_width() -> float:
	var route_shape_node := route_damage_area.get_node("CollisionShape2D") as CollisionShape2D
	var rectangle := route_shape_node.shape as RectangleShape2D
	return rectangle.size.y if rectangle != null else 14.0


func _clear_path_telegraphs() -> void:
	for telegraph in _path_telegraphs:
		if is_instance_valid(telegraph):
			telegraph.queue_free()
	_path_telegraphs.clear()


func _release_delayed_path_shockwave(start: Vector2, finish: Vector2) -> void:
	var generation_position := global_position
	await get_tree().create_timer(0.65).timeout
	if not is_inside_tree() or not is_alive():
		return
	var line := Line2D.new()
	line.width = 12.0
	line.default_color = Color(0.74, 0.30, 1.0, 0.46)
	line.z_index = 7
	line.points = PackedVector2Array([start, finish])
	get_parent().add_child(line)
	var player := get_target()
	if player != null:
		var nearest := Geometry2D.get_closest_point_to_segment(
			player.global_position,
			start,
			finish
		)
		if nearest.distance_to(player.global_position) <= 7.0:
			var away := (player.global_position - generation_position).normalized()
			player.take_hit(HitData.new(18.0, away * 34.0, self, 1.0, get_instance_id()))
	var tween := line.create_tween()
	tween.tween_property(line, "modulate:a", 0.0, 0.24)
	tween.finished.connect(line.queue_free)


func _teleport_and_seed_mines() -> void:
	var arena := get_tree().get_first_node_in_group("arena_bounds") as ArenaBounds
	if arena == null:
		return
	var safe_rect := arena.get_safe_rect(visual_safe_margin)
	var teleport_rect := safe_rect.grow(-4.0)
	global_position = Vector2(
		_rng.randf_range(teleport_rect.position.x, teleport_rect.end.x),
		_rng.randf_range(teleport_rect.position.y, teleport_rect.end.y)
	)
	for index in 3:
		var mine_position := Vector2(
			_rng.randf_range(safe_rect.position.x, safe_rect.end.x),
			_rng.randf_range(safe_rect.position.y, safe_rect.end.y)
		)
		_seed_mine(mine_position, index * 0.08)


func _seed_mine(mine_position: Vector2, delay: float) -> void:
	await get_tree().create_timer(delay).timeout
	if not is_inside_tree() or not is_alive():
		return
	var mine := AREA_TELEGRAPH.instantiate() as AreaTelegraph
	get_parent().add_child(mine)
	_active_mines.append(mine)
	mine.global_position = mine_position
	mine.configure(16.0, Color(0.94, 0.22, 0.86, 0.92))
	var elapsed := 0.0
	while elapsed < 0.90:
		await get_tree().process_frame
		if not is_instance_valid(mine) or not is_alive():
			if is_instance_valid(mine):
				mine.queue_free()
			_active_mines.erase(mine)
			return
		elapsed += get_process_delta_time()
		mine.set_progress(elapsed / 0.90)
	var player := get_target()
	if player != null and player.global_position.distance_to(mine_position) <= 16.0:
		var away := (player.global_position - mine_position).normalized()
		player.take_hit(HitData.new(22.0, away * 42.0, self, 1.0, get_instance_id()))
	var feedback := get_tree().get_first_node_in_group("feedback_manager")
	if feedback != null and feedback.has_method("spawn_shockwave"):
		feedback.spawn_shockwave(mine_position, 16.0, Color(0.92, 0.22, 0.82, 0.92))
	mine.queue_free()
	_active_mines.erase(mine)


func _on_route_damage_body_entered(body: Node2D) -> void:
	if _state != WeaverState.PATH_DASH or _route_hit_player:
		return
	var player := body as PlayerController
	if player == null:
		return
	_route_hit_player = true
	var away := (player.global_position - global_position).normalized()
	player.take_hit(HitData.new(30.0, away * 48.0, self, 1.0, get_instance_id()))


func _uses_soft_separation() -> bool:
	return false


func _before_death(_hit_data: HitData) -> void:
	collision_mask = 3
	route_damage_area.set_deferred("monitoring", false)
	_clear_path_telegraphs()
	for mine in _active_mines:
		if is_instance_valid(mine):
			mine.queue_free()
	_active_mines.clear()
	for bullet in get_tree().get_nodes_in_group("enemy_bullet"):
		bullet.queue_free()


func _play_audio(event_id: StringName) -> void:
	var audio := get_tree().get_first_node_in_group("audio_manager")
	if audio != null and audio.has_method("play_game_sfx"):
		audio.play_game_sfx(event_id, global_position, 1.0)
