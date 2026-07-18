extends SceneTree

var _failures: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var player_scene := load("res://actors/player/player.tscn") as PackedScene
	var dummy_scene := load("res://actors/enemies/training_dummy.tscn") as PackedScene
	var player := player_scene.instantiate() as PlayerController
	var dummy := dummy_scene.instantiate() as TrainingDummy
	player.position = Vector2.ZERO
	dummy.position = Vector2(12.0, 0.0)
	root.add_child(player)
	root.add_child(dummy)
	player.set_combat_input_enabled(true)
	await physics_frame

	Input.action_press("attack_charge")
	player._handle_combat_input(1.0 / 60.0)
	await create_timer(0.05).timeout
	_expect_equal("charge state", String(player.get_player_state()), "CHARGE")
	_expect_equal("world charge meter shows while charging", player.charge_meter.visible, true)
	await create_timer(0.77).timeout
	_expect_close("half charge size", player.get_size_factor(), 2.25, 0.12)

	Input.action_release("attack_charge")
	player._handle_combat_input(1.0 / 60.0)
	_expect_equal("swing state", String(player.get_player_state()), "SWING")
	_expect_equal("world charge meter hides on release", player.charge_meter.visible, false)
	await create_timer(0.55).timeout
	_expect_equal("returns to move", String(player.get_player_state()), "MOVE")
	if dummy.get_health() >= TrainingDummy.MAX_HEALTH:
		_failures.append("swing should damage the training dummy")

	Input.action_press("attack_charge")
	player._handle_combat_input(1.0 / 60.0)
	await create_timer(1.75).timeout
	_expect_close("full charge clamps size", player.get_size_factor(), 3.0, 0.01)
	Input.action_press("attack_cancel")
	player._handle_combat_input(1.0 / 60.0)
	Input.action_release("attack_cancel")
	Input.action_release("attack_charge")
	_expect_equal("cancel recovery state", String(player.get_player_state()), "CANCEL_RECOVERY")
	_expect_equal("world charge meter hides on cancel", player.charge_meter.visible, false)
	_expect_close("cancel resets size", player.get_size_factor(), 1.5, 0.01)
	await create_timer(0.24).timeout
	_expect_equal("cancel recovery completes", String(player.get_player_state()), "MOVE")

	dummy.take_hit(HitData.new(500.0, Vector2.ZERO, player, 3.0, 999))
	await create_timer(1.1).timeout
	_expect_equal("dummy respawns alive", dummy.is_alive(), true)
	_expect_close("dummy respawns with full health", dummy.get_health(), TrainingDummy.MAX_HEALTH, 0.01)
	_expect_close("dummy respawns at original x", dummy.global_position.x, 12.0, 0.01)

	var armor_modifiers := RunModifiers.new()
	armor_modifiers.add_upgrade(&"charging_armor")
	player.set_run_modifiers(armor_modifiers)
	player.sword.begin_charge()
	player.sword.advance_charge(0.8)
	player._set_state(PlayerController.PlayerState.CHARGE)
	var guarded_progress := player.get_charge_progress()
	var health_before_guard := player.get_health()
	var guarded_hit := HitData.new(20.0, Vector2(30.0, 0.0), dummy, 1.5, 1001)
	_expect_equal("charging armor applies its guard", player.take_hit(guarded_hit), true)
	_expect_close(
		"charging armor reduces damage by 35 percent",
		player.get_health(),
		health_before_guard - 13.0,
		0.001
	)
	_expect_equal(
		"charging armor preserves charge state",
		String(player.get_player_state()),
		"CHARGE"
	)
	_expect_close(
		"charging armor preserves accumulated charge",
		player.get_charge_progress(),
		guarded_progress,
		0.001
	)
	_expect_close(
		"charging armor starts four second cooldown",
		player._charging_armor_cooldown,
		PlayerController.CHARGING_ARMOR_COOLDOWN,
		0.001
	)
	player._damage_invulnerability_remaining = 0.0
	_expect_equal("cooldown hit still applies", player.take_hit(guarded_hit), true)
	_expect_equal(
		"cooldown hit interrupts charging normally",
		String(player.get_player_state()),
		"HURT"
	)
	_expect_close("cooldown hit resets charge", player.get_charge_progress(), 0.0, 0.001)

	player.queue_free()
	dummy.queue_free()
	await process_frame
	if _failures.is_empty():
		print("PASS: player combat")
		quit(0)
		return
	for failure in _failures:
		push_error(failure)
	quit(1)


func _expect_equal(label: String, actual: Variant, expected: Variant) -> void:
	if actual != expected:
		_failures.append("%s: expected %s, got %s" % [label, str(expected), str(actual)])


func _expect_close(
	label: String,
	actual: float,
	expected: float,
	epsilon: float = 0.0001
) -> void:
	if absf(actual - expected) > epsilon:
		_failures.append("%s: expected %.4f, got %.4f" % [label, expected, actual])
