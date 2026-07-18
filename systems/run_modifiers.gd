class_name RunModifiers
extends RefCounted

signal changed

const BASE_MOVE_SPEED := 70.0
const BASE_MAX_HEALTH := 100.0
const BASE_CHARGE_TIME := 1.6
const BASE_MAX_SIZE := 3.0
const BASE_DAMAGE := 20.0
const BASE_DODGE_COOLDOWN := 0.85
const BLOOD_ANCHOR_MOVE_MULTIPLIER := 0.25

var stacks: Dictionary = {}


func reset() -> void:
	stacks.clear()
	changed.emit()


func add_upgrade(upgrade_id: StringName) -> void:
	stacks[upgrade_id] = get_upgrade_stack(upgrade_id) + 1
	changed.emit()


func get_upgrade_stack(upgrade_id: StringName) -> int:
	return int(stacks.get(upgrade_id, 0))


func has(upgrade_id: StringName) -> bool:
	return get_upgrade_stack(upgrade_id) > 0


func get_move_speed() -> float:
	return BASE_MOVE_SPEED * (1.0 + 0.10 * get_upgrade_stack(&"swift_steps"))


func get_max_health() -> float:
	return BASE_MAX_HEALTH + 20.0 * get_upgrade_stack(&"sturdy_body")


func get_full_charge_time() -> float:
	var result := BASE_CHARGE_TIME * pow(0.88, get_upgrade_stack(&"rapid_growth"))
	if has(&"compressed_growth"):
		result /= 1.60
	return result


func get_max_size() -> float:
	var result := BASE_MAX_SIZE + 0.25 * get_upgrade_stack(&"scale_breakthrough")
	if has(&"titan_worship"):
		result += 0.5
	if has(&"compressed_growth"):
		result -= 0.5
	return maxf(result, 2.0)


func get_base_damage() -> float:
	return BASE_DAMAGE * pow(1.15, get_upgrade_stack(&"sharpened_edge"))


func get_swing_duration_multiplier() -> float:
	return pow(0.90, get_upgrade_stack(&"flexible_wrist"))


func get_knockback_multiplier() -> float:
	return pow(1.20, get_upgrade_stack(&"weight_impact"))


func get_dodge_cooldown() -> float:
	return BASE_DODGE_COOLDOWN * pow(0.88, get_upgrade_stack(&"quick_roll"))


func get_max_dodge_charges() -> int:
	return 2 if has(&"dodge_reserve") else 1


func apply_charge_movement_modifier(
	base_multiplier: float,
	progress: float,
	apply_blood_anchor := true
) -> float:
	var result := base_multiplier
	if has(&"heavy_stride") and CombatMath.is_tier_at_least(progress, CombatMath.SizeTier.LARGE):
		result = lerpf(result, 1.0, 0.35)
	if (
		apply_blood_anchor
		and has(&"blood_anchor")
		and CombatMath.is_tier_at_least(progress, CombatMath.SizeTier.COLOSSAL)
	):
		return minf(result, BLOOD_ANCHOR_MOVE_MULTIPLIER)
	return result
