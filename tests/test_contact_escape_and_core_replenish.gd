extends SceneTree

var _failures: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var game := (load("res://levels/game.tscn") as PackedScene).instantiate() as GameFlowManager
	root.add_child(game)
	await process_frame
	await _test_player_escape_collision(game)
	await _test_contact_recoil_while_invulnerable(game)
	await _test_core_replenishment_timing(game)
	game.queue_free()
	await process_frame
	if _failures.is_empty():
		print("PASS: contact escape and core replenishment")
		quit(0)
		return
	for failure in _failures:
		push_error(failure)
	quit(1)


func _test_player_escape_collision(game: GameFlowManager) -> void:
	game.wave_manager.clear_all()
	await process_frame
	_expect_equal("player only collides with world", game.player.collision_mask, 1)
	game.player.reset_for_run(Vector2(150.0, 90.0))
	game.player.set_combat_input_enabled(true)
	var blocker := (
		(load("res://actors/enemies/chaser.tscn") as PackedScene).instantiate()
		as ChaserEnemy
	)
	game.enemies.add_child(blocker)
	blocker.global_position = Vector2(164.0, 90.0)
	blocker.set_physics_process(false)
	_expect_equal("enemy still detects world and player", blocker.collision_mask, 3)
	Input.action_press("move_right")
	for frame in 20:
		await physics_frame
	Input.action_release("move_right")
	if game.player.global_position.x <= 168.0:
		_failures.append(
			"player remained blocked by enemy at x=%.2f"
			% game.player.global_position.x
		)
	game.player.set_combat_input_enabled(false)


func _test_contact_recoil_while_invulnerable(game: GameFlowManager) -> void:
	game.wave_manager.clear_all()
	await process_frame
	game.player.reset_for_run(Vector2(160.0, 90.0))
	game.player._damage_invulnerability_remaining = 1.0
	var chaser := (
		(load("res://actors/enemies/chaser.tscn") as PackedScene).instantiate()
		as ChaserEnemy
	)
	game.enemies.add_child(chaser)
	chaser.global_position = Vector2(153.0, 90.0)
	var health_before := game.player.get_health()
	for frame in 8:
		await physics_frame
	_expect_close(
		"invulnerable contact deals no damage",
		game.player.get_health(),
		health_before,
		0.01
	)
	if chaser.global_position.distance_to(game.player.global_position) < 8.0:
		_failures.append("invulnerable contact did not separate enemy")
	if chaser._contact_recoil_remaining <= 0.0:
		_failures.append("contact did not enter recoil state")


