class_name EnemyBase
extends CharacterBody2D

signal health_changed(current_health: float, maximum_health: float)
signal enemy_died(enemy: EnemyBase, hit_data: HitData)

const CONTACT_SEPARATION_DISTANCE := 6.0
const CONTACT_RECOIL_DURATION := 0.14
const CONTACT_RECOIL_SPEED := 28.0

@export var max_health := 35.0
@export var move_speed := 30.0
@export var contact_damage := 10.0
@export_range(0.0, 0.95) var knockback_resistance := 0.0
@export var contact_cooldown := 0.65
@export var is_boss := false
@export var boss_name_key: StringName = &""
@export var visual_safe_margin := 6.0

@onready var collision_shape: CollisionShape2D = $CollisionShape2D
@onready var visual_root: Node2D = $VisualRoot
@onready var sprite: Sprite2D = $VisualRoot/Sprite2D
@onready var health_bar: ProgressBar = $HealthBar

var _target: PlayerController
var _health := 0.0
var _alive := true
var _desired_velocity := Vector2.ZERO
var _knockback_velocity := Vector2.ZERO
var _contact_cooldown_remaining := 0.0
var _motion_phase := 0.0
var _charge_visual_active := false
var _flash_tween: Tween
var _sprite_base_scale := Vector2.ONE
var _visual_base_scale := Vector2.ONE
var _spawn_locked := false
var _arena_bounds: ArenaBounds
var _footstep_distance := 0.0
var _contact_recoil_remaining := 0.0
var _contact_recoil_direction := Vector2.ZERO


func _ready() -> void:
	add_to_group("enemy")
	_health = max_health
	_sprite_base_scale = sprite.scale
	_visual_base_scale = visual_root.scale
	health_bar.max_value = max_health
	health_bar.value = _health
	_target = get_tree().get_first_node_in_group("player") as PlayerController
	_arena_bounds = get_tree().get_first_node_in_group("arena_bounds") as ArenaBounds
	_enemy_ready()


func _physics_process(delta: float) -> void:
	if not _alive or _spawn_locked:
		return
	if not is_instance_valid(_target):
		_target = get_tree().get_first_node_in_group("player") as PlayerController
	_contact_cooldown_remaining = maxf(_contact_cooldown_remaining - delta, 0.0)
	_contact_recoil_remaining = maxf(_contact_recoil_remaining - delta, 0.0)
	_desired_velocity = Vector2.ZERO
	_tick_behavior(delta)
	if _contact_recoil_remaining > 0.0:
		_desired_velocity = _contact_recoil_direction * CONTACT_RECOIL_SPEED
	else:
		_apply_soft_separation()
	velocity = _desired_velocity + _knockback_velocity
	var position_before_move := global_position
	move_and_slide()
	_process_contact_collisions()
	_after_motion(delta, global_position - position_before_move)
	clamp_to_arena()
	_update_footstep_dust(global_position.distance_to(position_before_move))
	_knockback_velocity = _knockback_velocity.move_toward(Vector2.ZERO, 180.0 * delta)
	_update_motion_visual(delta)


func take_hit(hit_data: HitData) -> bool:
	if not _alive or _spawn_locked:
		return false
	_health = maxf(_health - hit_data.amount, 0.0)
	health_bar.value = _health
	health_changed.emit(_health, max_health)
	_knockback_velocity += hit_data.knockback * (1.0 - knockback_resistance)
	_play_hit_flash()
	var feedback := get_tree().get_first_node_in_group("feedback_manager") as FeedbackManager
	if feedback != null:
		feedback.spawn_hit_particles(global_position, hit_data.size_factor)
	if _health <= 0.0:
		_before_death(hit_data)
		_die(hit_data)
	return true


func is_alive() -> bool:
	return _alive


func get_health() -> float:
	return _health


func get_max_health() -> float:
	return max_health


func get_health_ratio() -> float:
	return _health / maxf(max_health, 1.0)


func heal(amount: float) -> float:
	if not _alive or amount <= 0.0:
		return 0.0
	var previous := _health
	_health = minf(_health + amount, max_health)
	health_bar.value = _health
	health_changed.emit(_health, max_health)
	return _health - previous


