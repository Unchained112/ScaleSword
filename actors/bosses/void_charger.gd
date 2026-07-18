class_name VoidChargerBoss
extends EnemyBase

const BULLET_SCENE := preload("res://actors/enemies/enemy_bullet.tscn")
const DASH_TELEGRAPH := preload("res://combat/dash_telegraph.tscn")
const AREA_TELEGRAPH := preload("res://combat/area_telegraph.tscn")

enum BossState {
	IDLE,
	DASH_WINDUP,
	DASH,
	TELEPORT_WINDUP,
	BULLET_WINDUP,
	RECOVERY,
}

var _state := BossState.IDLE
var _timer := 1.0
var _action_index := 0
var _phase_two := false
var _dash_direction := Vector2.RIGHT
var _dash_length := 0.0
var _dash_speed := 0.0
var _dash_travelled := 0.0
var _dash_damage := 0.0
var _long_dash := false
var _short_dashes_remaining := 0
var _dash_hit_player := false
var _dash_sequence := 0
var _teleport_target := Vector2.ZERO
var _telegraph: Node2D
var _combo_actions: Array[StringName] = []


func _enemy_ready() -> void:
	contact_damage = 0.0


func _tick_behavior(delta: float) -> void:
	if not _phase_two and get_health_ratio() <= 0.50:
		_phase_two = true
	match _state:
		BossState.IDLE:
			set_desired_velocity(Vector2.ZERO)
			_timer -= delta
			if _timer <= 0.0:
				_choose_action()
		BossState.DASH_WINDUP:
			_timer = maxf(_timer - delta, 0.0)
			set_desired_velocity(Vector2.ZERO)
			var duration := 1.08 if _long_dash else 0.55
			var progress := 1.0 - _timer / duration
			set_charge_visual(progress, 1.35 if _long_dash else 1.22)
			if _long_dash and _telegraph is DashTelegraph:
				(_telegraph as DashTelegraph).set_progress(progress)
			if _timer <= 0.0:
				_begin_dash()
		BossState.DASH:
			set_desired_velocity(_dash_direction * _dash_speed)
		BossState.TELEPORT_WINDUP:
			_timer = maxf(_timer - delta, 0.0)
			set_desired_velocity(Vector2.ZERO)
			set_charge_visual(1.0 - _timer / 0.50, 1.25)
			if _telegraph is AreaTelegraph:
				(_telegraph as AreaTelegraph).set_progress(1.0 - _timer / 0.50)
			if _timer <= 0.0:
				_teleport_target = _get_safe_position_around_player(
					_teleport_target,
					24.0,
					28.0
				)
				global_position = _teleport_target
				_clear_telegraph()
				clear_charge_visual()
				_start_recovery(0.35)
		BossState.BULLET_WINDUP:
			_timer = maxf(_timer - delta, 0.0)
			set_desired_velocity(Vector2.ZERO)
			set_charge_visual(1.0 - _timer / 0.55, 1.20)
			if _telegraph is AreaTelegraph:
				(_telegraph as AreaTelegraph).set_progress(1.0 - _timer / 0.55)
			if _timer <= 0.0:
				_fire_safe_ring()
				_clear_telegraph()
				clear_charge_visual()
				_start_recovery(0.60)
		BossState.RECOVERY:
			set_desired_velocity(Vector2.ZERO)
			_timer = maxf(_timer - delta, 0.0)
			if _timer <= 0.0:
				if not _combo_actions.is_empty():
					_start_action(_combo_actions.pop_front())
				else:
					_state = BossState.IDLE
					_timer = 0.65 if _phase_two else 0.90


func _choose_action() -> void:
	if _phase_two and _action_index % 3 == 2:
		_combo_actions = [&"bullet", &"long"]
		_start_action(&"teleport")
	else:
		var cycle: Array[StringName] = [&"short", &"long", &"teleport", &"bullet"]
		_start_action(cycle[_action_index % cycle.size()])
	_action_index += 1


