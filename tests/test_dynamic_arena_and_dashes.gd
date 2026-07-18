extends SceneTree

var _failures: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var game := (load("res://levels/game.tscn") as PackedScene).instantiate() as GameFlowManager
	root.add_child(game)
	await process_frame
	_expect_equal(
		"arena is derived from current walls",
		game.arena_bounds.get_interior_rect(),
		Rect2(66.0, 32.0, 196.0, 104.0)
	)
	for index in 24:
		var point := game.wave_manager._choose_spawn_point()
		if not game.arena_bounds.get_safe_rect(10.0).grow(0.01).has_point(point):
			_failures.append("spawn point escaped dynamic safe rect: %s" % point)
			break
	await _test_charger_player_and_wall_recovery(game)
	await _test_void_wall_recovery(game)
	await _test_core_clone_physics_spawn(game)
	await _test_rift_path_bounds(game)
	game.queue_free()
	await process_frame
	if _failures.is_empty():
		print("PASS: dynamic arena and dash stability")
		quit(0)
		return
	for failure in _failures:
		push_error(failure)
	quit(1)


func _test_charger_player_and_wall_recovery(game: GameFlowManager) -> void:
	game.wave_manager.clear_all()
	await process_frame
	game.player.reset_for_run(Vector2(118.0, 90.0))
	game.player._damage_invulnerability_remaining = 1.0
	var charger := (
		(load("res://actors/enemies/charger.tscn") as PackedScene).instantiate()
		as ChargerEnemy
	)
	game.enemies.add_child(charger)
	charger.global_position = Vector2(92.0, 90.0)
	charger._dash_direction = Vector2.RIGHT
	charger._begin_dash()
	await create_timer(0.35).timeout
	_expect_equal(
		"invulnerable player still ends charger dash",
		charger._charge_state,
		ChargerEnemy.ChargeState.RECOVERY
	)
	charger.queue_free()
	await process_frame
	var wall_charger := (
		(load("res://actors/enemies/heavy_charger.tscn") as PackedScene).instantiate()
		as ChargerEnemy
	)
	game.enemies.add_child(wall_charger)
	wall_charger.global_position = Vector2(250.0, 90.0)
	wall_charger._dash_direction = Vector2.RIGHT
	wall_charger._begin_dash()
	await create_timer(0.25).timeout
	_expect_equal(
		"charger enters recovery after wall",
		wall_charger._charge_state,
		ChargerEnemy.ChargeState.RECOVERY
	)
	if wall_charger.global_position.x > game.arena_bounds.get_safe_rect(6.0).end.x + 0.01:
		_failures.append("charger visual center escaped arena after wall")


func _test_void_wall_recovery(game: GameFlowManager) -> void:
	game.wave_manager.clear_all()
	await process_frame
	var boss := (
		(load("res://actors/bosses/void_charger.tscn") as PackedScene).instantiate()
		as VoidChargerBoss
	)
	game.enemies.add_child(boss)
	boss.global_position = Vector2(246.0, 72.0)
	boss._long_dash = true
	boss._dash_direction = Vector2.RIGHT
	boss._dash_length = 140.0
	boss._dash_speed = 172.0
	boss._dash_damage = 28.0
	boss._begin_dash()
	await create_timer(0.25).timeout
	_expect_equal(
		"void boss recovers after wall",
		boss._state,
		VoidChargerBoss.BossState.RECOVERY
	)
	if boss.global_position.x > game.arena_bounds.get_safe_rect(14.0).end.x + 0.01:
		_failures.append("void boss escaped visual safe rect")


func _test_core_clone_physics_spawn(game: GameFlowManager) -> void:
	game.wave_manager.clear_all()
	await process_frame
	game.wave_manager._active = true
	game.wave_manager._current_definition = game.wave_manager.get_definition(9)
	game.wave_manager._round_index = 9
	game.player.reset_for_run(Vector2(160.0, 90.0))
	var core := (
		(load("res://actors/bosses/proliferation_core.tscn") as PackedScene).instantiate()
		as ProliferationCoreBoss
	)
	game.enemies.add_child(core)
	core.global_position = Vector2(174.0, 90.0)
	core.set_physics_process(false)
	core.take_hit(HitData.new(260.0, Vector2.ZERO, game.player, 1.5, 7000, 0.0))
	game.player.sword.begin_charge()
	game.player.sword.release_attack(Vector2.RIGHT)
	await create_timer(0.42).timeout
	await physics_frame
	await process_frame
	_expect_equal("core physics hit spawns two deferred clones", core._get_clones().size(), 2)
	_expect_equal(
		"core deferred clone queue drains",
		game.wave_manager.get_pending_deferred_spawn_count(),
		0
	)