func _test_core_replenishment_timing(game: GameFlowManager) -> void:
	game.wave_manager.clear_all()
	await process_frame
	game.wave_manager._active = true
	game.wave_manager._current_definition = game.wave_manager.get_definition(9)
	game.wave_manager._round_index = 9
	var core := (
		(load("res://actors/bosses/proliferation_core.tscn") as PackedScene).instantiate()
		as ProliferationCoreBoss
	)
	game.enemies.add_child(core)
	core.global_position = Vector2(210.0, 90.0)
	core.set_physics_process(false)
	core.take_hit(HitData.new(280.0, Vector2.ZERO, game.player, 1.5, 8100, 0.0))
	await process_frame
	await physics_frame
	_expect_equal("seventy percent phase creates two clones", core._get_clones().size(), 2)
	for clone in core._get_clones():
		clone._spawn_locked = false
	core._update_clone_replenishment(15.0)
	_expect_close(
		"full squad keeps replenishment disabled",
		core._clone_replenish_remaining,
		-1.0,
		0.001
	)
	var first_clone := core._get_clones()[0]
	first_clone.take_hit(HitData.new(999.0, Vector2.ZERO, game.player, 3.0, 8101, 1.0))
	await process_frame
	_expect_close(
		"clone kill starts six second delay",
		core._clone_replenish_remaining,
		6.0,
		0.001
	)
	core._update_clone_replenishment(4.9)
	_expect_equal(
		"no warning before final second",
		is_instance_valid(core._clone_replenish_warning),
		false
	)
	core._update_clone_replenishment(0.2)
	_expect_equal(
		"final second creates warning",
		is_instance_valid(core._clone_replenish_warning),
		true
	)
	_expect_equal("no early replacement", core._get_clones().size(), 1)
	core._update_clone_replenishment(0.9)
	await process_frame
	await physics_frame
	_expect_equal("six seconds replenishes exactly one clone", core._get_clones().size(), 2)

	core.take_hit(HitData.new(300.0, Vector2.ZERO, game.player, 1.5, 8102, 0.0))
	await process_frame
	await physics_frame
	_expect_equal("forty percent phase fills four clone cap", core._get_clones().size(), 4)
	for clone in core._get_clones():
		clone._spawn_locked = false
	var killed_clones := core._get_clones().slice(0, 2)
	(killed_clones[0] as ProliferationClone).take_hit(
		HitData.new(999.0, Vector2.ZERO, game.player, 3.0, 8103, 1.0)
	)
	core._update_clone_replenishment(2.0)
	(killed_clones[1] as ProliferationClone).take_hit(
		HitData.new(999.0, Vector2.ZERO, game.player, 3.0, 8104, 1.0)
	)
	await process_frame
	_expect_close(
		"second kill refreshes full delay",
		core._clone_replenish_remaining,
		6.0,
		0.001
	)
	core._update_clone_replenishment(6.0)
	await process_frame
	await physics_frame
	_expect_equal("first cycle restores only one missing clone", core._get_clones().size(), 3)
	_expect_close(
		"second missing clone starts another cycle",
		core._clone_replenish_remaining,
		6.0,
		0.001
	)
	core._update_clone_replenishment(6.0)
	await process_frame
	await physics_frame
	_expect_equal("second cycle restores final clone", core._get_clones().size(), 4)

	for clone in core._get_clones():
		clone._spawn_time_msec = Time.get_ticks_msec() - 7000
	var core_capsule := core.collision_shape.shape as CapsuleShape2D
	_expect_equal(
		"core uses the configured capsule collision",
		core_capsule != null,
		true
	)
	var base_capsule_radius := core_capsule.radius
	var base_capsule_height := core_capsule.height
	core._start_absorb()
	core._complete_absorb()
	await process_frame
	await physics_frame
	await process_frame
	_expect_close(
		"absorption starts ten second lockout",
		core._clone_replenish_remaining,
		10.0,
		0.001
	)
	_expect_close(
		"absorption grows capsule radius",
		core_capsule.radius,
		base_capsule_radius * 1.12,
		0.001
	)
	_expect_close(
		"absorption grows capsule height",
		core_capsule.height,
		base_capsule_height * 1.12,
		0.001
	)
	core._update_clone_replenishment(9.0)
	if not is_instance_valid(core._clone_replenish_warning):
		_failures.append(
			"absorb lockout warning missing: remaining=%.3f clones=%d pending=%d"
			% [
				core._clone_replenish_remaining,
				core._get_clones().size(),
				core._pending_clone_requests,
			]
		)
	core.take_hit(HitData.new(250.0, Vector2.ZERO, game.player, 3.0, 8105, 1.0))
	_expect_equal("below twenty percent cancels replenishment", core.get_health_ratio() <= 0.20, true)
	core._update_clone_replenishment(20.0)
	_expect_close(
		"below twenty percent remains disabled",
		core._clone_replenish_remaining,
		-1.0,
		0.001
	)
	_expect_equal(
		"below twenty percent clears warning",
		is_instance_valid(core._clone_replenish_warning),
		false
	)


func _expect_equal(label: String, actual: Variant, expected: Variant) -> void:
	if actual != expected:
		_failures.append("%s: expected %s, got %s" % [label, str(expected), str(actual)])


func _expect_close(label: String, actual: float, expected: float, epsilon: float) -> void:
	if absf(actual - expected) > epsilon:
		_failures.append("%s: expected %.4f, got %.4f" % [label, expected, actual])
