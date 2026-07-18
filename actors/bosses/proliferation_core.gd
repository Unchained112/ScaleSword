class_name ProliferationCoreBoss
extends EnemyBase

const DASH_TELEGRAPH := preload("res://combat/dash_telegraph.tscn")
const AREA_TELEGRAPH := preload("res://combat/area_telegraph.tscn")
const CLONE_SCENE := preload("res://actors/bosses/core_clone.tscn")
const CLONE_REPLENISH_DELAY := 6.0
const CLONE_REPLENISH_WARNING := 1.0
const ABSORB_REPLENISH_LOCKOUT := 10.0

enum CoreState {
	IDLE,
	DASH_WINDUP,
	DASH,
	SHOCK_WINDUP,
	ABSORB_WINDUP,
	RECOVERY,
}

var _state := CoreState.IDLE
var _timer := 1.0
var _action_index := 0
var _dash_direction := Vector2.RIGHT
var _dash_travelled := 0.0
var _dash_length := 128.0
var _dash_speed := 158.0
var _base_contact_damage := 18.0
var _telegraph: Node2D
var _spawned_seventy := false
var _spawned_forty := false
var _absorb_timer := 10.0
var _absorb_lines: Array[Line2D] = []
var _absorbed_count := 0
var _force_wide_dash := false
var _dash_hit_player := false
var _pending_clone_requests := 0
var _absorb_targets: Array[ProliferationClone] = []
var _clone_replenish_remaining := -1.0
var _clone_replenish_warning: AreaTelegraph
var _clone_replenish_position := Vector2.ZERO
var _clone_spawn_serial := 0
var _wave_manager: WaveManager
var _core_base_visual_scale := Vector2.ONE
var _base_collision_radius := 0.0
var _base_collision_height := 0.0
var _base_collision_size := Vector2.ZERO


func _enemy_ready() -> void:
	_base_contact_damage = contact_damage
	contact_damage = 0.0
	_core_base_visual_scale = _visual_base_scale
	_prepare_scalable_collision_shape()
	_wave_manager = get_tree().get_first_node_in_group("wave_manager") as WaveManager
	if _wave_manager != null:
		_wave_manager.deferred_enemy_spawned.connect(_on_deferred_clone_spawned)
		_wave_manager.deferred_enemy_spawn_cancelled.connect(_on_deferred_clone_cancelled)
		_wave_manager.enemy_killed.connect(_on_wave_enemy_killed)


func take_hit(hit_data: HitData) -> bool:
	var applied := super.take_hit(hit_data)
	if not applied or not is_alive():
		return applied
	if not _spawned_seventy and get_health_ratio() <= 0.70:
		_spawned_seventy = true
		_spawn_clones(2 - _get_clones().size() - _pending_clone_requests)
	if not _spawned_forty and get_health_ratio() <= 0.40:
		_spawned_forty = true
		_spawn_clones(4 - _get_clones().size() - _pending_clone_requests)
		for clone in _get_clones():
			clone.set_enraged()
	return applied