func _test_rift_path_bounds(game: GameFlowManager) -> void:
	game.wave_manager.clear_all()
	await process_frame
	var rift := (
		(load("res://actors/bosses/rift_weaver.tscn") as PackedScene).instantiate()
		as RiftWeaverBoss
	)
	game.enemies.add_child(rift)
	rift.set_physics_process(false)
	rift.global_position = game.arena_bounds.get_safe_rect(20.0).get_center()
	var safe_rect := game.arena_bounds.get_safe_rect(20.0)
	var player_direction := Vector2(0.73, 0.41).normalized()
	var path := rift._build_reflection_path(
		rift.global_position,
		player_direction,
		3
	)
	_expect_equal("rift three reflections create four legs", path.size(), 4)
	var previous := rift.global_position
	for point in path:
		if not safe_rect.grow(0.01).has_point(point):
			_failures.append("rift path point escaped dynamic arena: %s" % point)
			break
		if previous.distance_to(point) < 2.0:
			_failures.append("rift reflection produced a zero-length segment")
			break
		previous = point
	if not path.is_empty():
		var actual_first_direction := (path[0] - rift.global_position).normalized()
		_expect_true(
			"rift first leg aims at player direction",
			actual_first_direction.dot(player_direction) > 0.999
		)
	var corner_direction := (
		safe_rect.end - safe_rect.get_center()
	).normalized()
	var corner_path := rift._build_reflection_path(
		safe_rect.get_center(),
		corner_direction,
		3
	)
	_expect_equal("rift corner route remains finite", corner_path.size(), 4)
	for point in corner_path:
		_expect_true(
			"rift corner point is finite",
			is_finite(point.x) and is_finite(point.y)
		)
	rift._path_origin = rift.global_position
	rift._path_points = path
	rift._cache_telegraph_lengths()
	rift._create_path_telegraphs()
	_expect_equal(
		"rift creates one rectangular warning per route segment",
		rift._path_telegraphs.size(),
		path.size()
	)
	for telegraph in rift._path_telegraphs:
		_expect_true(
			"rift warning matches route damage width",
			is_equal_approx(
				telegraph._path_width,
				rift._get_route_damage_width()
			)
		)
		_expect_true(
			"rift warning uses translucent purple fill",
			telegraph._fill_color.b > telegraph._fill_color.r
			and telegraph._fill_color.a < 0.5
			and telegraph._edge_color.a > telegraph._fill_color.a
		)
	rift._clear_path_telegraphs()
	_test_rift_targeted_fans(game, rift)


func _test_rift_targeted_fans(
	game: GameFlowManager,
	rift: RiftWeaverBoss
) -> void:
	game.player.global_position = rift.global_position + Vector2(34.0, -7.0)
	game.player.velocity = Vector2.ZERO
	for phase in [
		{"health": 1200.0, "count": 3},
		{"health": 600.0, "count": 5},
		{"health": 300.0, "count": 3},
	]:
		for bullet in get_nodes_in_group("enemy_bullet"):
			bullet.free()
		rift._health = phase["health"]
		rift._fire_vertex_fan()
		var bullets := get_nodes_in_group("enemy_bullet")
		_expect_equal(
			"rift phase fan count at health %d" % int(phase["health"]),
			bullets.size(),
			phase["count"]
		)
		var target_direction := (
			game.player.global_position - rift.global_position
		).normalized()
		var best_alignment := -1.0
		for bullet in bullets:
			var enemy_bullet := bullet as EnemyBullet
			if enemy_bullet != null:
				best_alignment = maxf(
					best_alignment,
					enemy_bullet._velocity.normalized().dot(target_direction)
				)
		_expect_true(
			"rift fan keeps a center projectile aimed at player",
			best_alignment > 0.999
		)
	for bullet in get_nodes_in_group("enemy_bullet"):
		bullet.free()
	rift._path_reflection_count = 2
	rift._health = 1200.0
	_expect_true(
		"rift phase one fires only at its first reflection",
		rift._should_fire_vertex_fan(0)
		and not rift._should_fire_vertex_fan(1)
	)
	rift._path_reflection_count = 3
	rift._health = 600.0
	_expect_true(
		"rift later phases alternate reflection volleys",
		rift._should_fire_vertex_fan(0)
		and not rift._should_fire_vertex_fan(1)
		and rift._should_fire_vertex_fan(2)
	)
	_expect_close(
		"rift middle phase recovery window",
		rift._get_path_recovery_duration(),
		1.15,
		0.001
	)
	rift._health = 300.0
	_expect_true(
		"rift final phase fires two lighter volleys",
		rift._should_fire_vertex_fan(0)
		and not rift._should_fire_vertex_fan(1)
		and rift._should_fire_vertex_fan(2)
	)
	_expect_close(
		"rift final phase recovery window",
		rift._get_path_recovery_duration(),
		1.80,
		0.001
	)
	_expect_close(
		"rift final phase idle interval",
		rift._get_path_idle_duration(),
		1.15,
		0.001
	)


func _expect_true(label: String, condition: bool) -> void:
	if not condition:
		_failures.append(label)


func _expect_equal(label: String, actual: Variant, expected: Variant) -> void:
	if actual != expected:
		_failures.append("%s: expected %s, got %s" % [label, str(expected), str(actual)])


func _expect_close(
	label: String,
	actual: float,
	expected: float,
	epsilon: float
) -> void:
	if absf(actual - expected) > epsilon:
		_failures.append("%s: expected %.3f, got %.3f" % [label, expected, actual])