func _start_action(action: StringName) -> void:
	match action:
		&"short":
			_short_dashes_remaining = 1 if _phase_two else 0
			_start_dash(false)
		&"long":
			_start_dash(true)
		&"teleport":
			_start_teleport()
		&"bullet":
			_start_bullet_windup()


func _start_dash(long_dash: bool, override_windup := -1.0) -> void:
	var player := get_target()
	if player == null:
		return
	if not long_dash and global_position.distance_to(player.global_position) < 18.0:
		global_position = _get_safe_position_around_player(
			global_position,
			18.0,
			20.0
		)
	_long_dash = long_dash
	_state = BossState.DASH_WINDUP
	_timer = override_windup if override_windup > 0.0 else 1.08 if long_dash else 0.55
	_dash_direction = (player.global_position - global_position).normalized()
	if _dash_direction.length_squared() < 0.001:
		_dash_direction = Vector2.RIGHT
	_dash_length = 138.0 if long_dash else 68.0
	_dash_speed = 172.0 if long_dash else 148.0
	_dash_damage = 28.0 if long_dash else 21.0
	_telegraph = DASH_TELEGRAPH.instantiate() as DashTelegraph
	add_child(_telegraph)
	(_telegraph as DashTelegraph).configure(
		_dash_direction,
		_dash_length,
		15.0 if long_dash else 11.0,
		long_dash
	)


func _begin_dash() -> void:
	_state = BossState.DASH
	_dash_travelled = 0.0
	_dash_hit_player = false
	_dash_sequence += 1
	_clear_telegraph()
	_charge_visual_active = true
	visual_root.rotation = _dash_direction.angle()
	visual_root.skew = 0.0
	visual_root.scale = _visual_base_scale * Vector2(1.28, 0.76)
	_play_audio(&"enemy_dash")


func _start_teleport() -> void:
	var player := get_target()
	if player == null:
		return
	_state = BossState.TELEPORT_WINDUP
	_timer = 0.50
	var offset := (player.global_position - global_position).normalized() * 24.0
	_teleport_target = player.global_position + offset.rotated(PI * 0.72)
	_teleport_target = _get_arena_safe_position(_teleport_target)
	_telegraph = AREA_TELEGRAPH.instantiate() as AreaTelegraph
	get_parent().add_child(_telegraph)
	_telegraph.global_position = _teleport_target
	(_telegraph as AreaTelegraph).configure(10.0, Color(0.72, 0.36, 1.0, 0.92))
	_play_audio(&"enemy_spell")


func _start_bullet_windup() -> void:
	_state = BossState.BULLET_WINDUP
	_timer = 0.55
	_telegraph = AREA_TELEGRAPH.instantiate() as AreaTelegraph
	add_child(_telegraph)
	(_telegraph as AreaTelegraph).configure(17.0, Color(1.0, 0.45, 0.12, 0.90))
	_play_audio(&"enemy_spell")


func _fire_safe_ring() -> void:
	var player := get_target()
	if player == null:
		return
	var safe_angle := (player.global_position - global_position).angle()
	_fire_ring_layer(safe_angle, 18 if _phase_two else 16, 0.0)
	if _phase_two:
		_fire_second_ring(safe_angle)


func _fire_ring_layer(safe_angle: float, bullet_count: int, angle_offset: float) -> void:
	for index in bullet_count:
		var angle := TAU * float(index) / float(bullet_count) + angle_offset
		if absf(wrapf(angle - safe_angle, -PI, PI)) < deg_to_rad(25.0):
			continue
		var bullet := BULLET_SCENE.instantiate() as EnemyBullet
		get_parent().add_child(bullet)
		bullet.global_position = global_position
		bullet.launch(Vector2.RIGHT.rotated(angle), 58.0, 11.0)


func _fire_second_ring(safe_angle: float) -> void:
	await get_tree().create_timer(0.18).timeout
	if not is_inside_tree() or not is_alive():
		return
	_fire_ring_layer(safe_angle, 18, TAU / 36.0)


func _start_recovery(duration: float) -> void:
	_state = BossState.RECOVERY
	_timer = 1.0 if _phase_two and _combo_actions.is_empty() else duration
	contact_damage = 0.0
	clear_charge_visual()


