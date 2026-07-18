class_name GameFlowManager
extends Node

signal flow_state_changed(previous_state: int, current_state: int)
signal round_intro_started(round_index: int, duration: float)
signal combat_started(round_index: int)

enum FlowState {
	MAIN_MENU,
	TRANSITION,
	ROUND_INTRO,
	COMBAT,
	UPGRADE,
	PAUSED,
	RESULT,
}

const PLAYER_SPAWN := Vector2(160.0, 90.0)
const ROUND_NAMES := {
	1: &"ROUND_NAME_1",
	2: &"ROUND_NAME_2",
	3: &"ROUND_NAME_3",
	4: &"ROUND_NAME_4",
	5: &"ROUND_NAME_5",
	6: &"ROUND_NAME_6",
	7: &"ROUND_NAME_7",
	8: &"ROUND_NAME_8",
	9: &"ROUND_NAME_9",
	10: &"ROUND_NAME_10",
	11: &"ROUND_NAME_11",
	12: &"ROUND_NAME_12",
	13: &"ROUND_NAME_13",
}

@onready var effects: Node2D = %Effects
@onready var enemies: Node2D = %Dummies
@onready var arena_bounds: ArenaBounds = %ArenaBounds
@onready var camera: Camera2D = %Camera2D
@onready var player: PlayerController = %Player
@onready var feedback_manager: FeedbackManager = %FeedbackManager
@onready var wave_manager: WaveManager = %WaveManager
@onready var upgrade_manager: UpgradeManager = %UpgradeManager
@onready var audio_manager: AudioManager = %AudioManager
@onready var localization_manager: LocalizationManager = %LocalizationManager
@onready var main_menu: MainMenu = %MainMenu
@onready var run_hud: RunHUD = %RunHUD
@onready var upgrade_selection: UpgradeSelection = %UpgradeSelection
@onready var run_result: RunResult = %RunResult
@onready var round_intro: Control = %RoundIntro
@onready var round_title: Label = %RoundTitle
@onready var countdown_label: Label = %CountdownLabel
@onready var pause_overlay: Control = %PauseOverlay
@onready var pause_title: Label = %PauseTitle
@onready var resume_button: Button = %ResumeButton
@onready var menu_button: Button = %MenuButton
@onready var fade_rect: ColorRect = %FadeRect
@onready var debug_hud: DebugHUD = %DebugHUD

var _flow_state := FlowState.MAIN_MENU
var _transition_running := false
var _current_round := 1
var _combat_elapsed := 0.0
var _kills := 0
var _upgrades := 0
var _rounds_cleared := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	effects.add_to_group("world_effects")
	feedback_manager.set_camera(camera)
	wave_manager.setup(enemies, player, arena_bounds)
	main_menu.setup_localization(localization_manager)
	localization_manager.locale_changed.connect(_on_locale_changed)
	_refresh_localized_text()
	run_hud.setup(self, player, wave_manager)
	debug_hud.setup(self, player)
	main_menu.start_requested.connect(_on_start_requested)
	main_menu.quit_requested.connect(_on_quit_requested)
	resume_button.pressed.connect(_resume_game)
	menu_button.pressed.connect(_return_to_main_menu)
	upgrade_selection.upgrade_chosen.connect(_on_upgrade_chosen)
	run_result.retry_requested.connect(_on_retry_requested)
	run_result.menu_requested.connect(_return_to_main_menu)
	player.player_died.connect(_on_player_died)
	wave_manager.wave_cleared.connect(_on_wave_cleared)
	wave_manager.enemy_killed.connect(_on_enemy_killed)
	round_intro.hide()
	pause_overlay.hide()
	upgrade_selection.hide()
	run_result.hide()
	run_hud.hide()
	fade_rect.modulate.a = 0.0
	player.set_combat_input_enabled(false)
	player.reset_for_run(_get_player_spawn())
	wave_manager.clear_all()
	_set_flow_state(FlowState.MAIN_MENU)
	main_menu.show()
	main_menu.set_start_enabled(true)
	audio_manager.set_music_context(AudioManager.MusicContext.MENU, true)


