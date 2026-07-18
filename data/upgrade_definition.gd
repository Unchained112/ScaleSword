class_name UpgradeDefinition
extends RefCounted

var id: StringName
var title_key: StringName
var description_key: StringName
var category_key: StringName
var max_stacks: int
var icon_code: String
var prerequisite_ids: Array[StringName]


func _init(
	p_id: StringName,
	p_title_key: StringName,
	p_description_key: StringName,
	p_category_key: StringName,
	p_max_stacks: int,
	p_icon_code: String,
	p_prerequisite_ids: Array[StringName] = []
) -> void:
	id = p_id
	title_key = p_title_key
	description_key = p_description_key
	category_key = p_category_key
	max_stacks = p_max_stacks
	icon_code = p_icon_code
	prerequisite_ids = p_prerequisite_ids
