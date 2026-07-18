class_name UpgradeManager
extends Node

signal upgrade_choices_ready(choices: Array[UpgradeDefinition])
signal upgrade_selected(upgrade_id: StringName)

var modifiers := RunModifiers.new()
var _definitions: Array[UpgradeDefinition] = []
var _definition_by_id: Dictionary = {}
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_definitions()


func reset_for_run(seed_value := 0) -> void:
	modifiers = RunModifiers.new()
	if seed_value == 0:
		_rng.randomize()
	else:
		_rng.seed = seed_value


func get_definition(upgrade_id: StringName) -> UpgradeDefinition:
	return _definition_by_id.get(upgrade_id) as UpgradeDefinition


func get_all_definitions() -> Array[UpgradeDefinition]:
	return _definitions.duplicate()


func get_stack(upgrade_id: StringName) -> int:
	return modifiers.get_upgrade_stack(upgrade_id)


func create_choices(count := 3) -> Array[UpgradeDefinition]:
	var eligible: Array[UpgradeDefinition] = []
	for definition in _definitions:
		if (
			modifiers.get_upgrade_stack(definition.id) < definition.max_stacks
			and _prerequisites_met(definition)
		):
			eligible.append(definition)
	eligible.shuffle()
	var result: Array[UpgradeDefinition] = []
	var used_categories: Dictionary = {}
	for definition in eligible:
		if result.size() >= count:
			break
		if not used_categories.has(definition.category_key):
			result.append(definition)
			used_categories[definition.category_key] = true
	for definition in eligible:
		if result.size() >= count:
			break
		if not result.has(definition):
			result.append(definition)
	upgrade_choices_ready.emit(result)
	return result


func select_upgrade(upgrade_id: StringName) -> bool:
	var definition := get_definition(upgrade_id)
	if definition == null:
		return false
	if modifiers.get_upgrade_stack(upgrade_id) >= definition.max_stacks:
		return false
	if not _prerequisites_met(definition):
		return false
	modifiers.add_upgrade(upgrade_id)
	upgrade_selected.emit(upgrade_id)
	return true


func _add(
	id: StringName,
	title_key: StringName,
	description_key: StringName,
	category_key: StringName,
	max_stacks: int,
	icon_code: String,
	prerequisite_ids: Array[StringName] = []
) -> void:
	var definition := UpgradeDefinition.new(
		id, title_key, description_key, category_key, max_stacks, icon_code, prerequisite_ids
	)
	_definitions.append(definition)
	_definition_by_id[id] = definition


