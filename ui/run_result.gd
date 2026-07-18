class_name RunResult
extends Control

signal retry_requested
signal menu_requested

@onready var title: Label = %Title
@onready var stats: Label = %Stats
@onready var retry_button: Button = %RetryButton
@onready var menu_button: Button = %ResultMenuButton

var _victory := false
var _run_stats: Dictionary = {}
var _localization_manager: LocalizationManager

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	retry_button.pressed.connect(func() -> void: retry_requested.emit())
	menu_button.pressed.connect(func() -> void: menu_requested.emit())
	_localization_manager = (
		get_tree().get_first_node_in_group("localization_manager")
		as LocalizationManager
	)
	if _localization_manager != null:
		_localization_manager.locale_changed.connect(_on_locale_changed)
	hide()


func show_result(victory: bool, run_stats: Dictionary) -> void:
	_victory = victory
	_run_stats = run_stats.duplicate()
	_refresh_localized_text()
	title.modulate = Color.WHITE
	show()
	retry_button.grab_focus()


func _refresh_localized_text() -> void:
	title.text = tr(&"RESULT_VICTORY") if _victory else tr(&"RESULT_DEFEATED")
	retry_button.text = tr(&"RESULT_RETRY")
	menu_button.text = tr(&"COMMON_MAIN_MENU")
	var run_stats := _run_stats
	var elapsed := float(run_stats.get("elapsed_combat_time", 0.0))
	stats.text = tr(&"RESULT_STATS_FORMAT").replace("\\n", "\n") % [
			int(elapsed) / 60,
			int(elapsed) % 60,
			int(run_stats.get("rounds_cleared", 0)),
			int(run_stats.get("round_count", 13)),
			int(run_stats.get("kills", 0)),
			int(run_stats.get("upgrades", 0)),
		]


func _on_locale_changed(_locale: StringName) -> void:
	_refresh_localized_text()
