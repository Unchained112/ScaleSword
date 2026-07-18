extends SceneTree

var _failures: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var game := (load("res://levels/game.tscn") as PackedScene).instantiate() as GameFlowManager
	root.add_child(game)
	await process_frame
	_expect_equal("upgrade catalog size", game.upgrade_manager.get_all_definitions().size(), 27)
	_expect_equal("wave count", game.wave_manager.get_round_count(), 13)
	_expect_equal("round five boss", game.wave_manager.get_definition(5).boss_id, &"boss_void")
	_expect_equal("round nine boss", game.wave_manager.get_definition(9).boss_id, &"boss_core")
	_expect_equal("round thirteen boss", game.wave_manager.get_definition(13).boss_id, &"boss_rift")
	game.player.sword.begin_charge()
	_expect_equal("charge loop starts", game.audio_manager._charge_player.playing, true)
	_expect_close(
		"charge loop starts at audible volume",
		game.audio_manager._charge_player.volume_db,
		3.0,
		0.01
	)
	_expect_equal(
		"charge loop uses supplied asset",
		game.audio_manager._charge_player.stream.resource_path,
		"res://audio/sfx/game/human_charging_1_loop.wav"
	)
	game.player.sword.advance_charge(1.6)
	_expect_close(
		"charge loop becomes audible at full charge",
		game.audio_manager._charge_player.volume_db,
		9.0,
		0.01
	)
	game.player.sword.release_attack(Vector2.RIGHT)
	_expect_equal(
		"charge loop stops when the sword is released",
		game.audio_manager._charge_player.playing,
		false
	)
	game.player.sword.reset_sword()
	game.player.sword.begin_charge()
	game.player.sword.cancel_charge()
	_expect_equal(
		"charge loop stops when charge is cancelled",
		game.audio_manager._charge_player.playing,
		false
	)
	game.player.sword.begin_charge()
	game.player.sword.reset_sword()
	_expect_equal(
		"charge loop stops when the sword resets",
		game.audio_manager._charge_player.playing,
		false
	)
	game.audio_manager.set_player_walking(true)
	_expect_equal("walk loop starts", game.audio_manager._walk_player.playing, true)
	_expect_close(
		"walk loop uses audible volume",
		game.audio_manager._walk_player.volume_db,
		12.0,
		0.01
	)
	game.audio_manager.set_player_walking(false)
	_expect_equal("walk loop stops", game.audio_manager._walk_player.playing, false)
	_test_modifiers(game.upgrade_manager)
	game.wave_manager.start_round(1)
	await create_timer(0.75).timeout
	_expect_equal("round one first batch", game.wave_manager._get_alive_enemies().size(), 3)
	_expect_equal("round one total remaining", game.wave_manager.get_remaining(), 6)
	game.wave_manager.clear_all()
	await process_frame
	await _test_boss_assets_and_phases(game)
	await _test_void_boss_contact_safety(game)
	await _test_death_feedback(game)
	await _test_boss_cinematic_reset(game)
	_expect_equal("music players", game.audio_manager._music_players.size(), 4)
	game._return_to_main_menu()
	await process_frame
	_expect_close("time scale reset on menu", Engine.time_scale, 1.0, 0.001)
	_expect_close("camera zoom reset", game.camera.zoom.x, 2.0, 0.001)
	game.queue_free()
	await process_frame
	if _failures.is_empty():
		print("PASS: stage 4-5 systems")
		quit(0)
		return
	for failure in _failures:
		push_error(failure)
	quit(1)


