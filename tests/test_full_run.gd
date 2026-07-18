extends SceneTree

var _failures: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var game := (load("res://levels/game.tscn") as PackedScene).instantiate() as GameFlowManager
	root.add_child(game)
	await process_frame
	game._on_start_requested()
	await create_timer(5.25, true, false, true).timeout
	for expected_round in range(1, 14):
		_expect_equal("round %d active" % expected_round, game.get_current_round(), expected_round)
		var safety := 0
		while String(game.get_flow_state_name()) == "COMBAT" and safety < 80:
			safety += 1
			await create_timer(0.48).timeout
			for node in get_nodes_in_group("enemy"):
				var enemy := node as EnemyBase
				if is_instance_valid(enemy) and enemy.is_alive():
					enemy.take_hit(HitData.new(
						99999.0,
						Vector2.ZERO,
						game.player,
						3.5,
						9000 + safety
					))
			await create_timer(0.16, true, false, true).timeout
		if safety >= 80:
			_failures.append("round %d did not clear" % expected_round)
			break
		if expected_round < 13:
			_expect_equal(
				"round %d opens upgrade" % expected_round,
				String(game.get_flow_state_name()),
				"UPGRADE"
			)
			var choices: Array[UpgradeDefinition] = game.upgrade_manager.create_choices(3)
			if choices.is_empty():
				_failures.append("round %d has no upgrade choices" % expected_round)
				break
			game._on_upgrade_chosen(choices[0].id)
			await create_timer(1.35, true, false, true).timeout
	_expect_equal("full run reaches result", String(game.get_flow_state_name()), "RESULT")
	_expect_equal("full run clears thirteen rounds", game.get_run_stats()["rounds_cleared"], 13)
	_expect_equal("full run grants twelve upgrades", game.get_run_stats()["upgrades"], 12)
	game._return_to_main_menu()
	await process_frame
	_expect_equal("full run returns to menu", String(game.get_flow_state_name()), "MAIN_MENU")
	_expect_equal("full run clears enemies", get_nodes_in_group("enemy").size(), 0)
	game.queue_free()
	await process_frame
	if _failures.is_empty():
		print("PASS: full thirteen-round run")
		quit(0)
		return
	for failure in _failures:
		push_error(failure)
	quit(1)


func _expect_equal(label: String, actual: Variant, expected: Variant) -> void:
	if actual != expected:
		_failures.append("%s: expected %s, got %s" % [label, str(expected), str(actual)])
