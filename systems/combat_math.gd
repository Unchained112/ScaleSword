class_name CombatMath
extends RefCounted

const BASE_DAMAGE := 20.0
const FULL_CHARGE_TIME := 1.6
enum SizeTier {
	SMALL,
	MEDIUM,
	LARGE,
	COLOSSAL,
}

const MIN_SIZE := 1.5
const MAX_SIZE := 3.0
const MIN_MOVE_MULTIPLIER := 0.45
const MIN_SWING_DURATION := 0.22
const MAX_SWING_DURATION := 0.55
const MIN_KNOCKBACK := 22.0
const MAX_KNOCKBACK := 70.0


static func charge_progress(charge_time: float, full_charge_time := FULL_CHARGE_TIME) -> float:
	return clampf(charge_time / maxf(full_charge_time, 0.05), 0.0, 1.0)


static func size_factor_from_progress(progress: float, maximum_size := MAX_SIZE) -> float:
	return lerpf(MIN_SIZE, maximum_size, clampf(progress, 0.0, 1.0))


static func move_multiplier(progress: float) -> float:
	var safe_progress := clampf(progress, 0.0, 1.0)
	if safe_progress <= 0.5:
		return lerpf(1.0, 0.85, safe_progress / 0.5)
	return lerpf(0.85, MIN_MOVE_MULTIPLIER, (safe_progress - 0.5) / 0.5)


static func get_size_tier(progress: float) -> SizeTier:
	var safe_progress := clampf(progress, 0.0, 1.0)
	if safe_progress < 0.25:
		return SizeTier.SMALL
	if safe_progress < 0.50:
		return SizeTier.MEDIUM
	if safe_progress < 0.80:
		return SizeTier.LARGE
	return SizeTier.COLOSSAL


static func is_tier_at_least(progress: float, tier: SizeTier) -> bool:
	return get_size_tier(progress) >= tier


static func damage_for_size(
	size_factor: float,
	base_damage := BASE_DAMAGE,
	maximum_size := MAX_SIZE
) -> float:
	var safe_size := clampf(size_factor, MIN_SIZE, maximum_size)
	return base_damage * (0.65 + 0.35 * pow(safe_size, 1.6))


static func swing_duration(progress: float) -> float:
	return lerpf(MIN_SWING_DURATION, MAX_SWING_DURATION, clampf(progress, 0.0, 1.0))


static func knockback_for_progress(progress: float) -> float:
	return lerpf(MIN_KNOCKBACK, MAX_KNOCKBACK, clampf(progress, 0.0, 1.0))


static func hit_stop_for_size(size_factor: float) -> float:
	if size_factor >= 2.4:
		return 0.070
	if size_factor >= 1.5:
		return 0.045
	return 0.025


static func shake_amplitude_for_size(size_factor: float) -> float:
	if size_factor >= 2.4:
		return 5.0
	if size_factor >= 1.5:
		return 3.0
	return 1.5
