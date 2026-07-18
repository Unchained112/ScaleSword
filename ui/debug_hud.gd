class_name DebugHUD
extends Control

@onready var debug_label: Label = %DebugLabel

var _flow_manager: Node
var _player: PlayerController


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	hide()


func setup(flow_manager: Node, player: PlayerController) -> void:
	_flow_manager = flow_manager
	_player = player


func _process(_delta: float) -> void:
	if Input.is_action_just_pressed("debug_toggle"):
		visible = not visible
	if not visible or not is_instance_valid(_flow_manager) or not is_instance_valid(_player):
		return
	var alive_enemies := 0
	for enemy in get_tree().get_nodes_in_group("enemy"):
		if enemy.has_method("is_alive") and enemy.is_alive():
			alive_enemies += 1
	debug_label.text = (
		"FPS: %d\nFLOW: %s\nPLAYER: %s\nHP: %.0f/%.0f\nCHARGE: %3.0f%%\nSIZE: %.2f\nDODGE CD: %.2f\nENEMIES: %d"
		% [
			Engine.get_frames_per_second(),
			_flow_manager.get_flow_state_name(),
			_player.get_player_state(),
			_player.get_health(),
			_player.get_max_health(),
			_player.get_charge_progress() * 100.0,
			_player.get_size_factor(),
			_player.get_dodge_cooldown_remaining(),
			alive_enemies,
		]
	)