func _test_modifiers(manager: UpgradeManager) -> void:
	manager.reset_for_run(123)
	for id in [
		&"swift_steps", &"sturdy_body", &"rapid_growth", &"scale_breakthrough",
		&"sharpened_edge", &"flexible_wrist", &"weight_impact", &"quick_roll",
	]:
		_expect_equal("select %s" % id, manager.select_upgrade(id), true)
	var modifiers := manager.modifiers
	_expect_close("move upgrade", modifiers.get_move_speed(), 77.0, 0.01)
	_expect_close("health upgrade", modifiers.get_max_health(), 120.0, 0.01)
	_expect_close("charge upgrade", modifiers.get_full_charge_time(), 1.408, 0.001)
	_expect_close("size upgrade", modifiers.get_max_size(), 3.25, 0.001)
	_expect_close("damage upgrade", modifiers.get_base_damage(), 23.0, 0.001)
	manager.select_upgrade(&"dodge_reserve")
	_expect_equal("dodge reserve adds charge", modifiers.get_max_dodge_charges(), 2)
	manager.select_upgrade(&"compressed_growth")
	_expect_close("compressed growth charge speed", modifiers.get_full_charge_time(), 0.88, 0.001)
	_expect_close("compressed growth reduces maximum size", modifiers.get_max_size(), 2.75, 0.001)
	_expect_equal("blood anchor locked without prerequisite", manager.select_upgrade(&"blood_anchor"), false)
	manager.select_upgrade(&"charging_armor")
	_expect_equal("blood anchor unlocks after armor", manager.select_upgrade(&"blood_anchor"), true)
	var large_progress := 0.79
	var colossal_progress := 0.80
	var large_base_move := CombatMath.move_multiplier(large_progress)
	var colossal_base_move := CombatMath.move_multiplier(colossal_progress)
	_expect_close(
		"blood anchor does not slow large charging",
		modifiers.apply_charge_movement_modifier(large_base_move, large_progress),
		large_base_move,
		0.001
	)
	_expect_close(
		"blood anchor limits colossal charging to 25 percent",
		modifiers.apply_charge_movement_modifier(colossal_base_move, colossal_progress),
		RunModifiers.BLOOD_ANCHOR_MOVE_MULTIPLIER,
		0.001
	)
	_expect_close(
		"blood anchor does not slow released swing",
		modifiers.apply_charge_movement_modifier(colossal_base_move, colossal_progress, false),
		colossal_base_move,
		0.001
	)
	_expect_equal("three upgrade choices", manager.create_choices(3).size(), 3)


func _test_boss_assets_and_phases(game: GameFlowManager) -> void:
	var void_boss := (
		(load("res://actors/bosses/void_charger.tscn") as PackedScene).instantiate()
		as VoidChargerBoss
	)
	game.enemies.add_child(void_boss)
	void_boss.global_position = Vector2(240, 90)
	_expect_equal("void boss flag", void_boss.is_boss, true)
	_expect_equal("void boss region", void_boss.sprite.region_rect, Rect2(104, 0, 8, 8))
	void_boss.queue_free()
	await process_frame
	var core := (
		(load("res://actors/bosses/proliferation_core.tscn") as PackedScene).instantiate()
		as ProliferationCoreBoss
	)
	game.wave_manager._active = true
	game.wave_manager._current_definition = game.wave_manager.get_definition(9)
	game.wave_manager._round_index = 9
	game.enemies.add_child(core)
	core.global_position = Vector2(240, 90)
	_expect_equal("core boss region", core.sprite.region_rect, Rect2(88, 0, 8, 8))
	core.take_hit(HitData.new(280.0, Vector2.ZERO, game.player, 1.0, 700))
	await process_frame
	_expect_equal("core spawns two clones at 70 percent", core._get_clones().size(), 2)
	core.take_hit(HitData.new(300.0, Vector2.ZERO, game.player, 1.0, 701))
	await process_frame
	_expect_equal("core fills clone cap at 40 percent", core._get_clones().size(), 4)
	for clone in core._get_clones():
		_expect_equal("forty percent clones are enraged", clone._enraged, true)
	var rift := (
		(load("res://actors/bosses/rift_weaver.tscn") as PackedScene).instantiate()
		as RiftWeaverBoss
	)
	game.enemies.add_child(rift)
	_expect_equal("rift boss region", rift.sprite.region_rect, Rect2(72, 0, 8, 8))
	_expect_close("rift boss hp", rift.get_max_health(), 1200.0, 0.01)
	game.wave_manager.clear_all()
	await process_frame


