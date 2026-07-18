class_name ProliferationClone
extends ChargerEnemy

var _absorb_frozen := false
var _enraged := false
var _spawn_time_msec := 0


func _ready() -> void:
	super._ready()
	add_to_group("boss_clone")
	_spawn_time_msec = Time.get_ticks_msec()


func _tick_behavior(delta: float) -> void:
	if _absorb_frozen:
		set_desired_velocity(Vector2.ZERO)
		return
	super._tick_behavior(delta)


func set_absorb_frozen(frozen: bool) -> void:
	_absorb_frozen = frozen
	if frozen:
		set_charge_visual(0.8, 1.18)
	else:
		clear_charge_visual()


func set_enraged() -> void:
	if _enraged:
		return
	_enraged = true
	move_speed *= 1.25
	dash_speed *= 1.25
	dash_cooldown *= 0.80
	sprite.modulate = Color(1.0, 0.62, 0.42, 1.0)


func get_active_duration() -> float:
	return float(Time.get_ticks_msec() - _spawn_time_msec) / 1000.0