func _process(delta: float) -> void:
	if _flow_state == FlowState.COMBAT:
		_combat_elapsed += delta


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("pause"):
		return
	if _flow_state == FlowState.COMBAT:
		_pause_game()
	elif _flow_state == FlowState.PAUSED:
		_resume_game()
	get_viewport().set_input_as_handled()


func get_flow_state_name() -> StringName:
	return StringName(FlowState.keys()[_flow_state])


func get_combat_elapsed() -> float:
	return _combat_elapsed


func get_current_round() -> int:
	return _current_round


func get_run_stats() -> Dictionary:
	return {
		"elapsed_combat_time": _combat_elapsed,
		"rounds_cleared": _rounds_cleared,
		"kills": _kills,
		"upgrades": _upgrades,
		"round_count": wave_manager.get_round_count(),
	}


func _on_start_requested() -> void:
	if _transition_running or _flow_state != FlowState.MAIN_MENU:
		return
	_start_game_sequence()


func _on_retry_requested() -> void:
	if _transition_running or _flow_state != FlowState.RESULT:
		return
	run_result.hide()
	_start_game_sequence()


func _start_game_sequence() -> void:
	_transition_running = true
	get_tree().paused = false
	_set_flow_state(FlowState.TRANSITION)
	await _fade_to(1.0, 0.25)
	main_menu.hide()
	run_result.hide()
	feedback_manager.reset_feedback()
	audio_manager.stop_continuous_sfx()
	wave_manager.clear_all()
	upgrade_manager.reset_for_run()
	player.set_run_modifiers(upgrade_manager.modifiers)
	player.reset_for_run(_get_player_spawn())
	player.set_combat_input_enabled(false)
	_current_round = 1
	_combat_elapsed = 0.0
	_kills = 0
	_upgrades = 0
	_rounds_cleared = 0
	run_hud.reset_hud()
	run_hud.show()
	await _fade_to(0.0, 0.25)
	await _play_first_round_intro()
	_start_current_round()
	_transition_running = false


func _play_first_round_intro() -> void:
	_set_flow_state(FlowState.ROUND_INTRO)
	round_intro_started.emit(1, 4.0)
	round_intro.show()
	round_title.text = tr(&"ROUND_INTRO_FORMAT") % [1, tr(ROUND_NAMES[1])]
	countdown_label.text = tr(&"ROUND_GET_READY")
	await get_tree().create_timer(0.5, true, false, true).timeout
	round_title.text = ""
	for value in ["3", "2", "1"]:
		countdown_label.text = value
		countdown_label.scale = Vector2(1.35, 1.35)
		var tween := create_tween()
		tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
		tween.tween_property(countdown_label, "scale", Vector2.ONE, 0.18)
		audio_manager.play_ui_confirm()
		await get_tree().create_timer(1.0, true, false, true).timeout
	countdown_label.text = tr(&"ROUND_GO")
	audio_manager.play_ui_confirm()
	await get_tree().create_timer(0.5, true, false, true).timeout
	round_intro.hide()


func _play_short_round_intro() -> void:
	_set_flow_state(FlowState.ROUND_INTRO)
	round_intro_started.emit(_current_round, 1.2)
	round_intro.show()
	round_title.text = tr(&"ROUND_FORMAT") % [
		_current_round,
		wave_manager.get_round_count(),
	]
	countdown_label.text = tr(ROUND_NAMES[_current_round])
	countdown_label.scale = Vector2(1.12, 1.12)
	var tween := create_tween()
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.tween_property(countdown_label, "scale", Vector2.ONE, 0.28)
	await get_tree().create_timer(1.2, true, false, true).timeout
	round_intro.hide()


func _start_current_round() -> void:
	var definition := wave_manager.get_definition(_current_round)
	audio_manager.set_music_context(
		AudioManager.MusicContext.BOSS
		if definition != null and definition.is_boss_round()
		else AudioManager.MusicContext.COMBAT
	)
	player.set_combat_input_enabled(true)
	_set_flow_state(FlowState.COMBAT)
	wave_manager.start_round(_current_round)
	combat_started.emit(_current_round)


