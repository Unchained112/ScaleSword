class_name SplitterEnemy
extends EnemyBase

const CHILD_SCENE := preload("res://actors/enemies/splitter_child.tscn")


func _tick_behavior(_delta: float) -> void:
	var player := get_target()
	if player == null:
		return
	var to_player := player.global_position - global_position
	if to_player.length_squared() > 0.25:
		set_desired_velocity(to_player.normalized() * move_speed)


func _before_death(hit_data: HitData) -> void:
	var required_tier := CombatMath.SizeTier.COLOSSAL
	if (
		hit_data.source is PlayerController
		and (hit_data.source as PlayerController).get_run_modifiers().has(&"split_suppression")
	):
		required_tier = CombatMath.SizeTier.LARGE
	if CombatMath.get_size_tier(hit_data.charge_progress) >= required_tier:
		return
	var spawn_parent := get_parent()
	if not is_instance_valid(spawn_parent):
		return
	var wave_manager := get_tree().get_first_node_in_group("wave_manager") as WaveManager
	for side in [-1.0, 1.0]:
		var spawn_position := global_position + Vector2(5.0 * side, 0.0)
		if (
			wave_manager != null
			and wave_manager.request_deferred_enemy_spawn(
				CHILD_SCENE,
				spawn_position,
				&"split"
			)
		):
			continue
		var child := CHILD_SCENE.instantiate() as EnemyBase
		child.position = spawn_parent.to_local(spawn_position)
		spawn_parent.add_child.call_deferred(child)
