class_name UpgradeSelection
extends Control

signal upgrade_chosen(upgrade_id: StringName)

const CARD_SCENE := preload("res://ui/upgrade_card.tscn")

@onready var cards: HBoxContainer = %Cards
@onready var title: Label = %Title

var _choices: Array[UpgradeDefinition] = []
var _manager: UpgradeManager
var _round_index := 0
var _localization_manager: LocalizationManager


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_localization_manager = (
		get_tree().get_first_node_in_group("localization_manager")
		as LocalizationManager
	)
	if _localization_manager != null:
		_localization_manager.locale_changed.connect(_on_locale_changed)
	hide()


func show_choices(
	choices: Array[UpgradeDefinition],
	manager: UpgradeManager,
	round_index: int
) -> void:
	_choices = choices
	_manager = manager
	_round_index = round_index
	_rebuild_cards()
	show()
	_clear_card_focus()


func _rebuild_cards() -> void:
	title.text = tr(&"ROUND_CLEARED_FORMAT") % _round_index
	for child in cards.get_children():
		if child is UpgradeCard:
			(child as UpgradeCard).reset_visual_state()
		cards.remove_child(child)
		child.queue_free()
	for index in _choices.size():
		var definition := _choices[index]
		var card := CARD_SCENE.instantiate() as UpgradeCard
		cards.add_child(card)
		card.setup(definition, _manager.get_stack(definition.id), index)
		card.selected.connect(_choose_index)


func _unhandled_key_input(event: InputEvent) -> void:
	if not visible or not event.is_pressed() or event.is_echo():
		return
	var key_event := event as InputEventKey
	if key_event == null:
		return
	var index := -1
	if key_event.keycode == KEY_1:
		index = 0
	elif key_event.keycode == KEY_2:
		index = 1
	elif key_event.keycode == KEY_3:
		index = 2
	if index >= 0 and index < _choices.size():
		_choose(_choices[index].id)
		get_viewport().set_input_as_handled()
		return
	if (
		not _cards_have_focus()
		and (
			event.is_action("ui_up")
			or event.is_action("ui_down")
			or event.is_action("ui_left")
			or event.is_action("ui_right")
			or key_event.keycode == KEY_TAB
		)
		and cards.get_child_count() > 0
	):
		(cards.get_child(0) as UpgradeCard).grab_focus()
		get_viewport().set_input_as_handled()


func _on_locale_changed(_locale: StringName) -> void:
	if visible and _manager != null:
		_rebuild_cards()


func _choose_index(index: int) -> void:
	if index >= 0 and index < _choices.size():
		_choose(_choices[index].id)


func _choose(upgrade_id: StringName) -> void:
	for child in cards.get_children():
		if child is UpgradeCard:
			(child as UpgradeCard).reset_visual_state()
	hide()
	upgrade_chosen.emit(upgrade_id)


func _cards_have_focus() -> bool:
	var focus_owner := get_viewport().gui_get_focus_owner()
	return focus_owner != null and cards.is_ancestor_of(focus_owner)


func _clear_card_focus() -> void:
	var focus_owner := get_viewport().gui_get_focus_owner()
	if focus_owner != null:
		focus_owner.release_focus()
