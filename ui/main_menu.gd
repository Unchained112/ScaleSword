class_name MainMenu
extends Control

signal start_requested
signal quit_requested

@onready var start_button: Button = %StartButton
@onready var quit_button: Button = %QuitButton
@onready var language_button: Button = %LanguageButton
@onready var controls: Label = %Controls

var _localization_manager: LocalizationManager


func _ready() -> void:
	start_button.pressed.connect(_on_start_pressed)
	quit_button.pressed.connect(_on_quit_pressed)
	language_button.pressed.connect(_on_language_pressed)
	quit_button.visible = not OS.has_feature("web")
	setup_localization(
		get_tree().get_first_node_in_group("localization_manager")
		as LocalizationManager
	)
	_refresh_localized_text()
	_clear_menu_focus()


func setup_localization(localization_manager: LocalizationManager) -> void:
	if _localization_manager == localization_manager:
		return
	if (
		_localization_manager != null
		and _localization_manager.locale_changed.is_connected(_on_locale_changed)
	):
		_localization_manager.locale_changed.disconnect(_on_locale_changed)
	_localization_manager = localization_manager
	if (
		_localization_manager != null
		and not _localization_manager.locale_changed.is_connected(_on_locale_changed)
	):
		_localization_manager.locale_changed.connect(_on_locale_changed)
	if is_node_ready():
		_refresh_localized_text()


func set_start_enabled(enabled: bool) -> void:
	start_button.disabled = not enabled
	quit_button.disabled = not enabled
	language_button.disabled = not enabled
	if enabled and is_visible_in_tree():
		_clear_menu_focus()


func focus_start_button() -> void:
	_clear_menu_focus()


func _unhandled_key_input(event: InputEvent) -> void:
	if not visible or not event.is_pressed() or event.is_echo():
		return
	var key_event := event as InputEventKey
	if key_event == null or _menu_has_focus():
		return
	if (
		event.is_action("ui_up")
		or event.is_action("ui_down")
		or event.is_action("ui_left")
		or event.is_action("ui_right")
		or key_event.keycode == KEY_TAB
	):
		start_button.grab_focus()
		get_viewport().set_input_as_handled()


func _menu_has_focus() -> bool:
	var focus_owner := get_viewport().gui_get_focus_owner()
	return focus_owner != null and is_ancestor_of(focus_owner)


func _clear_menu_focus() -> void:
	var focus_owner := get_viewport().gui_get_focus_owner()
	if focus_owner != null:
		focus_owner.release_focus()


func _on_start_pressed() -> void:
	if start_button.disabled:
		return
	set_start_enabled(false)
	start_requested.emit()


func _on_quit_pressed() -> void:
	if quit_button.disabled:
		return
	quit_requested.emit()


func _on_language_pressed() -> void:
	if language_button.disabled or _localization_manager == null:
		return
	_localization_manager.toggle_locale()


func _on_locale_changed(_locale: StringName) -> void:
	_refresh_localized_text()


func _refresh_localized_text() -> void:
	start_button.text = tr(&"MENU_START")
	quit_button.text = tr(&"MENU_QUIT")
	controls.text = tr(&"MENU_CONTROLS").replace("\\n", "\n")
	language_button.text = (
		_localization_manager.get_switch_label()
		if _localization_manager != null
		else "中文"
	)
