class_name FeedbackManager
extends Node

const DEFAULT_CAMERA_ZOOM := Vector2(2.0, 2.0)

var _camera: Camera2D
var _shake_amplitude := 0.0
var _shake_remaining := 0.0
var _shake_duration := 0.0
var _hit_stop_until_msec := 0
var _hit_stop_running := false
var _boss_sequence_running := false
var _boss_sequence_id := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group("feedback_manager")


func set_camera(camera: Camera2D) -> void:
	_camera = camera


func request_camera_shake(amplitude: float, duration: float) -> void:
	_shake_amplitude = maxf(_shake_amplitude, clampf(amplitude, 0.0, 5.0))
	_shake_remaining = maxf(_shake_remaining, duration)
	_shake_duration = maxf(_shake_duration, duration)


func request_hit_stop(duration: float) -> void:
	if _boss_sequence_running:
		return
	var requested_until := Time.get_ticks_msec() + int(duration * 1000.0)
	_hit_stop_until_msec = maxi(_hit_stop_until_msec, requested_until)
	if not _hit_stop_running:
		_run_hit_stop()


func spawn_hit_particles(world_position: Vector2, size_factor: float) -> void:
	var count := 4 if size_factor < 1.5 else 6 if size_factor < 2.4 else 9
	var distance := lerpf(7.0, 16.0, inverse_lerp(CombatMath.MIN_SIZE, 3.0, size_factor))
	_spawn_shards(
		world_position,
		count,
		distance,
		0.18,
		Color(1.0, 0.82, 0.35, 0.9),
		30
	)


func spawn_enemy_death_particles(
	world_position: Vector2,
	visual_scale: float,
	boss: bool
) -> void:
	if boss:
		for burst in 3:
			_spawn_delayed_boss_burst(world_position, burst)
		request_camera_shake(5.0, 0.35)
		return
	var count := clampi(roundi(16.0 + visual_scale * 2.0), 16, 22)
	_spawn_shards(
		world_position,
		count,
		22.0,
		0.38,
		Color(1.0, 0.38, 0.16, 1.0),
		42
	)
	spawn_shockwave(world_position, 18.0, Color(1.0, 0.65, 0.22, 0.9))
	request_camera_shake(1.8, 0.12)


func spawn_shockwave(
	world_position: Vector2,
	radius: float,
	color := Color(1.0, 0.72, 0.24, 0.9)
) -> void:
	var effects_parent := _get_effects_parent()
	if effects_parent == null:
		return
	var ring := Line2D.new()
	var points := PackedVector2Array()
	for index in 25:
		points.append(Vector2.RIGHT.rotated(TAU * float(index) / 24.0))
	ring.points = points
	ring.closed = true
	ring.width = 1.5
	ring.default_color = color
	ring.global_position = world_position
	ring.scale = Vector2(0.1, 0.1)
	ring.z_index = 41
	effects_parent.add_child(ring)
	var tween := ring.create_tween()
	tween.set_parallel(true)
	tween.tween_property(ring, "scale", Vector2.ONE * radius, 0.28)
	tween.tween_property(ring, "modulate:a", 0.0, 0.28)
	tween.finished.connect(ring.queue_free)


func spawn_guard_flash(world_position: Vector2) -> void:
	spawn_shockwave(world_position, 10.0, Color(0.35, 0.82, 1.0, 0.95))


func spawn_footstep_dust(
	world_position: Vector2,
	color: Color,
	size_factor := 1.0
) -> void:
	if get_tree().get_nodes_in_group("footstep_particle").size() >= 64:
		return
	var effects_parent := _get_effects_parent()
	if effects_parent == null:
		return
	for side in [-1.0, 1.0]:
		var dust := Polygon2D.new()
		var size := randf_range(0.55, 0.95) * size_factor
		dust.polygon = PackedVector2Array([
			Vector2(-size, -size),
			Vector2(size, -size),
			Vector2(size, size),
			Vector2(-size, size),
		])
		dust.color = color
		dust.global_position = world_position + Vector2(side * randf_range(0.8, 1.8), 0.0)
		dust.z_index = 15
		dust.add_to_group("footstep_particle")
		effects_parent.add_child(dust)
		var tween := dust.create_tween()
		tween.set_parallel(true)
		tween.tween_property(
			dust,
			"position",
			dust.position + Vector2(side * randf_range(1.5, 3.0), randf_range(-1.8, -0.6)),
			0.24
		)
		tween.tween_property(dust, "modulate:a", 0.0, 0.24)
		tween.tween_property(dust, "scale", Vector2(0.25, 0.25), 0.24)
		tween.finished.connect(dust.queue_free)