func _build_definitions() -> void:
	if not _definitions.is_empty():
		return
	_add(&"swift_steps", &"UPGRADE_SWIFT_STEPS_TITLE", &"UPGRADE_SWIFT_STEPS_DESC", &"CATEGORY_GENERAL", 4, "SP")
	_add(&"sturdy_body", &"UPGRADE_STURDY_BODY_TITLE", &"UPGRADE_STURDY_BODY_DESC", &"CATEGORY_SURVIVAL", 4, "HP")
	_add(&"rapid_growth", &"UPGRADE_RAPID_GROWTH_TITLE", &"UPGRADE_RAPID_GROWTH_DESC", &"CATEGORY_HEAVY", 4, "RG")
	_add(&"scale_breakthrough", &"UPGRADE_SCALE_BREAKTHROUGH_TITLE", &"UPGRADE_SCALE_BREAKTHROUGH_DESC", &"CATEGORY_HEAVY", 3, "S+")
	_add(&"sharpened_edge", &"UPGRADE_SHARPENED_EDGE_TITLE", &"UPGRADE_SHARPENED_EDGE_DESC", &"CATEGORY_GENERAL", 4, "DM")
	_add(&"flexible_wrist", &"UPGRADE_FLEXIBLE_WRIST_TITLE", &"UPGRADE_FLEXIBLE_WRIST_DESC", &"CATEGORY_LIGHT", 4, "FW")
	_add(&"weight_impact", &"UPGRADE_WEIGHT_IMPACT_TITLE", &"UPGRADE_WEIGHT_IMPACT_DESC", &"CATEGORY_HEAVY", 3, "KB")
	_add(&"quick_roll", &"UPGRADE_QUICK_ROLL_TITLE", &"UPGRADE_QUICK_ROLL_DESC", &"CATEGORY_SURVIVAL", 3, "DR")
	_add(&"perfect_scale", &"UPGRADE_PERFECT_SCALE_TITLE", &"UPGRADE_PERFECT_SCALE_DESC", &"CATEGORY_HEAVY", 1, "PS")
	_add(&"ground_quake", &"UPGRADE_GROUND_QUAKE_TITLE", &"UPGRADE_GROUND_QUAKE_DESC", &"CATEGORY_HEAVY", 1, "GQ")
	_add(&"double_slash", &"UPGRADE_DOUBLE_SLASH_TITLE", &"UPGRADE_DOUBLE_SLASH_DESC", &"CATEGORY_GENERAL", 1, "DS")
	_add(&"bullet_breaker", &"UPGRADE_BULLET_BREAKER_TITLE", &"UPGRADE_BULLET_BREAKER_DESC", &"CATEGORY_SURVIVAL", 1, "BB")
	_add(&"weight_transfer", &"UPGRADE_WEIGHT_TRANSFER_TITLE", &"UPGRADE_WEIGHT_TRANSFER_DESC", &"CATEGORY_HEAVY", 1, "WT")
	_add(&"growing_momentum", &"UPGRADE_GROWING_MOMENTUM_TITLE", &"UPGRADE_GROWING_MOMENTUM_DESC", &"CATEGORY_HEAVY", 1, "GM")
	_add(&"split_suppression", &"UPGRADE_SPLIT_SUPPRESSION_TITLE", &"UPGRADE_SPLIT_SUPPRESSION_DESC", &"CATEGORY_HEAVY", 1, "SS")
	_add(&"light_swordplay", &"UPGRADE_LIGHT_SWORDPLAY_TITLE", &"UPGRADE_LIGHT_SWORDPLAY_DESC", &"CATEGORY_LIGHT", 1, "LS")
	_add(&"combo_edge", &"UPGRADE_COMBO_EDGE_TITLE", &"UPGRADE_COMBO_EDGE_DESC", &"CATEGORY_LIGHT", 1, "CE")
	_add(&"charging_armor", &"UPGRADE_CHARGING_ARMOR_TITLE", &"UPGRADE_CHARGING_ARMOR_DESC", &"CATEGORY_SURVIVAL", 1, "CA")
	_add(&"titan_worship", &"UPGRADE_TITAN_WORSHIP_TITLE", &"UPGRADE_TITAN_WORSHIP_DESC", &"CATEGORY_HEAVY", 1, "TW")
	_add(&"arc_extension", &"UPGRADE_ARC_EXTENSION_TITLE", &"UPGRADE_ARC_EXTENSION_DESC", &"CATEGORY_GENERAL", 1, "AE")
	_add(&"gravity_slash", &"UPGRADE_GRAVITY_SLASH_TITLE", &"UPGRADE_GRAVITY_SLASH_DESC", &"CATEGORY_HEAVY", 1, "GS")
	_add(&"desperate_charge", &"UPGRADE_DESPERATE_CHARGE_TITLE", &"UPGRADE_DESPERATE_CHARGE_DESC", &"CATEGORY_SURVIVAL", 1, "DC")
	_add(&"heavy_stride", &"UPGRADE_HEAVY_STRIDE_TITLE", &"UPGRADE_HEAVY_STRIDE_DESC", &"CATEGORY_HEAVY", 1, "HS")
	_add(&"compressed_growth", &"UPGRADE_COMPRESSED_GROWTH_TITLE", &"UPGRADE_COMPRESSED_GROWTH_DESC", &"CATEGORY_HEAVY", 1, "CG")
	_add(&"dodge_reserve", &"UPGRADE_DODGE_RESERVE_TITLE", &"UPGRADE_DODGE_RESERVE_DESC", &"CATEGORY_SURVIVAL", 1, "D2")
	_add(
		&"blood_anchor",
		&"UPGRADE_BLOOD_ANCHOR_TITLE",
		&"UPGRADE_BLOOD_ANCHOR_DESC",
		&"CATEGORY_SURVIVAL",
		1,
		"BA",
		[&"charging_armor"]
	)
	_add(&"balanced_edge", &"UPGRADE_BALANCED_EDGE_TITLE", &"UPGRADE_BALANCED_EDGE_DESC", &"CATEGORY_GENERAL", 1, "BE")


func _prerequisites_met(definition: UpgradeDefinition) -> bool:
	for prerequisite_id in definition.prerequisite_ids:
		if not modifiers.has(prerequisite_id):
			return false
	return true