func get_target() -> PlayerController:
	return _target


func set_desired_velocity(new_velocity: Vector2) -> void:
	_desired_velocity = new_velocity


func clamp_to_arena() -> void:
	if not is_instance_valid(_arena_bounds):
		_arena_bounds = get_tree().get_first_node_in_group("arena_bounds") as ArenaBounds
	if _arena_bounds != null:
		global_position = _arena_bounds.clamp_position(global_position, visual_safe_margin)


func get_arena_safe_rect() -> Rect2:
	if not is_instance_valid(_arena_bounds):
		_arena_bounds = get_tree().get_first_node_in_group("arena_bounds") as ArenaBounds
	if _arena_bounds == null:
		return Rect2(-100000.0, -100000.0, 200000.0, 200000.0)
	return _arena_bounds.get_safe_rect(visual_safe_margin)


func is_outside_visual_safe_rect() -> bool:
	return not get_arena_safe_rect().grow(0.01).has_point(global_position)


func begin_spawn_intro(duration := 0.40) -> void:
	_spawn_locked = true
	collision_shape.set_deferred("disabled", true)
	visual_root.modulate.a = 0.15
	var target_scale := _visual_base_scale
	visual_root.scale = target_scale * 0.25
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(visual_root, "scale", target_scale, duration).set_trans(Tween.TRANS_BACK)
	tween.tween_property(visual_root, "modulate:a", 1.0, duration)
	await tween.finished
	if is_inside_tree() and _alive:
		_spawn_locked = false
		collision_shape.set_deferred("disabled", false)


func apply_external_pull(target_position: Vector2, distance: float) -> void:
	var offset := target_position - global_position
	if offset.length_squared() <= 0.01:
		return
	_knockback_velocity += offset.normalized() * distance * 6.0


func set_charge_visual(progress: float, maximum_scale: float) -> void:
	_charge_visual_active = true
	var safe_progress := clampf(progress, 0.0, 1.0)
	var scale_value := lerpf(1.0, maximum_scale, safe_progress)
	visual_root.scale = _visual_base_scale * scale_value
	visual_root.skew = sin(Time.get_ticks_msec() * 0.035) * 0.07 * safe_progress
	var material := sprite.material as ShaderMaterial
	if material != null:
		material.set_shader_parameter("charge_amount", safe_progress)


func clear_charge_visual() -> void:
	_charge_visual_active = false
	var material := sprite.material as ShaderMaterial
	if material != null:
		material.set_shader_parameter("charge_amount", 0.0)
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(visual_root, "scale", _visual_base_scale, 0.12)
	tween.tween_property(visual_root, "skew", 0.0, 0.12)


func _enemy_ready() -> void:
	pass


func _tick_behavior(_delta: float) -> void:
	pass


func _before_death(_hit_data: HitData) -> void:
	pass


func _after_motion(_delta: float, _actual_displacement: Vector2) -> void:
	pass


func _uses_soft_separation() -> bool:
	return true


func _die(hit_data: HitData) -> void:
	if not _alive:
		return
	_alive = false
	velocity = Vector2.ZERO
	collision_shape.set_deferred("disabled", true)
	if is_instance_valid(hit_data.source) and hit_data.source.has_method("notify_enemy_killed"):
		hit_data.source.notify_enemy_killed(hit_data)
	var feedback := get_tree().get_first_node_in_group("feedback_manager") as FeedbackManager
	if feedback != null:
		feedback.spawn_enemy_death_particles(global_position, visual_root.global_scale.x, is_boss)
	if is_boss and feedback != null:
		await feedback.play_boss_death_sequence(global_position)
	if not is_inside_tree():
		return
	enemy_died.emit(self, hit_data)
	queue_free()


func _process_contact_collisions() -> void:
	for collision_index in get_slide_collision_count():
		var collision := get_slide_collision(collision_index)
		var player := collision.get_collider() as PlayerController
		if player == null:
			continue
		var toward_player := (player.global_position - global_position).normalized()
		if toward_player.length_squared() < 0.0001:
			toward_player = velocity.normalized()
		if toward_player.length_squared() < 0.0001:
			toward_player = Vector2.RIGHT
		if _contact_cooldown_remaining <= 0.0 and contact_damage > 0.0:
			var hit := HitData.new(
				contact_damage,
				toward_player * 32.0,
				self,
				1.0,
				get_instance_id()
			)
			if player.take_hit(hit):
				_contact_cooldown_remaining = contact_cooldown
		resolve_player_contact(player, toward_player)
		break


