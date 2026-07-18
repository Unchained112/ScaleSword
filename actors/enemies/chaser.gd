class_name ChaserEnemy
extends EnemyBase


func _tick_behavior(_delta: float) -> void:
	var player := get_target()
	if player == null:
		return
	var direction := player.global_position - global_position
	if direction.length_squared() > 0.25:
		set_desired_velocity(direction.normalized() * move_speed)