func _tick_behavior(delta: float) -> void:
	_absorb_timer -= delta
	_update_clone_replenishment(delta)
	match _state:
		CoreState.IDLE:
			set_desired_velocity(Vector2.ZERO)
			_timer -= delta
			if _absorb_timer <= 0.0 and not _get_absorbable_clones().is_empty():
				_start_absorb()
			elif _timer <= 0.0:
				if _action_index % 2 == 0:
					_start_dash()
				else:
					_start_shockwave()
				_action_index += 1
		CoreState.DASH_WINDUP:
			_timer = maxf(_timer - delta, 0.0)
			set_desired_velocity(Vector2.ZERO)
			var duration := 1.0
			var progress := 1.0 - _timer / duration
			set_charge_visual(progress, 1.45)
			if _telegraph is DashTelegraph:
				(_telegraph as DashTelegraph).set_progress(progress)
			if _timer <= 0.0:
				_begin_dash()
		CoreState.DASH:
			set_desired_velocity(_dash_direction * _dash_speed)
		CoreState.SHOCK_WINDUP:
			_timer = maxf(_timer - delta, 0.0)
			set_desired_velocity(Vector2.ZERO)
			set_charge_visual(1.0 - _timer / 0.90, 1.28)
			if _telegraph is AreaTelegraph:
				(_telegraph as AreaTelegraph).set_progress(1.0 - _timer / 0.90)
			if _timer <= 0.0:
				_release_shockwave()
				_clear_telegraph()
				clear_charge_visual()
				_start_recovery(0.72)
		CoreState.ABSORB_WINDUP:
			_timer = maxf(_timer - delta, 0.0)
			set_desired_velocity(Vector2.ZERO)
			set_charge_visual(1.0 - _timer / 1.80, 1.32)
			_update_absorb_lines()
			if _timer <= 0.0:
				_complete_absorb()
		CoreState.RECOVERY:
			set_desired_velocity(Vector2.ZERO)
			_timer = maxf(_timer - delta, 0.0)
			if _timer <= 0.0:
				if _force_wide_dash:
					_force_wide_dash = false
					_start_dash(true)
				else:
					_state = CoreState.IDLE
					_timer = 0.58 if get_health_ratio() <= 0.20 else 0.90


func _start_dash(wide := false) -> void:
	var player := get_target()
	if player == null:
		return
	_state = CoreState.DASH_WINDUP
	_timer = 1.0
	_dash_direction = (player.global_position - global_position).normalized()
	if _dash_direction.length_squared() < 0.001:
		_dash_direction = Vector2.RIGHT
	var growth := 1.0 + 0.06 * _absorbed_count
	_dash_length = (142.0 if wide else 128.0) * growth
	_dash_speed = 168.0 if wide else 158.0
	_telegraph = DASH_TELEGRAPH.instantiate() as DashTelegraph
	add_child(_telegraph)
	(_telegraph as DashTelegraph).configure(
		_dash_direction,
		_dash_length,
		(19.0 if wide else 15.0) * growth,
		true
	)


func _begin_dash() -> void:
	_state = CoreState.DASH
	_dash_travelled = 0.0
	_dash_hit_player = false
	_clear_telegraph()
	_charge_visual_active = true
	visual_root.rotation = _dash_direction.angle()
	visual_root.scale = _visual_base_scale * Vector2(1.30, 0.74)
	_play_audio(&"enemy_dash")


func _start_shockwave() -> void:
	_state = CoreState.SHOCK_WINDUP
	_timer = 0.90
	_telegraph = AREA_TELEGRAPH.instantiate() as AreaTelegraph
	add_child(_telegraph)
	(_telegraph as AreaTelegraph).configure(38.0, Color(1.0, 0.30, 0.08, 0.92))
	_play_audio(&"enemy_spell")


func _release_shockwave() -> void:
	var player := get_target()
	if player != null and global_position.distance_to(player.global_position) <= 38.0:
		var away := (player.global_position - global_position).normalized()
		player.take_hit(HitData.new(24.0, away * 42.0, self, 1.0, get_instance_id()))
	var feedback := get_tree().get_first_node_in_group("feedback_manager")
	if feedback != null and feedback.has_method("spawn_shockwave"):
		feedback.spawn_shockwave(global_position, 38.0, Color(1.0, 0.28, 0.08, 0.95))


func _start_absorb() -> void:
	_absorb_targets = _get_absorbable_clones()
	if _absorb_targets.size() > 2:
		_absorb_targets.resize(2)
	if _absorb_targets.is_empty():
		_absorb_timer = 2.0
		return
	_state = CoreState.ABSORB_WINDUP
	_timer = 1.80
	_absorb_timer = 10.0
	for clone in _absorb_targets:
		clone.set_absorb_frozen(true)
		var line := Line2D.new()
		line.width = 1.4
		line.default_color = Color(0.82, 0.35, 1.0, 0.82)
		line.z_index = 10
		get_parent().add_child(line)
		_absorb_lines.append(line)
	_play_audio(&"enemy_spell")