func resolve_player_contact(
	_player: PlayerController,
	toward_player: Vector2,
	separation_distance := CONTACT_SEPARATION_DISTANCE
) -> void:
	var safe_direction := toward_player.normalized()
	if safe_direction.length_squared() < 0.0001:
		safe_direction = Vector2.RIGHT
	_contact_recoil_direction = -safe_direction
	_contact_recoil_remaining = CONTACT_RECOIL_DURATION
	global_position += _contact_recoil_direction * separation_distance
	clamp_to_arena()


func _play_hit_flash() -> void:
	if is_instance_valid(_flash_tween):
		_flash_tween.kill()
	var material := sprite.material as ShaderMaterial
	if material != null:
		material.set_shader_parameter("flash_amount", 1.0)
	sprite.scale = _sprite_base_scale * 1.40
	_flash_tween = create_tween()
	_flash_tween.tween_interval(0.055)
	if material != null:
		_flash_tween.tween_method(
			func(value: float) -> void:
				material.set_shader_parameter("flash_amount", value),
			1.0,
			0.0,
			0.15
		)
	_flash_tween.parallel().tween_property(sprite, "scale", _sprite_base_scale, 0.15)


func _update_motion_visual(delta: float) -> void:
	if _charge_visual_active:
		return
	if _desired_velocity.length_squared() > 1.0:
		_motion_phase += _desired_velocity.length() * delta * 0.34
		var wave := sin(_motion_phase)
		visual_root.rotation = lerp_angle(
			visual_root.rotation,
			wave * deg_to_rad(3.0),
			minf(delta * 16.0, 1.0)
		)
		visual_root.skew = lerpf(visual_root.skew, wave * 0.035, minf(delta * 16.0, 1.0))
		visual_root.scale = visual_root.scale.lerp(
			_visual_base_scale * Vector2(1.0, 1.0 + absf(wave) * 0.04),
			minf(delta * 16.0, 1.0)
		)
	else:
		visual_root.rotation = lerp_angle(visual_root.rotation, 0.0, minf(delta * 12.0, 1.0))
		visual_root.skew = lerpf(visual_root.skew, 0.0, minf(delta * 12.0, 1.0))
		visual_root.scale = visual_root.scale.lerp(
			_visual_base_scale,
			minf(delta * 12.0, 1.0)
		)


func _apply_soft_separation() -> void:
	if not _uses_soft_separation() or _desired_velocity.length_squared() <= 0.01:
		return
	var separation := Vector2.ZERO
	for node in get_tree().get_nodes_in_group("enemy"):
		var other := node as EnemyBase
		if other == null or other == self or not other.is_alive():
			continue
		var offset := global_position - other.global_position
		var distance_squared := offset.length_squared()
		if distance_squared >= 100.0:
			continue
		if distance_squared < 0.01:
			var angle := float((get_instance_id() + other.get_instance_id()) % 16) / 16.0 * TAU
			offset = Vector2.RIGHT.rotated(angle)
			distance_squared = 1.0
		var distance := sqrt(distance_squared)
		separation += offset / distance * (1.0 - distance / 10.0)
	if separation.length_squared() > 0.01:
		_desired_velocity += separation.normalized() * minf(separation.length() * 12.0, 12.0)


func _update_footstep_dust(distance_moved: float) -> void:
	if distance_moved <= 0.01 or _spawn_locked:
		return
	_footstep_distance += distance_moved
	if _footstep_distance < 7.0:
		return
	_footstep_distance = fmod(_footstep_distance, 7.0)
	var feedback := get_tree().get_first_node_in_group("feedback_manager") as FeedbackManager
	if feedback != null:
		feedback.spawn_footstep_dust(
			global_position + Vector2(0.0, 3.0),
			Color(0.52, 0.48, 0.42, 0.62),
			clampf(visual_root.global_scale.x, 0.7, 2.0)
		)
