class_name SkirmisherEnemy
extends EnemyBase

const BULLET_SCENE := preload("res://actors/enemies/enemy_bullet.tscn")
const TELEGRAPH_SCENE := preload("res://combat/dash_telegraph.tscn")

enum SkirmishState {
	ORBIT,
	DASH_WINDUP,
	DASH,
	SHOOT_WINDUP,
}

const DASH_WINDUP := 0.32
const DASH_DURATION := 0.18
const SHOOT_WINDUP := 0.28

var _state := SkirmishState.ORBIT
var _state_timer := 0.0
var _action_timer := 1.2
var _orbit_sign := 1.0
var _dash_direction := Vector2.RIGHT
var _telegraph: DashTelegraph


func _tick_behavior(delta: float) -> void:
	var player := get_target()
	if player == null:
		return
	match _state:
		SkirmishState.ORBIT:
			_action_timer -= delta
			var to_player := player.global_position - global_position
			var distance := to_player.length()
			var direction := to_player.normalized() if distance > 0.01 else Vector2.RIGHT
			var radial := direction * clampf((distance - 70.0) / 24.0, -1.0, 1.0)
			var tangent := direction.orthogonal() * _orbit_sign
			set_desired_velocity((tangent + radial * 0.75).normalized() * move_speed)
			if _action_timer <= 0.0:
				_begin_dash_windup(tangent.normalized())
		SkirmishState.DASH_WINDUP:
			_state_timer = maxf(_state_timer - delta, 0.0)
			set_desired_velocity(Vector2.ZERO)
			set_charge_visual(1.0 - _state_timer / DASH_WINDUP, 1.12)
			if _state_timer <= 0.0:
				_state = SkirmishState.DASH
				_state_timer = DASH_DURATION
				if is_instance_valid(_telegraph):
					_telegraph.queue_free()
		SkirmishState.DASH:
			_state_timer = maxf(_state_timer - delta, 0.0)
			set_desired_velocity(_dash_direction * 112.0)
			_charge_visual_active = true
			visual_root.rotation = _dash_direction.angle()
			visual_root.scale = Vector2(1.22, 0.78)
			if _state_timer <= 0.0:
				_state = SkirmishState.SHOOT_WINDUP
				_state_timer = SHOOT_WINDUP
				clear_charge_visual()
		SkirmishState.SHOOT_WINDUP:
			_state_timer = maxf(_state_timer - delta, 0.0)
			set_desired_velocity(Vector2.ZERO)
			set_charge_visual(1.0 - _state_timer / SHOOT_WINDUP, 1.10)
			if _state_timer <= 0.0:
				_fire_spread()
				clear_charge_visual()
				_state = SkirmishState.ORBIT
				_action_timer = 2.0
				_orbit_sign *= -1.0


func _begin_dash_windup(direction: Vector2) -> void:
	_state = SkirmishState.DASH_WINDUP
	_state_timer = DASH_WINDUP
	_dash_direction = direction if direction.length_squared() > 0.0001 else Vector2.RIGHT
	_telegraph = TELEGRAPH_SCENE.instantiate() as DashTelegraph
	add_child(_telegraph)
	_telegraph.configure(_dash_direction, 24.0, 7.0, false)


func _fire_spread() -> void:
	var player := get_target()
	if player == null:
		return
	var center_direction := (player.global_position - global_position).normalized()
	for angle_degrees in [-18.0, 0.0, 18.0]:
		var bullet := BULLET_SCENE.instantiate() as EnemyBullet
		bullet.position = position
		get_parent().add_child(bullet)
		bullet.global_position = global_position
		bullet.launch(center_direction.rotated(deg_to_rad(angle_degrees)), 68.0, 8.0)
	var audio := get_tree().get_first_node_in_group("audio_manager")
	if audio != null and audio.has_method("play_game_sfx"):
		audio.play_game_sfx(&"enemy_spell", global_position, 1.08)
