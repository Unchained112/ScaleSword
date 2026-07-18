class_name SplitterChildEnemy
extends EnemyBase


func _tick_behavior(_delta: float) -> void:
	var player := get_target()
	if player == null:
		return
	var to_player := player.global_position - global_position
	if to_player.length_squared() > 0.25:
		set_desired_velocity(to_player.normalized() * move_speed)