func _update_absorb_lines() -> void:
	for index in _absorb_lines.size():
		var line := _absorb_lines[index]
		if index >= _absorb_targets.size() or not is_instance_valid(_absorb_targets[index]):
			line.visible = false
			continue
		line.points = PackedVector2Array([
			_absorb_targets[index].global_position,
			global_position,
		])


func _complete_absorb() -> void:
	var absorbed := 0
	for clone in _absorb_targets:
		if not is_instance_valid(clone):
			continue
		absorbed += 1
		clone.queue_free()
	for line in _absorb_lines:
		if is_instance_valid(line):
			line.queue_free()
	_absorb_lines.clear()
	_absorb_targets.clear()
	if absorbed > 0:
		heal(35.0 * absorbed)
		_absorbed_count = mini(_absorbed_count + absorbed, 4)
		var growth := 1.0 + 0.06 * _absorbed_count
		_visual_base_scale = _core_base_visual_scale * growth
		visual_root.scale = _visual_base_scale
		_apply_collision_growth(growth)
		_force_wide_dash = true
		_start_clone_replenishment(ABSORB_REPLENISH_LOCKOUT, true)
	clear_charge_visual()
	_start_recovery(0.25)


func _prepare_scalable_collision_shape() -> void:
	if collision_shape.shape == null:
		return
	collision_shape.shape = collision_shape.shape.duplicate()
	var capsule := collision_shape.shape as CapsuleShape2D
	if capsule != null:
		_base_collision_radius = capsule.radius
		_base_collision_height = capsule.height
		return
	var circle := collision_shape.shape as CircleShape2D
	if circle != null:
		_base_collision_radius = circle.radius
		return
	var rectangle := collision_shape.shape as RectangleShape2D
	if rectangle != null:
		_base_collision_size = rectangle.size


func _apply_collision_growth(growth: float) -> void:
	var safe_growth := maxf(growth, 0.01)
	var capsule := collision_shape.shape as CapsuleShape2D
	if capsule != null:
		capsule.radius = _base_collision_radius * safe_growth
		capsule.height = _base_collision_height * safe_growth
		return
	var circle := collision_shape.shape as CircleShape2D
	if circle != null:
		circle.radius = _base_collision_radius * safe_growth
		return
	var rectangle := collision_shape.shape as RectangleShape2D
	if rectangle != null:
		rectangle.size = _base_collision_size * safe_growth


func _spawn_clones(amount: int) -> void:
	if amount <= 0:
		return
	for index in amount:
		var angle := TAU * float(index) / maxf(float(amount), 1.0)
		var spawn_position := global_position + Vector2.RIGHT.rotated(angle) * 24.0
		var arena := get_tree().get_first_node_in_group("arena_bounds") as ArenaBounds
		if arena != null:
			spawn_position = arena.clamp_position(spawn_position, 11.0)
		var context := &"core_clone_enraged" if _spawned_forty else &"core_clone"
		_request_clone_spawn(spawn_position, context)
	_absorb_timer = 10.0


func _request_clone_spawn(spawn_position: Vector2, context: StringName) -> bool:
	if _wave_manager != null:
		if not _wave_manager.is_active():
			return false
		if _wave_manager.request_deferred_enemy_spawn(
			CLONE_SCENE,
			spawn_position,
			context,
			self
		):
			_pending_clone_requests += 1
			return true
		return false
	var parent := get_parent()
	if not is_instance_valid(parent):
		return false
	var clone := CLONE_SCENE.instantiate() as ProliferationClone
	parent.call_deferred("add_child", clone)
	_apply_fallback_clone_position.call_deferred(clone, spawn_position, context)
	return true