func _on_wave_cleared(round_index: int, was_boss_round: bool) -> void:
	if _flow_state != FlowState.COMBAT or round_index != _current_round:
		return
	player.set_combat_input_enabled(false)
	_rounds_cleared = maxi(_rounds_cleared, round_index)
	await _clear_enemy_bullets()
	player.heal(player.get_max_health() * (0.25 if was_boss_round else 0.15))
	if round_index >= wave_manager.get_round_count():
		_show_result(true)
		return
	_show_upgrade_selection()


func _show_upgrade_selection() -> void:
	_set_flow_state(FlowState.UPGRADE)
	audio_manager.set_music_context(AudioManager.MusicContext.UPGRADE)
	var choices := upgrade_manager.create_choices(3)
	upgrade_selection.show_choices(choices, upgrade_manager, _current_round)
	get_tree().paused = true


func _on_upgrade_chosen(upgrade_id: StringName) -> void:
	if _flow_state != FlowState.UPGRADE:
		return
	if not upgrade_manager.select_upgrade(upgrade_id):
		return
	_upgrades += 1
	player.on_upgrade_applied(upgrade_id)
	get_tree().paused = false
	_current_round += 1
	await _play_short_round_intro()
	_start_current_round()


func _on_enemy_killed(_enemy: EnemyBase, _hit_data: HitData) -> void:
	_kills += 1


func _clear_enemy_bullets() -> void:
	var bullets := get_tree().get_nodes_in_group("enemy_bullet")
	for bullet in bullets:
		var tween := bullet.create_tween()
		tween.tween_property(bullet, "modulate:a", 0.0, 0.25)
	await get_tree().create_timer(0.25).timeout
	for bullet in bullets:
		if is_instance_valid(bullet):
			bullet.queue_free()


func _fade_to(alpha: float, duration: float) -> void:
	var tween := create_tween()
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.tween_property(fade_rect, "modulate:a", alpha, duration)
	await tween.finished


func _pause_game() -> void:
	if _flow_state != FlowState.COMBAT:
		return
	_set_flow_state(FlowState.PAUSED)
	pause_overlay.show()
	resume_button.grab_focus()
	get_tree().paused = true


func _resume_game() -> void:
	if _flow_state != FlowState.PAUSED:
		return
	get_tree().paused = false
	pause_overlay.hide()
	_set_flow_state(FlowState.COMBAT)


func _return_to_main_menu() -> void:
	get_tree().paused = false
	_transition_running = false
	feedback_manager.reset_feedback()
	audio_manager.stop_continuous_sfx()
	audio_manager.set_music_context(AudioManager.MusicContext.MENU)
	pause_overlay.hide()
	upgrade_selection.hide()
	run_result.hide()
	round_intro.hide()
	run_hud.hide()
	wave_manager.clear_all()
	upgrade_manager.reset_for_run()
	player.set_run_modifiers(upgrade_manager.modifiers)
	player.set_combat_input_enabled(false)
	player.reset_for_run(_get_player_spawn())
	_set_flow_state(FlowState.MAIN_MENU)
	main_menu.show()
	main_menu.set_start_enabled(true)
	main_menu.focus_start_button()


func _on_quit_requested() -> void:
	get_tree().quit()


func _on_player_died() -> void:
	if _flow_state != FlowState.COMBAT:
		return
	wave_manager.stop()
	_show_result(false)


func _get_player_spawn() -> Vector2:
	if is_instance_valid(arena_bounds):
		return arena_bounds.get_safe_rect(8.0).get_center()
	return PLAYER_SPAWN


func _show_result(victory: bool) -> void:
	get_tree().paused = false
	player.set_combat_input_enabled(false)
	wave_manager.stop()
	_set_flow_state(FlowState.RESULT)
	audio_manager.stop_continuous_sfx()
	audio_manager.set_music_context(AudioManager.MusicContext.RESULT)
	run_result.show_result(victory, get_run_stats())
	get_tree().paused = true


func _on_locale_changed(_locale: StringName) -> void:
	_refresh_localized_text()


func _refresh_localized_text() -> void:
	pause_title.text = tr(&"PAUSE_TITLE")
	resume_button.text = tr(&"PAUSE_RESUME")
	menu_button.text = tr(&"COMMON_MAIN_MENU")


func _set_flow_state(new_state: int) -> void:
	if new_state == _flow_state:
		return
	var previous := _flow_state
	_flow_state = new_state
	flow_state_changed.emit(previous, _flow_state)
