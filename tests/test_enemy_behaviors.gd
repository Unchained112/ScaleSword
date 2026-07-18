extends SceneTree

var _failures: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var game := (load("res://levels/game.tscn") as PackedScene).instantiate() as GameFlowManager
	root.add_child(game)
	await process_frame
	_expect_equal("tilemap background exists", game.has_node("World/Background"), true)
	_expect_equal(
		"dynamic arena interior",
		game.arena_bounds.get_interior_rect(),
		Rect2(66.0, 32.0, 196.0, 104.0)
	)
	_expect_equal(
		"sword renders above player",
		game.player.sword.visual_root.z_index > game.player.visual_root.z_index,
		true
	)
	var scene_paths := [
		"res://actors/enemies/chaser.tscn",
		"res://actors/enemies/shooter.tscn",
		"res://actors/enemies/charger.tscn",
		"res://actors/enemies/heavy_charger.tscn",
		"res://actors/enemies/splitter.tscn",
		"res://actors/enemies/skirmisher.tscn",
	]
	var positions := [
		Vector2(210, 52), Vector2(260, 84), Vector2(210, 132),
		Vector2(278, 42), Vector2(270, 136), Vector2(82, 54),
	]
	for index in scene_paths.size():
		var enemy := (load(scene_paths[index]) as PackedScene).instantiate() as EnemyBase
		game.enemies.add_child(enemy)
		enemy.position = positions[index]
	await process_frame
	var enemies := get_nodes_in_group("enemy")
	_expect_equal("complete enemy roster size", enemies.size(), 6)
	_expect_type_count(enemies, ChaserEnemy, 1, "chaser")
	_expect_type_count(enemies, ShooterEnemy, 1, "shooter")
	_expect_type_count(enemies, ChargerEnemy, 2, "chargers")
	_expect_type_count(enemies, SplitterEnemy, 1, "splitter")
	_expect_type_count(enemies, SkirmisherEnemy, 1, "skirmisher")
	await create_timer(0.75).timeout
	var telegraphs := _count_nodes_of_type(game.enemies, DashTelegraph)
	if telegraphs < 2:
		_failures.append("expected short and segmented dash telegraphs, got %d" % telegraphs)
	var chaser: ChaserEnemy
	for enemy in enemies:
		if enemy is ChaserEnemy:
			chaser = enemy
			break
	if chaser != null and is_instance_valid(chaser):
		chaser.take_hit(HitData.new(1.0, Vector2.ZERO, game.player, 1.0, 100))
		var material := chaser.sprite.material as ShaderMaterial
		_expect_close(
			"hit flash reaches full white",
			float(material.get_shader_parameter("flash_amount")),
			1.0,
			0.01
		)
		await create_timer(0.24).timeout
		_expect_close(
			"hit flash returns to normal",
			float(material.get_shader_parameter("flash_amount")),
			0.0,
			0.02
		)
	await create_timer(1.25).timeout
	if get_nodes_in_group("enemy_bullet").is_empty():
		_failures.append("shooter did not create an enemy bullet")
	game.wave_manager.clear_all()
	await process_frame
	game.player.reset_for_run(Vector2(160, 90))
	var first_damage := game.player.take_hit(
		HitData.new(10.0, Vector2.RIGHT * 10.0, game, 1.0, 200)
	)
	var second_damage := game.player.take_hit(
		HitData.new(10.0, Vector2.RIGHT * 10.0, game, 1.0, 201)
	)
	_expect_equal("first player hit applies", first_damage, true)
	_expect_equal("invulnerability rejects immediate second hit", second_damage, false)
	await _test_splitter(game, false)
	await _test_splitter(game, true)
	await _test_splitter_from_sword_physics_callback(game)
	await _test_cancelled_deferred_split(game)
	game.queue_free()
	await process_frame
	if _failures.is_empty():
		print("PASS: enemy behaviors")
		quit(0)
		return
	for failure in _failures:
		push_error(failure)
	quit(1)


