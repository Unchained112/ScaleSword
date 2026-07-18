class_name WaveDefinition
extends RefCounted

var round_index: int
var threat_budget: int
var enemy_ids: Array[StringName]
var batch_size: int
var max_alive: int
var boss_id: StringName


func _init(
	p_round_index: int,
	p_threat_budget: int,
	p_enemy_ids: Array[StringName],
	p_batch_size: int,
	p_max_alive: int,
	p_boss_id: StringName = &""
) -> void:
	round_index = p_round_index
	threat_budget = p_threat_budget
	enemy_ids = p_enemy_ids
	batch_size = p_batch_size
	max_alive = p_max_alive
	boss_id = p_boss_id


func is_boss_round() -> bool:
	return not boss_id.is_empty()
