extends SceneTree

var _failures: Array[String] = []
var _last_intro_duration := 0.0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var game_scene := load("res://levels/game.tscn") as PackedScene
	var game := game_scene.instantiate() as GameFlowManager
	root.add_child(game)
	await process_frame
	game.round_intro_started.connect(_on_round_intro_started)
	_expect_equal("initial flow", String(game.get_flow_state_name()), "MAIN_MENU")
	_expect_equal("initial enemy count", get_nodes_in_group("enemy").size(), 0)

	for run_index in 3:
		game._on_start_requested()
		game._on_start_requested()
		await create_timer(5.25, true, false, true).timeout
		_expect_equal(
			"first intro duration %d" % run_index,
			_last_intro_duration,
			4.0
		)
		_expect_equal(
			"combat flow after intro %d" % run_index,
			String(game.get_flow_state_name()),
			"COMBAT"
		)
		_expect_equal(
			"first batch count after intro %d" % run_index,
			get_nodes_in_group("enemy").size(),
			3
		)

		if run_index == 0:
			game._pause_game()
			_expect_equal("pause flow", String(game.get_flow_state_name()), "PAUSED")
			game._resume_game()
			_expect_equal("resume flow", String(game.get_flow_state_name()), "COMBAT")

		game._return_to_main_menu()
		await process_frame
		_expect_equal(
			"return to menu flow %d" % run_index,
			String(game.get_flow_state_name()),
			"MAIN_MENU"
		)
		_expect_equal(
			"enemy count after return %d" % run_index,
			get_nodes_in_group("enemy").size(),
			0
		)

	game.queue_free()
	await process_frame
	if _failures.is_empty():
		print("PASS: game flow")
		quit(0)
		return
	for failure in _failures:
		push_error(failure)
	quit(1)


func _on_round_intro_started(_round_index: int, duration: float) -> void:
	_last_intro_duration = duration


func _expect_equal(label: String, actual: Variant, expected: Variant) -> void:
	if actual != expected:
		_failures.append("%s: expected %s, got %s" % [label, str(expected), str(actual)])