func _update_clone_replenishment(delta: float) -> void:
	if (
		get_health_ratio() <= 0.20
		or _get_clone_cap() <= 0
		or (_wave_manager != null and not _wave_manager.is_active())
	):
		_cancel_clone_replenishment()
		return
	var deficit := _get_clone_cap() - _get_clones().size() - _pending_clone_requests
	if deficit <= 0:
		_cancel_clone_replenishment()
		return
	if _clone_replenish_remaining < 0.0:
		_start_clone_replenishment(CLONE_REPLENISH_DELAY)
	_clone_replenish_remaining = maxf(_clone_replenish_remaining - delta, 0.0)
	if (
		_clone_replenish_remaining <= CLONE_REPLENISH_WARNING
		and not is_instance_valid(_clone_replenish_warning)
	):
		_begin_clone_replenish_warning()
	if is_instance_valid(_clone_replenish_warning):
		_clone_replenish_warning.set_progress(
			1.0 - _clone_replenish_remaining / CLONE_REPLENISH_WARNING
		)
	if _clone_replenish_remaining > 0.0:
		return
	var spawn_position := _clone_replenish_position
	if not is_instance_valid(_clone_replenish_warning):
		spawn_position = _choose_clone_spawn_position()
	var context := &"core_clone_enraged" if _spawned_forty else &"core_clone"
	_clear_clone_replenish_warning()
	_clone_replenish_remaining = -1.0
	_request_clone_spawn(spawn_position, context)


func _start_clone_replenishment(duration: float, restart := false) -> void:
	if get_health_ratio() <= 0.20 or _get_clone_cap() <= 0:
		_cancel_clone_replenishment()
		return
	if not restart and _clone_replenish_remaining >= 0.0:
		return
	_clone_replenish_remaining = maxf(duration, CLONE_REPLENISH_WARNING)
	_clear_clone_replenish_warning()


func _cancel_clone_replenishment() -> void:
	_clone_replenish_remaining = -1.0
	_clear_clone_replenish_warning()


func _begin_clone_replenish_warning() -> void:
	_clone_replenish_position = _choose_clone_spawn_position()
	_clone_replenish_warning = AREA_TELEGRAPH.instantiate() as AreaTelegraph
	get_parent().add_child(_clone_replenish_warning)
	_clone_replenish_warning.global_position = _clone_replenish_position
	_clone_replenish_warning.configure(8.0, Color(0.80, 0.30, 1.0, 0.92))
	_clone_replenish_warning.set_progress(0.0)
	_play_audio(&"enemy_spell")


func _clear_clone_replenish_warning() -> void:
	if is_instance_valid(_clone_replenish_warning):
		_clone_replenish_warning.queue_free()
	_clone_replenish_warning = null


func _choose_clone_spawn_position() -> Vector2:
	var angle := TAU * float(_clone_spawn_serial % 8) / 8.0
	_clone_spawn_serial += 1
	var spawn_position := global_position + Vector2.RIGHT.rotated(angle) * 24.0
	var arena := get_tree().get_first_node_in_group("arena_bounds") as ArenaBounds
	if arena != null:
		spawn_position = arena.clamp_position(spawn_position, 11.0)
	return spawn_position


func _apply_fallback_clone_position(
	clone: ProliferationClone,
	spawn_position: Vector2,
	context: StringName
) -> void:
	if not is_instance_valid(clone) or not clone.is_inside_tree():
		return
	clone.global_position = spawn_position
	if context == &"core_clone_enraged":
		clone.set_enraged()
	clone.begin_spawn_intro(0.45)


func _get_clones() -> Array[ProliferationClone]:
	var result: Array[ProliferationClone] = []
	for node in get_tree().get_nodes_in_group("boss_clone"):
		if node is ProliferationClone and is_instance_valid(node) and node.is_alive():
			result.append(node)
	return result


func _get_absorbable_clones() -> Array[ProliferationClone]:
	var result: Array[ProliferationClone] = []
	for clone in _get_clones():
		if clone.get_active_duration() >= 6.0:
			result.append(clone)
	return result


func _get_clone_cap() -> int:
	if _spawned_forty:
		return 4
	if _spawned_seventy:
		return 2
	return 0


func _start_recovery(duration: float) -> void:
	_state = CoreState.RECOVERY
	_timer = duration
	contact_damage = 0.0
	clear_charge_visual()


