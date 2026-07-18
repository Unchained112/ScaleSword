class_name ChargerEnemy
extends EnemyBase

const TELEGRAPH_SCENE := preload("res://combat/dash_telegraph.tscn")

enum ChargeState {
	CHASE,
	WINDUP,
	DASH,
	RECOVERY,
}

@export var dash_length := 58.0
@export var dash_speed := 125.0
@export var dash_damage := 18.0
@export var windup_duration := 0.55
@export var recovery_duration := 0.65
@export var dash_cooldown := 1.4
@export var trigger_distance := 82.0
@export var maximum_charge_scale := 1.15
@export var segmented_telegraph := false
@export var path_width := 8.0

var _charge_state := ChargeState.CHASE
var _state_timer := 0.0
var _cooldown_remaining := 0.65
var _dash_direction := Vector2.RIGHT
var _dash_travelled := 0.0
var _base_contact_damage := 10.0
var _telegraph: DashTelegraph
var _dash_hit_player := false


func _enemy_ready() -> void:
	_base_contact_damage = contact_damage


func _tick_behavior(delta: float) -> void:
	var player := get_target()
	if player == null:
		return
	_cooldown_remaining = maxf(_cooldown_remaining - delta, 0.0)
	match _charge_state:
		ChargeState.CHASE:
			var to_player := player.global_position - global_position
			var distance := to_player.length()
			if distance > 0.01:
				set_desired_velocity(to_player.normalized() * move_speed)
			if _cooldown_remaining <= 0.0 and distance <= trigger_distance:
				_begin_windup(to_player.normalized())
		ChargeState.WINDUP:
			_state_timer = maxf(_state_timer - delta, 0.0)
			var progress := 1.0 - _state_timer / windup_duration
			set_desired_velocity(Vector2.ZERO)
			set_charge_visual(progress, maximum_charge_scale)
			if is_instance_valid(_telegraph) and segmented_telegraph:
				_telegraph.set_progress(progress)
			if _state_timer <= 0.0:
				_begin_dash()
		ChargeState.DASH:
			set_desired_velocity(_dash_direction * dash_speed)
		ChargeState.RECOVERY:
			set_desired_velocity(Vector2.ZERO)
			_state_timer = maxf(_state_timer - delta, 0.0)
			if _state_timer <= 0.0:
				_charge_state = ChargeState.CHASE
				_cooldown_remaining = dash_cooldown


func _begin_windup(direction: Vector2) -> void:
	_charge_state = ChargeState.WINDUP
	_state_timer = windup_duration
	_dash_direction = direction if direction.length_squared() > 0.0001 else Vector2.RIGHT
	_telegraph = TELEGRAPH_SCENE.instantiate() as DashTelegraph
	add_child(_telegraph)
	_telegraph.position = Vector2.ZERO
	_telegraph.configure(_dash_direction, dash_length, path_width, segmented_telegraph)


func _begin_dash() -> void:
	_charge_state = ChargeState.DASH
	_dash_travelled = 0.0
	_dash_hit_player = false
	if is_instance_valid(_telegraph):
		_telegraph.queue_free()
	_charge_visual_active = true
	visual_root.rotation = _dash_direction.angle()
	visual_root.skew = 0.0
	visual_root.scale = Vector2(1.30, 0.74)
	var audio := get_tree().get_first_node_in_group("audio_manager")
	if audio != null and audio.has_method("play_game_sfx"):
		audio.play_game_sfx(&"enemy_dash", global_position, 1.0)


func _begin_recovery() -> void:
	_charge_state = ChargeState.RECOVERY
	_state_timer = recovery_duration
	contact_damage = 0.0
	clear_charge_visual()


func _process_contact_collisions() -> void:
	if _charge_state == ChargeState.CHASE:
		contact_damage = _base_contact_damage
		super._process_contact_collisions()
		return
	if _charge_state != ChargeState.DASH:
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
					dash_damage,
					direction * 38.0,
					self,
					1.0,
					get_instance_id()
				))
			var away := global_position - player.global_position
			if away.length_squared() < 0.0001:
				away = -_dash_direction
			global_position += away.normalized() * 10.0
		else:
			global_position += collision.get_normal() * 3.5
		clamp_to_arena()
		_begin_recovery()
		velocity = Vector2.ZERO
		return


func _after_motion(_delta: float, actual_displacement: Vector2) -> void:
	if _charge_state != ChargeState.DASH:
		return
	if is_outside_visual_safe_rect():
		global_position -= _dash_direction * 3.5
		clamp_to_arena()
		velocity = Vector2.ZERO
		_begin_recovery()
		return
	_dash_travelled += maxf(actual_displacement.dot(_dash_direction), 0.0)
	if _dash_travelled >= dash_length:
		_begin_recovery()


func _uses_soft_separation() -> bool:
	return _charge_state == ChargeState.CHASE
