class_name ShooterEnemy
extends EnemyBase

const BULLET_SCENE := preload("res://actors/enemies/enemy_bullet.tscn")
const PREFERRED_DISTANCE := 66.0
const FIRE_INTERVAL := 1.55
const FIRE_WINDUP := 0.35

var _fire_timer := 0.8
var _windup_remaining := 0.0
var _strafe_sign := 1.0


func _tick_behavior(delta: float) -> void:
	var player := get_target()
	if player == null:
		return
	if _windup_remaining > 0.0:
		_windup_remaining = maxf(_windup_remaining - delta, 0.0)
		set_desired_velocity(Vector2.ZERO)
		set_charge_visual(1.0 - _windup_remaining / FIRE_WINDUP, 1.14)
		if _windup_remaining <= 0.0:
			_fire()
			clear_charge_visual()
			_fire_timer = FIRE_INTERVAL
		return

	_fire_timer -= delta
	var to_player := player.global_position - global_position
	var distance := to_player.length()
	var direction := to_player.normalized() if distance > 0.01 else Vector2.RIGHT
	var radial := Vector2.ZERO
	if distance > PREFERRED_DISTANCE + 10.0:
		radial = direction
	elif distance < PREFERRED_DISTANCE - 10.0:
		radial = -direction
	var tangent := direction.orthogonal() * _strafe_sign * 0.38
	set_desired_velocity((radial + tangent).normalized() * move_speed)
	if _fire_timer <= 0.0 and distance < 120.0:
		_windup_remaining = FIRE_WINDUP
		_strafe_sign *= -1.0


func _fire() -> void:
	var player := get_target()
	if player == null:
		return
	var bullet := BULLET_SCENE.instantiate() as EnemyBullet
	bullet.global_position = global_position
	get_parent().add_child(bullet)
	bullet.global_position = global_position
	bullet.launch(player.global_position - global_position)
	var audio := get_tree().get_first_node_in_group("audio_manager")
	if audio != null and audio.has_method("play_game_sfx"):
		audio.play_game_sfx(&"enemy_spell", global_position, randf_range(0.96, 1.04))