func _process_contact_collisions() -> void:
	if _state != CoreState.DASH:
		return
	for collision_index in get_slide_collision_count():
		var collision := get_slide_collision(collision_index)
		var player := collision.get_collider() as PlayerController
		if player != null:
			if not _dash_hit_player:
				_dash_hit_player = true
				var direction := (player.global_position - global_position).normalized()
				if direction.length_squared() < 0.0001:
					direction = _dash_direction
				player.take_hit(HitData.new(
					30.0,
					direction * 48.0,
					self,
					1.0,
					get_instance_id()
				))
			var away := global_position - player.global_position
			if away.length_squared() < 0.0001:
				away = -_dash_direction
			global_position += away.normalized() * 14.0
		else:
			global_position += collision.get_normal() * 4.0
		clamp_to_arena()
		velocity = Vector2.ZERO
		_start_recovery(0.72)
		return


func _after_motion(_delta: float, actual_displacement: Vector2) -> void:
	if _state != CoreState.DASH:
		return
	if is_outside_visual_safe_rect():
		global_position -= _dash_direction * 4.0
		clamp_to_arena()
		velocity = Vector2.ZERO
		_start_recovery(0.72)
		return
	_dash_travelled += maxf(actual_displacement.dot(_dash_direction), 0.0)
	if _dash_travelled >= _dash_length:
		_start_recovery(0.72)


func _uses_soft_separation() -> bool:
	return false


func _clear_telegraph() -> void:
	if is_instance_valid(_telegraph):
		_telegraph.queue_free()
	_telegraph = null


func _before_death(_hit_data: HitData) -> void:
	_clear_telegraph()
	_cancel_clone_replenishment()
	for line in _absorb_lines:
		if is_instance_valid(line):
			line.queue_free()
	_absorb_lines.clear()
	_absorb_targets.clear()
	var wave_manager := get_tree().get_first_node_in_group("wave_manager") as WaveManager
	if wave_manager != null:
		wave_manager.cancel_deferred_spawns_for_source(self)
	for clone in get_tree().get_nodes_in_group("boss_clone"):
		clone.queue_free()
	for bullet in get_tree().get_nodes_in_group("enemy_bullet"):
		bullet.queue_free()


func _on_deferred_clone_spawned(
	_enemy: EnemyBase,
	spawn_context: StringName,
	source_instance_id: int
) -> void:
	if source_instance_id != get_instance_id() or not spawn_context in [
		&"core_clone",
		&"core_clone_enraged",
	]:
		return
	_pending_clone_requests = maxi(_pending_clone_requests - 1, 0)
	if get_health_ratio() <= 0.40 and _enemy is ProliferationClone:
		(_enemy as ProliferationClone).set_enraged()
	_absorb_timer = 10.0
	if (
		_get_clone_cap() - _get_clones().size() - _pending_clone_requests > 0
		and _clone_replenish_remaining < 0.0
	):
		_start_clone_replenishment(CLONE_REPLENISH_DELAY)


func _on_deferred_clone_cancelled(
	spawn_context: StringName,
	source_instance_id: int
) -> void:
	if source_instance_id != get_instance_id() or not spawn_context in [
		&"core_clone",
		&"core_clone_enraged",
	]:
		return
	_pending_clone_requests = maxi(_pending_clone_requests - 1, 0)
	if is_alive() and get_health_ratio() > 0.20:
		_start_clone_replenishment(CLONE_REPLENISH_DELAY)


func _on_wave_enemy_killed(enemy: EnemyBase, _hit_data: HitData) -> void:
	if not is_alive() or not enemy is ProliferationClone:
		return
	_start_clone_replenishment(CLONE_REPLENISH_DELAY, true)


func _play_audio(event_id: StringName) -> void:
	var audio := get_tree().get_first_node_in_group("audio_manager")
	if audio != null and audio.has_method("play_game_sfx"):
		audio.play_game_sfx(event_id, global_position, 1.0)
