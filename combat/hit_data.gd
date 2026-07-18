class_name HitData
extends RefCounted

var amount: float
var knockback: Vector2
var source: Node
var size_factor: float
var attack_id: int
var charge_progress: float


func _init(
	p_amount: float,
	p_knockback: Vector2,
	p_source: Node,
	p_size_factor: float,
	p_attack_id: int,
	p_charge_progress := 0.0
) -> void:
	amount = p_amount
	knockback = p_knockback
	source = p_source
	size_factor = p_size_factor
	attack_id = p_attack_id
	charge_progress = clampf(p_charge_progress, 0.0, 1.0)
