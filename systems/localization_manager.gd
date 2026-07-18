class_name LocalizationManager
extends Node

signal locale_changed(locale: StringName)

const SETTINGS_PATH := "user://settings.cfg"
const DEFAULT_LOCALE: StringName = &"en"
const SUPPORTED_LOCALES: Array[StringName] = [&"en", &"zh_CN"]

var _locale: StringName = DEFAULT_LOCALE


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group("localization_manager")
	var config := ConfigFile.new()
	if config.load(SETTINGS_PATH) == OK:
		_locale = _normalize_locale(
			StringName(config.get_value("localization", "locale", DEFAULT_LOCALE))
		)
	TranslationServer.set_locale(String(_locale))


func toggle_locale() -> void:
	set_locale(&"zh_CN" if _locale == &"en" else &"en")


func set_locale(locale: StringName, persist := true) -> void:
	var normalized := _normalize_locale(locale)
	_locale = normalized
	TranslationServer.set_locale(String(_locale))
	if persist:
		var config := ConfigFile.new()
		config.load(SETTINGS_PATH)
		config.set_value("localization", "locale", String(_locale))
		config.save(SETTINGS_PATH)
	locale_changed.emit(_locale)


func get_locale() -> StringName:
	return _locale


func get_switch_label() -> String:
	return "中文" if _locale == &"en" else "EN"


func _normalize_locale(locale: StringName) -> StringName:
	return locale if SUPPORTED_LOCALES.has(locale) else DEFAULT_LOCALE
