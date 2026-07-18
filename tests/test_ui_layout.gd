extends SceneTree

const VIEWPORT_RECT := Rect2(Vector2.ZERO, Vector2(640.0, 360.0))

var _failures: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var game := (load("res://levels/game.tscn") as PackedScene).instantiate() as GameFlowManager
	root.add_child(game)
	await process_frame
	await process_frame
	_check_control_inside("main menu panel", game.main_menu.get_node("Panel") as Control)
	_check_control_inside(
		"language button",
		game.main_menu.get_node("LanguageButton") as Control
	)
	var background := game.main_menu.get_node("Background") as ColorRect
	_expect_color("menu floor gray", background.color, Color("#222323"))
	var theme := game.main_menu.theme
	_expect_true("shared theme assigned", theme != null)
	_expect_true(
		"regular default font assigned",
		theme.get_default_font() != null
	)
	_expect_true(
		"bold button font assigned",
		theme.get_font(&"font", &"Button") != null
	)
	_expect_true(
		"menu starts without forced focus",
		game.main_menu.get_viewport().gui_get_focus_owner() == null
	)
	_expect_true(
		"menu subtitle removed",
		not game.main_menu.has_node("Panel/Margins/Content/Subtitle")
	)
	var menu_panel := game.main_menu.get_node("Panel") as Control
	_expect_true(
		"menu frame fills the viewport",
		menu_panel.size.x >= 610.0 and menu_panel.size.y >= 330.0
	)
	_expect_true(
		"focus and hover use distinct styles",
		theme.get_stylebox(&"focus", &"Button")
		!= theme.get_stylebox(&"hover", &"Button")
	)
	var menu_key := InputEventKey.new()
	menu_key.pressed = true
	menu_key.keycode = KEY_DOWN
	game.main_menu._unhandled_key_input(menu_key)
	_expect_true(
		"keyboard input lazily focuses start",
		game.main_menu.get_viewport().gui_get_focus_owner()
		== game.main_menu.start_button
	)
	game.main_menu.start_button.release_focus()
	_expect_true(
		"charge meter is world-space player child",
		game.player.charge_meter.get_parent() == game.player
		and game.player.charge_meter.get_parent() != game.player.visual_root
	)
	_expect_true(
		"screen charge panel removed",
		not game.run_hud.has_node("ChargePanel")
	)
	var boss_panel := game.run_hud.get_node("BossPanel") as Control
	_expect_true(
		"boss panel anchored to bottom",
		is_equal_approx(boss_panel.anchor_top, 1.0)
		and boss_panel.offset_bottom < 0.0
	)

	game.upgrade_manager.reset_for_run(11274)
	var choices := game.upgrade_manager.create_choices(3)
	game.upgrade_selection.show_choices(choices, game.upgrade_manager, 1)
	await process_frame
	_check_control_inside(
		"upgrade panel",
		game.upgrade_selection.get_node("Panel") as Control
	)
	var cards := game.upgrade_selection.cards
	_expect_equal("upgrade card count", cards.get_child_count(), 3)
	_expect_true(
		"upgrade cards start without forced focus",
		game.upgrade_selection.get_viewport().gui_get_focus_owner() == null
	)
	var card_key := InputEventKey.new()
	card_key.pressed = true
	card_key.keycode = KEY_RIGHT
	game.upgrade_selection._unhandled_key_input(card_key)
	_expect_true(
		"keyboard input lazily focuses first card",
		game.upgrade_selection.get_viewport().gui_get_focus_owner()
		== cards.get_child(0)
	)
	(cards.get_child(0) as UpgradeCard).release_focus()
	for index in cards.get_child_count():
		var card := cards.get_child(index) as UpgradeCard
		_expect_true("card %d type" % index, card != null)
		if card == null:
			continue
		_expect_true("card %d width" % index, card.size.x >= 174.0)
		_expect_true("card %d height" % index, card.size.y >= 196.0)
		_expect_true(
			"card %d description" % index,
			not card.description_label.text.is_empty()
		)
		_expect_true(
			"card %d index removed" % index,
			not card.has_node("Margins/VBox/IndexLabel")
		)
		_expect_true(
			"card %d abbreviation removed" % index,
			not card.has_node("Margins/VBox/IconLabel")
		)
	var hover_card := cards.get_child(0) as UpgradeCard
	hover_card._on_mouse_entered()
	await create_timer(0.14).timeout
	_expect_true(
		"card hover grows from center",
		hover_card.scale.x > 1.03
		and hover_card.pivot_offset.is_equal_approx(hover_card.size * 0.5)
	)
	hover_card._on_mouse_exited()
	await create_timer(0.12).timeout
	_expect_true(
		"card hover restores scale",
		hover_card.scale.is_equal_approx(Vector2.ONE)
	)

	for locale in [&"en", &"zh_CN"]:
		game.localization_manager.set_locale(locale, false)
		await process_frame
		_check_control_inside(
			"%s main menu panel" % locale,
			game.main_menu.get_node("Panel") as Control
		)
		_check_control_inside(
			"%s upgrade panel" % locale,
			game.upgrade_selection.get_node("Panel") as Control
		)
		for child in game.upgrade_selection.cards.get_children():
			var card := child as UpgradeCard
			_expect_true(
				"%s card title" % locale,
				card != null and not card.title_label.text.is_empty()
			)

	game.upgrade_selection.hide()
	game.pause_overlay.show()
	await process_frame
	_check_control_inside(
		"pause panel",
		game.pause_overlay.get_node("Panel") as Control
	)
	game.pause_overlay.hide()
	game.run_result.show_result(true, game.get_run_stats())
	await process_frame
	_check_control_inside(
		"result panel",
		game.run_result.get_node("Panel") as Control
	)

	game.queue_free()
	await process_frame
	if _failures.is_empty():
		print("PASS: UI theme and 640x360 layout")
		quit(0)
		return
	for failure in _failures:
		push_error(failure)
	quit(1)


func _check_control_inside(label: String, control: Control) -> void:
	_expect_true("%s exists" % label, control != null)
	if control == null:
		return
	var rect := control.get_global_rect()
	_expect_true(
		"%s inside viewport: %s" % [label, rect],
		VIEWPORT_RECT.encloses(rect)
	)


func _expect_color(label: String, actual: Color, expected: Color) -> void:
	if not actual.is_equal_approx(expected):
		_failures.append("%s: expected %s, got %s" % [label, expected, actual])


func _expect_equal(label: String, actual: Variant, expected: Variant) -> void:
	if actual != expected:
		_failures.append("%s: expected %s, got %s" % [label, expected, actual])


func _expect_true(label: String, condition: bool) -> void:
	if not condition:
		_failures.append(label)