func _test_splitter(game: GameFlowManager, use_large_sword: bool) -> void:
	game.wave_manager.clear_all()
	await process_frame
	var splitter := (
		(load("res://actors/enemies/splitter.tscn") as PackedScene).instantiate()
		as SplitterEnemy
	)
	splitter.position = Vector2(120.0, 90.0)
	game.enemies.add_child(splitter)
	var size_factor := 3.0 if use_large_sword else 1.5
	var progress := 1.0 if use_large_sword else 0.0
	splitter.take_hit(HitData.new(
		1000.0,
		Vector2.ZERO,
		game.player,
		size_factor,
		300,
		progress
	))
	await process_frame
	await physics_frame
	var expected := 0 if use_large_sword else 2
	_expect_equal(
		"large sword suppresses split" if use_large_sword else "small sword creates children",
		get_nodes_in_group("enemy").size(),
		expected
	)


func _test_splitter_from_sword_physics_callback(game: GameFlowManager) -> void:
	game.wave_manager.clear_all()
	await process_frame
	game.wave_manager._active = true
	game.wave_manager._current_definition = game.wave_manager.get_definition(4)
	game.wave_manager._round_index = 4
	game.wave_manager._clear_emitted = false
	game.player.reset_for_run(Vector2(160.0, 90.0))
	game.player.set_combat_input_enabled(true)
	var cleared_early := false
	var on_cleared := func(_round: int, _boss: bool) -> void:
		cleared_early = true
	game.wave_manager.wave_cleared.connect(on_cleared, CONNECT_ONE_SHOT)
	var splitter := (
		(load("res://actors/enemies/splitter.tscn") as PackedScene).instantiate()
		as SplitterEnemy
	)
	splitter.global_position = Vector2(169.0, 90.0)
	game.enemies.add_child(splitter)
	splitter.take_hit(HitData.new(
		splitter.get_max_health() - 1.0,
		Vector2.ZERO,
		game.player,
		3.0,
		350
	))
	await physics_frame
	game.player.sword.set_aim_direction(Vector2.RIGHT)
	game.player.sword.begin_charge()
	game.player.sword.release_attack(Vector2.RIGHT)
	await create_timer(0.32).timeout
	await physics_frame
	await process_frame
	_expect_equal("physics-callback split creates two children", get_nodes_in_group("enemy").size(), 2)
	_expect_equal("deferred split pending count returns to zero", game.wave_manager.get_pending_deferred_spawn_count(), 0)
	_expect_equal("split children prevent premature clear", cleared_early, false)
	_expect_equal("split children remain in wave count", game.wave_manager.get_remaining(), 2)
	if game.wave_manager.wave_cleared.is_connected(on_cleared):
		game.wave_manager.wave_cleared.disconnect(on_cleared)


func _test_cancelled_deferred_split(game: GameFlowManager) -> void:
	game.wave_manager.clear_all()
	await process_frame
	game.wave_manager._active = true
	game.wave_manager._current_definition = game.wave_manager.get_definition(4)
	var accepted := game.wave_manager.request_deferred_enemy_spawn(
		load("res://actors/enemies/splitter_child.tscn") as PackedScene,
		Vector2(120.0, 90.0),
		&"split"
	)
	_expect_equal("active wave accepts deferred split", accepted, true)
	game.wave_manager.stop()
	await process_frame
	await physics_frame
	_expect_equal("stale split does not leak after stop", get_nodes_in_group("enemy").size(), 0)
	_expect_equal("stale split clears pending count", game.wave_manager.get_pending_deferred_spawn_count(), 0)


func _count_nodes_of_type(parent: Node, type_script: Variant) -> int:
	var count := 0
	for child in parent.get_children():
		if is_instance_of(child, type_script):
			count += 1
		count += _count_nodes_of_type(child, type_script)
	return count


func _expect_type_count(
	nodes: Array[Node],
	type_script: Variant,
	expected: int,
	label: String
) -> void:
	var count := 0
	for node in nodes:
		if is_instance_of(node, type_script):
			count += 1
	_expect_equal("%s type count" % label, count, expected)


func _expect_equal(label: String, actual: Variant, expected: Variant) -> void:
	if actual != expected:
		_failures.append("%s: expected %s, got %s" % [label, str(expected), str(actual)])


func _expect_close(label: String, actual: float, expected: float, epsilon: float) -> void:
	if absf(actual - expected) > epsilon:
		_failures.append("%s: expected %.4f, got %.4f" % [label, expected, actual])