func play_boss_death_sequence(_world_position: Vector2) -> void:
	_boss_sequence_id += 1
	var sequence_id := _boss_sequence_id
	_boss_sequence_running = true
	_hit_stop_running = false
	_hit_stop_until_msec = 0
	Engine.time_scale = 0.25
	request_camera_shake(3.0, 0.45)
	if is_instance_valid(_camera):
		var zoom_tween := create_tween()
		zoom_tween.set_ignore_time_scale(true)
		zoom_tween.tween_property(_camera, "zoom", Vector2(2.2, 2.2), 0.20)
		zoom_tween.tween_interval(0.34)
		zoom_tween.tween_property(_camera, "zoom", DEFAULT_CAMERA_ZOOM, 0.26)
	await get_tree().create_timer(0.80, true, false, true).timeout
	if sequence_id != _boss_sequence_id:
		return
	_boss_sequence_running = false
	Engine.time_scale = 1.0
	if is_instance_valid(_camera):
		_camera.zoom = DEFAULT_CAMERA_ZOOM
		_camera.offset = Vector2.ZERO


func reset_feedback() -> void:
	_boss_sequence_id += 1
	_boss_sequence_running = false
	_hit_stop_until_msec = 0
	_hit_stop_running = false
	Engine.time_scale = 1.0
	_shake_amplitude = 0.0
	_shake_remaining = 0.0
	_shake_duration = 0.0
	if is_instance_valid(_camera):
		_camera.offset = Vector2.ZERO
		_camera.zoom = DEFAULT_CAMERA_ZOOM


func is_boss_sequence_running() -> bool:
	return _boss_sequence_running


func _process(delta: float) -> void:
	if not is_instance_valid(_camera):
		return
	if _shake_remaining > 0.0:
		_shake_remaining = maxf(_shake_remaining - delta, 0.0)
		var falloff := 1.0
		if _shake_duration > 0.0:
			falloff = _shake_remaining / _shake_duration
		_camera.offset = Vector2(
			randf_range(-1.0, 1.0),
			randf_range(-1.0, 1.0)
		) * _shake_amplitude * falloff
	else:
		_camera.offset = _camera.offset.lerp(Vector2.ZERO, minf(delta * 28.0, 1.0))
		if _camera.offset.length_squared() < 0.01:
			_camera.offset = Vector2.ZERO
			_shake_amplitude = 0.0
			_shake_duration = 0.0


func _run_hit_stop() -> void:
	_hit_stop_running = true
	Engine.time_scale = 0.05
	while (
		is_inside_tree()
		and not _boss_sequence_running
		and Time.get_ticks_msec() < _hit_stop_until_msec
	):
		await get_tree().process_frame
	if not _boss_sequence_running:
		Engine.time_scale = 1.0
	_hit_stop_running = false


func _spawn_delayed_boss_burst(world_position: Vector2, burst: int) -> void:
	if burst > 0:
		await get_tree().create_timer(0.10 * burst, true, false, true).timeout
	if not is_inside_tree():
		return
	var colors := [
		Color(1.0, 0.78, 0.22, 1.0),
		Color(1.0, 0.28, 0.12, 1.0),
		Color(0.72, 0.40, 1.0, 1.0),
	]
	_spawn_shards(world_position, 22, 34.0 + burst * 8.0, 0.55, colors[burst], 45)
	spawn_shockwave(world_position, 24.0 + burst * 8.0, colors[burst])


func _spawn_shards(
	world_position: Vector2,
	count: int,
	distance: float,
	duration: float,
	color: Color,
	z: int
) -> void:
	var effects_parent := _get_effects_parent()
	if effects_parent == null:
		return
	for index in count:
		var shard := Polygon2D.new()
		var size := randf_range(1.0, 2.2)
		shard.polygon = PackedVector2Array([
			Vector2(-size, -size),
			Vector2(size, -size * 0.25),
			Vector2(size * 0.25, size),
			Vector2(-size, size * 0.25),
		])
		shard.color = color.lightened(randf_range(0.0, 0.25))
		shard.global_position = world_position
		shard.rotation = TAU * float(index) / float(count) + randf_range(-0.16, 0.16)
		shard.z_index = z
		effects_parent.add_child(shard)
		var direction := Vector2.RIGHT.rotated(shard.rotation)
		var tween := shard.create_tween()
		tween.set_parallel(true)
		tween.tween_property(
			shard,
			"position",
			shard.position + direction * randf_range(distance * 0.55, distance),
			duration
		).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tween.tween_property(shard, "rotation", shard.rotation + randf_range(-2.5, 2.5), duration)
		tween.tween_property(shard, "modulate:a", 0.0, duration)
		tween.tween_property(shard, "scale", Vector2(0.2, 0.2), duration)
		tween.finished.connect(shard.queue_free)


func _get_effects_parent() -> Node:
	return get_tree().get_first_node_in_group("world_effects")
