extends SceneTree

var _failures: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var game_scene := load("res://levels/game.tscn") as PackedScene
	var game := game_scene.instantiate() as GameFlowManager
	root.add_child(game)
	await process_frame
	var player := game.player as PlayerController
	player.set_combat_input_enabled(true)

	player.global_position = Vector2(160.0, 90.0)
	Input.action_press("move_right")
	for frame in 12:
		await physics_frame
	Input.action_release("move_right")
	var horizontal_distance := player.global_position.distance_to(Vector2(160.0, 90.0))

	player.global_position = Vector2(160.0, 90.0)
	player.velocity = Vector2.ZERO
	await physics_frame
	Input.action_press("move_right")
	Input.action_press("move_down")
	for frame in 12:
		await physics_frame
	Input.action_release("move_right")
	Input.action_release("move_down")
	var diagonal_distance := player.global_position.distance_to(Vector2(160.0, 90.0))
	# The first synthetic action may be observed one physics frame later than the second.
	_expect_close("diagonal movement is normalized", diagonal_distance, horizontal_distance, 1.3)

	player.global_position = Vector2(70.0, 90.0)
	player.velocity = Vector2.ZERO
	Input.action_press("move_left")
	player._start_dodge()
	Input.action_release("move_left")
	await create_timer(0.48).timeout
	if player.global_position.x < 68.9:
		_failures.append("dodge crossed the left arena wall: x=%.3f" % player.global_position.x)
	_expect_equal("dodge returns to move", String(player.get_player_state()), "MOVE")
	var visual_root := player.get_node("VisualRoot") as Node2D
	_expect_close("dodge rotation resets", visual_root.rotation, 0.0, 0.01)
	_expect_close("dodge skew resets", visual_root.skew, 0.0, 0.01)

	game.queue_free()
	await process_frame
	if _failures.is_empty():
		print("PASS: player movement")
		quit(0)
		return
	for failure in _failures:
		push_error(failure)
	quit(1)


func _expect_equal(label: String, actual: Variant, expected: Variant) -> void:
	if actual != expected:
		_failures.append("%s: expected %s, got %s" % [label, str(expected), str(actual)])


func _expect_close(label: String, actual: float, expected: float, epsilon: float) -> void:
	if absf(actual - expected) > epsilon:
		_failures.append("%s: expected %.4f, got %.4f" % [label, expected, actual])