func _test_death_feedback(game: GameFlowManager) -> void:
	var chaser := (
		(load("res://actors/enemies/chaser.tscn") as PackedScene).instantiate()
		as ChaserEnemy
	)
	game.enemies.add_child(chaser)
	chaser.global_position = Vector2(180, 90)
	var before := game.effects.get_child_count()
	chaser.take_hit(HitData.new(999.0, Vector2.ZERO, game.player, 2.0, 800))
	await process_frame
	_expect_equal("normal enemy freed after death", is_instance_valid(chaser), false)
	if game.effects.get_child_count() <= before:
		_failures.append("death particles did not outlive enemy node")
	await create_timer(0.45).timeout


func _test_void_boss_contact_safety(game: GameFlowManager) -> void:
	game.wave_manager.clear_all()
	await process_frame
	game.player.reset_for_run(Vector2(160.0, 90.0))
	var boss := (
		(load("res://actors/bosses/void_charger.tscn") as PackedScene).instantiate()
		as VoidChargerBoss
	)
	game.enemies.add_child(boss)
	boss.global_position = Vector2(190.0, 90.0)
	await physics_frame
	var health_before := game.player.get_health()
	boss._start_dash(false, 0.01)
	await create_timer(0.38).timeout
	_expect_close(
		"void dash deals one hit",
		game.player.get_health(),
		health_before - 21.0,
		0.01
	)
	_expect_equal(
		"void dash enters recovery after player collision",
		boss._state,
		VoidChargerBoss.BossState.RECOVERY
	)
	var health_after_dash := game.player.get_health()
	await create_timer(1.20).timeout
	_expect_close(
		"void recovery contact deals no repeated damage",
		game.player.get_health(),
		health_after_dash,
		0.01
	)
	var unsafe_target := game.player.global_position
	var safe_target := boss._get_safe_position_around_player(unsafe_target, 24.0, 28.0)
	if safe_target.distance_to(game.player.global_position) < 24.0:
		_failures.append("void teleport safety did not preserve 24 px separation")
	boss.queue_free()
	await process_frame
	game.player.reset_for_run(Vector2(160.0, 90.0))
	var invulnerable_boss := (
		(load("res://actors/bosses/void_charger.tscn") as PackedScene).instantiate()
		as VoidChargerBoss
	)
	game.enemies.add_child(invulnerable_boss)
	invulnerable_boss.global_position = Vector2(190.0, 90.0)
	game.player._damage_invulnerability_remaining = 1.0
	invulnerable_boss._start_dash(false, 0.01)
	await create_timer(0.38).timeout
	_expect_close(
		"invulnerable dash contact deals no damage",
		game.player.get_health(),
		game.player.get_max_health(),
		0.01
	)
	_expect_equal(
		"invulnerable contact still ends dash",
		invulnerable_boss._state,
		VoidChargerBoss.BossState.RECOVERY
	)
	game.wave_manager.clear_all()
	await process_frame


func _test_boss_cinematic_reset(game: GameFlowManager) -> void:
	game.feedback_manager.play_boss_death_sequence(Vector2(160, 90))
	await process_frame
	_expect_close("boss cinematic slow motion", Engine.time_scale, 0.25, 0.001)
	await create_timer(0.90, true, false, true).timeout
	_expect_close("boss cinematic restores time", Engine.time_scale, 1.0, 0.001)
	_expect_close("boss cinematic restores zoom", game.camera.zoom.x, 2.0, 0.001)


func _expect_equal(label: String, actual: Variant, expected: Variant) -> void:
	if actual != expected:
		_failures.append("%s: expected %s, got %s" % [label, str(expected), str(actual)])


func _expect_close(label: String, actual: float, expected: float, epsilon: float) -> void:
	if absf(actual - expected) > epsilon:
		_failures.append("%s: expected %.4f, got %.4f" % [label, expected, actual])
