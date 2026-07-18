extends SceneTree

var _failures: Array[String] = []


func _initialize() -> void:
	_run()


func _run() -> void:
	_expect_close("charge at zero", CombatMath.charge_progress(0.0), 0.0)
	_expect_close("charge at half", CombatMath.charge_progress(0.8), 0.5)
	_expect_close("charge at full", CombatMath.charge_progress(1.6), 1.0)
	_expect_close("charge clamps over full", CombatMath.charge_progress(99.0), 1.0)

	_expect_close("size at zero", CombatMath.size_factor_from_progress(0.0), 1.5)
	_expect_close("size at half", CombatMath.size_factor_from_progress(0.5), 2.25)
	_expect_close("size at full", CombatMath.size_factor_from_progress(1.0), 3.0)

	_expect_close("move at zero", CombatMath.move_multiplier(0.0), 1.0)
	_expect_close("move at half", CombatMath.move_multiplier(0.5), 0.85)
	_expect_close("move at full", CombatMath.move_multiplier(1.0), 0.45)

	_expect_close(
		"damage at base size",
		CombatMath.damage_for_size(1.5),
		20.0 * (0.65 + 0.35 * pow(1.5, 1.6))
	)
	_expect_close(
		"damage at size two",
		CombatMath.damage_for_size(2.0),
		20.0 * (0.65 + 0.35 * pow(2.0, 1.6))
	)
	_expect_close(
		"damage at size three",
		CombatMath.damage_for_size(3.0),
		20.0 * (0.65 + 0.35 * pow(3.0, 1.6))
	)

	_expect_close("swing at zero", CombatMath.swing_duration(0.0), 0.22)
	_expect_close("swing at half", CombatMath.swing_duration(0.5), 0.385)
	_expect_close("swing at full", CombatMath.swing_duration(1.0), 0.55)
	_expect_equal("small tier starts at zero", CombatMath.get_size_tier(0.0), CombatMath.SizeTier.SMALL)
	_expect_equal("medium tier boundary", CombatMath.get_size_tier(0.25), CombatMath.SizeTier.MEDIUM)
	_expect_equal("large tier boundary", CombatMath.get_size_tier(0.50), CombatMath.SizeTier.LARGE)
	_expect_equal("colossal tier boundary", CombatMath.get_size_tier(0.80), CombatMath.SizeTier.COLOSSAL)

	if _failures.is_empty():
		print("PASS: combat math")
		quit(0)
		return
	for failure in _failures:
		push_error(failure)
	quit(1)


func _expect_close(label: String, actual: float, expected: float, epsilon := 0.0001) -> void:
	if absf(actual - expected) > epsilon:
		_failures.append("%s: expected %.6f, got %.6f" % [label, expected, actual])


func _expect_equal(label: String, actual: Variant, expected: Variant) -> void:
	if actual != expected:
		_failures.append("%s: expected %s, got %s" % [label, str(expected), str(actual)])