func _process_contact_collisions() -> void:
	if _state != BossState.DASH:
		return
	for collision_index in get_slide_collision_count():
		var collision := get_slide_collision(collision_index)
		var player := collision.get_collider() as PlayerController
		if player != null:
			if not _dash_hit_player:
				_dash_hit_player = true
				var knockback_direction := (
					player.global_position - global_position
				).normalized()
				if knockback_direction.length_squared() < 0.0001:
					knockback_direction = _dash_direction
				player.take_hit(HitData.new(
					_dash_damage,
					knockback_direction * 46.0,
					self,
					1.0,
					get_instance_id() + _dash_sequence
				))
			_separate_from_player(player, 12.0)
			_finish_dash_after_collision()
			return
		global_position += collision.get_normal() * 4.0
		clamp_to_arena()
		_finish_dash_after_collision()
		return


func _after_motion(_delta: float, actual_displacement: Vector2) -> void:
	if _state != BossState.DASH:
		return
	if is_outside_visual_safe_rect():
		global_position -= _dash_direction * 4.0
		clamp_to_arena()
		_finish_dash_after_collision()
		return
	_dash_travelled += maxf(actual_displacement.dot(_dash_direction), 0.0)
	if _dash_travelled < _dash_length:
		return
	if _short_dashes_remaining > 0:
		_short_dashes_remaining -= 1
		_start_dash(false, 0.36)
	else:
		_start_recovery(0.80 if _long_dash else 0.55)


func _finish_dash_after_collision() -> void:
	_short_dashes_remaining = 0
	set_desired_velocity(Vector2.ZERO)
	velocity = Vector2.ZERO
	_start_recovery(0.80 if _long_dash else 0.55)


func _separate_from_player(player: PlayerController, distance: float) -> void:
	var away := global_position - player.global_position
	if away.length_squared() < 0.0001:
		away = -_dash_direction
	global_position += away.normalized() * distance
	clamp_to_arena()


func _get_safe_position_around_player(
	preferred_position: Vector2,
	minimum_distance: float,
	target_distance: float
) -> Vector2:
	var player := get_target()
	if player == null:
		return preferred_position
	var preferred_direction := preferred_position - player.global_position
	if preferred_direction.length_squared() < 0.0001:
		preferred_direction = global_position - player.global_position
	if preferred_direction.length_squared() < 0.0001:
		preferred_direction = Vector2.RIGHT
	preferred_direction = preferred_direction.normalized()
	var best_candidate := preferred_position
	var best_distance := -1.0
	for angle_offset in [
		0.0,
		PI * 0.25,
		-PI * 0.25,
		PI * 0.50,
		-PI * 0.50,
		PI * 0.75,
		-PI * 0.75,
		PI,
	]:
		var candidate := (
			player.global_position
			+ preferred_direction.rotated(angle_offset) * target_distance
		)
		candidate = _get_arena_safe_position(candidate)
		var distance_to_player := candidate.distance_to(player.global_position)
		if distance_to_player > best_distance:
			best_candidate = candidate
			best_distance = distance_to_player
		if distance_to_player >= minimum_distance:
			return candidate
	return best_candidate


func _get_arena_safe_position(position: Vector2) -> Vector2:
	var arena := get_tree().get_first_node_in_group("arena_bounds") as ArenaBounds
	return arena.clamp_position(position, visual_safe_margin) if arena != null else position


func _uses_soft_separation() -> bool:
	return false


func _clear_telegraph() -> void:
	if is_instance_valid(_telegraph):
		_telegraph.queue_free()
	_telegraph = null


func _before_death(_hit_data: HitData) -> void:
	_clear_telegraph()
	for bullet in get_tree().get_nodes_in_group("enemy_bullet"):
		bullet.queue_free()


func _play_audio(event_id: StringName) -> void:
	var audio := get_tree().get_first_node_in_group("audio_manager")
	if audio != null and audio.has_method("play_game_sfx"):
		audio.play_game_sfx(event_id, global_position, 1.0)
