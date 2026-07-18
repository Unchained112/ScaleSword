class_name RunHUD
extends Control

@onready var hp_label: Label = %HPLabel
@onready var hp_bar: ProgressBar = %HPBar
@onready var round_label: Label = %RoundLabel
@onready var remaining_label: Label = %RemainingLabel
@onready var time_label: Label = %TimeLabel
@onready var dodge_bar: ProgressBar = %DodgeBar
@onready var dodge_label: Label = %DodgeLabel
@onready var boss_panel: Control = %BossPanel
@onready var boss_name_label: Label = %BossName
@onready var boss_bar: ProgressBar = %BossBar

var _flow_manager: GameFlowManager
var _player: PlayerController
var _wave_manager: WaveManager
var _boss: EnemyBase
var _localization_manager: LocalizationManager
var _round_index := 1
var _remaining := 0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_localization_manager = (
		get_tree().get_first_node_in_group("localization_manager")
		as LocalizationManager
	)
	if _localization_manager != null:
		_localization_manager.locale_changed.connect(_on_locale_changed)
	boss_panel.hide()
	_on_locale_changed(
		_localization_manager.get_locale()
		if _localization_manager != null
		else &"en"
	)


func setup(
	flow_manager: GameFlowManager,
	player: PlayerController,
	wave_manager: WaveManager
) -> void:
	_flow_manager = flow_manager
	_player = player
	_wave_manager = wave_manager
	player.health_changed.connect(_on_health_changed)
	wave_manager.round_started.connect(_on_round_started)
	wave_manager.remaining_changed.connect(_on_remaining_changed)
	wave_manager.boss_spawned.connect(_on_boss_spawned)
	_on_health_changed(player.get_health(), player.get_max_health())
	hide()


func _process(_delta: float) -> void:
	if not is_instance_valid(_player):
		return
	var duration := maxf(_player.get_dodge_cooldown_duration(), 0.01)
	dodge_bar.value = 1.0 - clampf(_player.get_dodge_cooldown_remaining() / duration, 0.0, 1.0)
	dodge_label.text = tr(&"HUD_DODGE_CHARGES_FORMAT") % [
		_player.get_dodge_charges(),
		_player.get_max_dodge_charges(),
	]
	if is_instance_valid(_flow_manager):
		var elapsed := _flow_manager.get_combat_elapsed()
		time_label.text = "%02d:%02d" % [int(elapsed) / 60, int(elapsed) % 60]


func reset_hud() -> void:
	_boss = null
	boss_panel.hide()
	_on_round_started(1)
	_on_remaining_changed(0)


func _on_health_changed(current: float, maximum: float) -> void:
	hp_bar.max_value = maximum
	hp_bar.value = current
	hp_label.text = "HP  %d / %d" % [ceili(current), ceili(maximum)]


func _on_round_started(round_index: int) -> void:
	_round_index = round_index
	round_label.text = tr(&"ROUND_FORMAT") % [
		round_index,
		_wave_manager.get_round_count() if is_instance_valid(_wave_manager) else 13,
	]


func _on_remaining_changed(remaining: int) -> void:
	_remaining = remaining
	remaining_label.text = tr(&"HUD_ENEMIES_FORMAT") % remaining


func _on_boss_spawned(boss: EnemyBase) -> void:
	_boss = boss
	boss_name_label.text = tr(boss.boss_name_key)
	boss_bar.max_value = boss.get_max_health()
	boss_bar.value = boss.get_health()
	boss_panel.show()
	boss.health_changed.connect(_on_boss_health_changed)
	boss.enemy_died.connect(_on_boss_died)


func _on_boss_health_changed(current: float, maximum: float) -> void:
	boss_bar.max_value = maximum
	boss_bar.value = current


func _on_boss_died(_boss_enemy: EnemyBase, _hit_data: HitData) -> void:
	boss_panel.hide()
	_boss = null


func _on_locale_changed(_locale: StringName) -> void:
	_on_round_started(_round_index)
	_on_remaining_changed(_remaining)
	dodge_label.text = tr(&"HUD_DODGE_CHARGES_FORMAT") % [
		_player.get_dodge_charges() if is_instance_valid(_player) else 1,
		_player.get_max_dodge_charges() if is_instance_valid(_player) else 1,
	]
	if is_instance_valid(_boss):
		boss_name_label.text = tr(_boss.boss_name_key)
