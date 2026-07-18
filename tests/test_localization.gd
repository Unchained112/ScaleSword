extends SceneTree

var _failures: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var game := (load("res://levels/game.tscn") as PackedScene).instantiate() as GameFlowManager
	root.add_child(game)
	await process_frame
	var localization := game.localization_manager
	var original_locale := localization.get_locale()
	localization.set_locale(&"en", false)
	await process_frame
	_expect_equal("english menu title", game.main_menu.start_button.text, "START GAME")
	_expect_equal("english switch label", game.main_menu.language_button.text, "中文")
	_validate_catalog(game.upgrade_manager, &"en")
	localization.set_locale(&"zh_CN", false)
	await process_frame
	_expect_equal("chinese menu title", game.main_menu.start_button.text, "开始游戏")
	_expect_equal("chinese switch label", game.main_menu.language_button.text, "EN")
	_expect_equal("chinese pause title", game.pause_title.text, "已暂停")
	_validate_catalog(game.upgrade_manager, &"zh_CN")
	localization.set_locale(&"zh_CN", true)
	var config := ConfigFile.new()
	_expect_equal("settings file loads", config.load(LocalizationManager.SETTINGS_PATH), OK)
	_expect_equal(
		"locale persists",
		String(config.get_value("localization", "locale", "")),
		"zh_CN"
	)
	localization.set_locale(original_locale, true)
	game.queue_free()
	await process_frame
	if _failures.is_empty():
		print("PASS: localization")
		quit(0)
		return
	for failure in _failures:
		push_error(failure)
	quit(1)


func _validate_catalog(manager: UpgradeManager, locale: StringName) -> void:
	TranslationServer.set_locale(String(locale))
	for definition in manager.get_all_definitions():
		for key in [
			definition.title_key,
			definition.description_key,
			definition.category_key,
		]:
			var translated := TranslationServer.translate(String(key))
			if translated == String(key) or translated.is_empty():
				_failures.append("%s missing translation for %s" % [locale, key])
	for round_index in range(1, 14):
		var round_key: StringName = GameFlowManager.ROUND_NAMES[round_index]
		var translated_round := TranslationServer.translate(String(round_key))
		if translated_round == String(round_key):
			_failures.append("%s missing translation for %s" % [locale, round_key])
	for boss_key in [
		&"BOSS_VOID_CHARGER",
		&"BOSS_PROLIFERATION_CORE",
		&"BOSS_RIFT_WEAVER",
	]:
		if TranslationServer.translate(String(boss_key)) == String(boss_key):
			_failures.append("%s missing translation for %s" % [locale, boss_key])


func _expect_equal(label: String, actual: Variant, expected: Variant) -> void:
	if actual != expected:
		_failures.append("%s: expected %s, got %s" % [label, str(expected), str(actual)])
