class_name PlayerController
extends CharacterBody2D

signal state_changed(previous_state: int, current_state: int)
signal health_changed(current_health: float, maximum_health: float)
signal player_died

enum PlayerState {
	MOVE,
	CHARGE,
	CANCEL_RECOVERY,
	SWING,
	DODGE,
	HURT,
	DEAD,
}

const CANCEL_RECOVERY_DURATION := 0.20
const CANCEL_MOVE_MULTIPLIER := 0.65
const DODGE_DURATION := 0.18
const DODGE_SPEED := 180.0
const DODGE_INVULNERABLE_START := 0.03
const DODGE_INVULNERABLE_END := 0.16
const HURT_DURATION := 0.18
const DAMAGE_INVULNERABILITY := 0.80
const CHARGING_ARMOR_REQUIRED_TIME := 0.60
const CHARGING_ARMOR_DAMAGE_MULTIPLIER := 0.65
const CHARGING_ARMOR_COOLDOWN := 4.0

@onready var visual_root: Node2D = $VisualRoot
@onready var player_sprite: Sprite2D = $VisualRoot/PlayerSprite
@onready var sword: SwordController = $SwordPivot
@onready var charge_meter: PlayerChargeMeter = $ChargeMeter

var _modifiers := RunModifiers.new()
var _state := PlayerState.MOVE
var _combat_input_enabled := false
var _last_aim_direction := Vector2.RIGHT
var _last_move_direction := Vector2.DOWN
var _move_phase := 0.0
var _idle_phase := 0.0
var _state_timer := 0.0
var _dodge_cooldown_remaining := 0.0
var _dodge_charges := 1
var _dodge_direction := Vector2.ZERO
var _next_afterimage_time := 0.0
var _dodge_tween: Tween
var _health := 100.0
var _damage_invulnerability_remaining := 0.0
var _hurt_velocity := Vector2.ZERO
var _hurt_flash_tween: Tween
var _charging_armor_cooldown := 0.0
var _weight_transfer_remaining := 0.0
var _footstep_distance := 0.0


func _ready() -> void:
	add_to_group("player")
	sword.set_owner_actor(self)
	sword.set_run_modifiers(_modifiers)
	sword.swing_finished.connect(_on_sword_swing_finished)
	sword.charge_changed.connect(charge_meter.set_charge_progress)
	_reset_visual_transform()


func _physics_process(delta: float) -> void:
	_update_aim()
	_update_dodge_recharge(delta)
	_damage_invulnerability_remaining = maxf(_damage_invulnerability_remaining - delta, 0.0)
	_charging_armor_cooldown = maxf(_charging_armor_cooldown - delta, 0.0)
	_weight_transfer_remaining = maxf(_weight_transfer_remaining - delta, 0.0)
	if not _combat_input_enabled:
		velocity = Vector2.ZERO
		move_and_slide()
		_update_visual_animation(delta, Vector2.ZERO)
		_update_walk_audio(false)
		return
	_handle_combat_input(delta)
	if _state == PlayerState.DODGE:
		_update_dodge(delta)
	elif _state == PlayerState.HURT:
		_update_hurt(delta)
	else:
		_update_standard_movement(delta)


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and _state == PlayerState.CHARGE:
		sword.cancel_charge()
		_set_state(PlayerState.MOVE)


func set_run_modifiers(modifiers: RunModifiers) -> void:
	var old_max := get_max_health()
	_modifiers = modifiers
	sword.set_run_modifiers(_modifiers)
	var new_max := get_max_health()
	if new_max > old_max:
		_health = minf(_health + new_max - old_max, new_max)
	health_changed.emit(_health, new_max)


func on_upgrade_applied(upgrade_id: StringName) -> void:
	if upgrade_id == &"sturdy_body":
		heal(20.0)
	elif upgrade_id == &"dodge_reserve":
		_dodge_charges = mini(_dodge_charges + 1, _modifiers.get_max_dodge_charges())
	else:
		health_changed.emit(_health, get_max_health())


func get_run_modifiers() -> RunModifiers:
	return _modifiers


func set_combat_input_enabled(enabled: bool) -> void:
	_combat_input_enabled = enabled
	if not enabled:
		velocity = Vector2.ZERO
		_update_walk_audio(false)
		if _state != PlayerState.DEAD:
			sword.reset_sword()
			_set_state(PlayerState.MOVE)


func reset_for_run(spawn_position: Vector2) -> void:
	global_position = spawn_position
	velocity = Vector2.ZERO
	_dodge_cooldown_remaining = 0.0
	_dodge_charges = _modifiers.get_max_dodge_charges()
	_state_timer = 0.0
	_last_aim_direction = Vector2.RIGHT
	_last_move_direction = Vector2.DOWN
	_move_phase = 0.0
	_idle_phase = 0.0
	_health = get_max_health()
	_damage_invulnerability_remaining = 0.0
	_charging_armor_cooldown = 0.0
	_weight_transfer_remaining = 0.0
	_footstep_distance = 0.0
	_hurt_velocity = Vector2.ZERO
	player_sprite.modulate = Color.WHITE
	sword.reset_sword()
	charge_meter.reset()
	_set_state(PlayerState.MOVE)
	_reset_visual_transform()
	health_changed.emit(_health, get_max_health())


func get_player_state() -> StringName:
	return StringName(PlayerState.keys()[_state])


func get_charge_progress() -> float:
	return sword.get_charge_progress()


func get_size_factor() -> float:
	return sword.get_size_factor()


func get_dodge_cooldown_remaining() -> float:
	return _dodge_cooldown_remaining


func get_dodge_cooldown_duration() -> float:
	return _modifiers.get_dodge_cooldown()


func get_dodge_charges() -> int:
	return _dodge_charges


func get_max_dodge_charges() -> int:
	return _modifiers.get_max_dodge_charges()


func get_next_dodge_recharge_progress() -> float:
	if _dodge_charges >= get_max_dodge_charges():
		return 1.0
	return 1.0 - clampf(
		_dodge_cooldown_remaining / maxf(get_dodge_cooldown_duration(), 0.01),
		0.0,
		1.0
	)


func get_health() -> float:
	return _health


func get_max_health() -> float:
	return _modifiers.get_max_health()


func get_health_ratio() -> float:
	return _health / maxf(get_max_health(), 1.0)


func heal(amount: float) -> float:
	if amount <= 0.0 or _state == PlayerState.DEAD:
		return 0.0
	var previous := _health
	_health = minf(_health + amount, get_max_health())
	health_changed.emit(_health, get_max_health())
	return _health - previous


func is_invulnerable() -> bool:
	if _damage_invulnerability_remaining > 0.0:
		return true
	if _state != PlayerState.DODGE:
		return false
	var elapsed := DODGE_DURATION - _state_timer
	return elapsed >= DODGE_INVULNERABLE_START and elapsed <= DODGE_INVULNERABLE_END


func take_hit(hit_data: HitData) -> bool:
	if _state == PlayerState.DEAD or is_invulnerable():
		return false
	var damage := hit_data.amount
	var charging_armor_guarded := false
	if (
		_modifiers.has(&"charging_armor")
		and _state == PlayerState.CHARGE
		and sword.get_charge_time() >= CHARGING_ARMOR_REQUIRED_TIME
		and _charging_armor_cooldown <= 0.0
	):
		damage *= CHARGING_ARMOR_DAMAGE_MULTIPLIER
		charging_armor_guarded = true
		_charging_armor_cooldown = CHARGING_ARMOR_COOLDOWN
		var feedback := get_tree().get_first_node_in_group("feedback_manager")
		if feedback != null and feedback.has_method("spawn_guard_flash"):
			feedback.spawn_guard_flash(global_position)
	_health = maxf(_health - damage, 0.0)
	health_changed.emit(_health, get_max_health())
	_damage_invulnerability_remaining = DAMAGE_INVULNERABILITY
	if _health <= 0.0:
		sword.reset_sword()
		velocity = Vector2.ZERO
		_set_state(PlayerState.DEAD)
		_combat_input_enabled = false
		_update_walk_audio(false)
		player_died.emit()
		return true
	if charging_armor_guarded:
		return true
	sword.reset_sword()
	_hurt_velocity = hit_data.knockback
	_state_timer = HURT_DURATION
	_set_state(PlayerState.HURT)
	_play_hurt_flash()
	var feedback_manager := get_tree().get_first_node_in_group("feedback_manager")
	if feedback_manager != null and feedback_manager.has_method("request_camera_shake"):
		feedback_manager.request_camera_shake(2.0, 0.12)
	return true


func notify_enemy_killed(hit_data: HitData) -> void:
	if (
		_modifiers.has(&"weight_transfer")
		and hit_data.source == self
		and CombatMath.is_tier_at_least(
			hit_data.charge_progress,
			CombatMath.SizeTier.LARGE
		)
	):
		_weight_transfer_remaining = 1.0


func _handle_combat_input(delta: float) -> void:
	match _state:
		PlayerState.MOVE:
			if Input.is_action_just_pressed("dodge") and _dodge_charges > 0:
				_start_dodge()
			elif Input.is_action_just_pressed("attack_charge"):
				sword.begin_charge()
				_set_state(PlayerState.CHARGE)
		PlayerState.CHARGE:
			sword.advance_charge(delta)
			if Input.is_action_just_pressed("dodge") and _dodge_charges > 0:
				sword.cancel_charge()
				_start_dodge()
			elif Input.is_action_just_pressed("attack_cancel"):
				sword.cancel_charge()
				_state_timer = CANCEL_RECOVERY_DURATION
				_set_state(PlayerState.CANCEL_RECOVERY)
			elif Input.is_action_just_released("attack_charge"):
				_set_state(PlayerState.SWING)
				sword.release_attack(_last_aim_direction)
		PlayerState.CANCEL_RECOVERY:
			_state_timer = maxf(_state_timer - delta, 0.0)
			if _state_timer <= 0.0:
				_set_state(PlayerState.MOVE)
		PlayerState.SWING, PlayerState.DODGE, PlayerState.HURT, PlayerState.DEAD:
			pass


func _update_standard_movement(delta: float) -> void:
	var input_vector := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	if input_vector.length_squared() > 0.0001:
		_last_move_direction = input_vector.normalized()
	var movement_multiplier := 1.0
	if _state == PlayerState.CHARGE or _state == PlayerState.SWING:
		movement_multiplier = sword.get_movement_multiplier()
		if _weight_transfer_remaining > 0.0:
			movement_multiplier = maxf(movement_multiplier, 1.0)
	elif _state == PlayerState.CANCEL_RECOVERY:
		movement_multiplier = CANCEL_MOVE_MULTIPLIER
	elif _state == PlayerState.HURT or _state == PlayerState.DEAD:
		movement_multiplier = 0.0
	velocity = input_vector * _modifiers.get_move_speed() * movement_multiplier
	var previous_position := global_position
	move_and_slide()
	var distance_moved := global_position.distance_to(previous_position)
	if distance_moved > 0.001:
		_move_phase += distance_moved * 0.42
		_emit_footstep_dust(distance_moved, 5.5)
	_update_visual_animation(delta, input_vector)
	_update_walk_audio(input_vector.length_squared() > 0.01)


func _update_aim() -> void:
	var aim_vector := get_global_mouse_position() - global_position
	if aim_vector.length_squared() > 0.25:
		_last_aim_direction = aim_vector.normalized()
	sword.set_aim_direction(_last_aim_direction)


func _update_visual_animation(delta: float, input_vector: Vector2) -> void:
	if _state == PlayerState.DODGE:
		return
	var target_rotation := 0.0
	var target_skew := 0.0
	var target_scale := Vector2.ONE
	if input_vector.length_squared() > 0.0001:
		var wave := sin(_move_phase)
		target_rotation = wave * deg_to_rad(3.0)
		target_skew = wave * 0.04
		target_scale = Vector2(1.0, 1.0 + absf(wave) * 0.035)
	else:
		_idle_phase += delta * TAU / 0.8
		target_scale.y = 1.0 + sin(_idle_phase) * 0.03
	if _state == PlayerState.CHARGE:
		var horizontal_sign := signf(_last_aim_direction.x)
		if is_zero_approx(horizontal_sign):
			horizontal_sign = 1.0
		target_skew -= horizontal_sign * 0.08 * sword.get_charge_progress()
	visual_root.position = Vector2.ZERO
	visual_root.rotation = lerp_angle(
		visual_root.rotation,
		target_rotation,
		minf(delta * 18.0, 1.0)
	)
	visual_root.skew = lerpf(visual_root.skew, target_skew, minf(delta * 18.0, 1.0))
	visual_root.scale = visual_root.scale.lerp(target_scale, minf(delta * 18.0, 1.0))


func _start_dodge() -> void:
	var input_vector := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	if input_vector.length_squared() > 0.0001:
		_dodge_direction = input_vector.normalized()
	elif _last_move_direction.length_squared() > 0.0001:
		_dodge_direction = _last_move_direction
	else:
		_dodge_direction = -_last_aim_direction
	_state_timer = DODGE_DURATION
	_dodge_charges = maxi(_dodge_charges - 1, 0)
	if _dodge_cooldown_remaining <= 0.0:
		_dodge_cooldown_remaining = _modifiers.get_dodge_cooldown()
	_next_afterimage_time = 0.02
	_set_state(PlayerState.DODGE)
	_play_dodge_visual()
	_play_audio(&"dodge")


func _update_dodge(delta: float) -> void:
	_state_timer = maxf(_state_timer - delta, 0.0)
	velocity = _dodge_direction * DODGE_SPEED
	var previous_position := global_position
	move_and_slide()
	_emit_footstep_dust(global_position.distance_to(previous_position), 7.0)
	var elapsed := DODGE_DURATION - _state_timer
	if elapsed >= _next_afterimage_time and _next_afterimage_time <= 0.12:
		_spawn_afterimage()
		_next_afterimage_time += 0.05
	if _state_timer <= 0.0:
		velocity = Vector2.ZERO
		_set_state(PlayerState.MOVE)
		_reset_visual_transform()


func _update_hurt(delta: float) -> void:
	_state_timer = maxf(_state_timer - delta, 0.0)
	velocity = _hurt_velocity
	move_and_slide()
	_hurt_velocity = _hurt_velocity.move_toward(Vector2.ZERO, 240.0 * delta)
	_update_visual_animation(delta, Vector2.ZERO)
	if _state_timer <= 0.0:
		velocity = Vector2.ZERO
		_set_state(PlayerState.MOVE)


func _play_hurt_flash() -> void:
	if is_instance_valid(_hurt_flash_tween):
		_hurt_flash_tween.kill()
	player_sprite.modulate = Color(1.0, 0.22, 0.22, 1.0)
	_hurt_flash_tween = create_tween()
	_hurt_flash_tween.tween_property(player_sprite, "modulate", Color.WHITE, 0.20)


func _play_dodge_visual() -> void:
	if is_instance_valid(_dodge_tween):
		_dodge_tween.kill()
	var tilt_sign := signf(_dodge_direction.x)
	if is_zero_approx(tilt_sign):
		tilt_sign = -signf(_dodge_direction.y)
	if is_zero_approx(tilt_sign):
		tilt_sign = 1.0
	_dodge_tween = create_tween()
	_dodge_tween.set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	_dodge_tween.set_parallel(true)
	_dodge_tween.tween_property(visual_root, "rotation", deg_to_rad(25.0) * tilt_sign, 0.04)
	_dodge_tween.tween_property(visual_root, "skew", 0.22 * tilt_sign, 0.04)
	_dodge_tween.tween_property(visual_root, "scale", Vector2(1.24, 0.74), 0.04)
	_dodge_tween.chain().set_parallel(true)
	_dodge_tween.tween_property(visual_root, "rotation", deg_to_rad(14.0) * tilt_sign, 0.10)
	_dodge_tween.tween_property(visual_root, "skew", 0.14 * tilt_sign, 0.10)
	_dodge_tween.tween_property(visual_root, "scale", Vector2(1.14, 0.84), 0.10)
	_dodge_tween.chain().set_parallel(true)
	_dodge_tween.tween_property(visual_root, "rotation", 0.0, 0.04)
	_dodge_tween.tween_property(visual_root, "skew", 0.0, 0.04)
	_dodge_tween.tween_property(visual_root, "scale", Vector2.ONE, 0.04)


func _spawn_afterimage() -> void:
	var ghost := Sprite2D.new()
	ghost.texture = player_sprite.texture
	ghost.region_enabled = player_sprite.region_enabled
	ghost.region_rect = player_sprite.region_rect
	ghost.centered = player_sprite.centered
	ghost.global_position = global_position
	ghost.global_rotation = visual_root.global_rotation
	ghost.scale = visual_root.global_scale
	ghost.skew = visual_root.skew
	ghost.modulate = Color(0.55, 0.85, 1.0, 0.45)
	ghost.z_index = 19
	get_parent().add_child(ghost)
	var tween := ghost.create_tween()
	tween.set_parallel(true)
	tween.tween_property(ghost, "modulate:a", 0.0, 0.16)
	tween.tween_property(ghost, "scale", ghost.scale * 0.85, 0.16)
	tween.finished.connect(ghost.queue_free)


func _on_sword_swing_finished() -> void:
	if _state == PlayerState.SWING:
		_set_state(PlayerState.MOVE)


func _set_state(new_state: int) -> void:
	if new_state == _state:
		return
	var previous := _state
	_state = new_state
	charge_meter.set_charging(_state == PlayerState.CHARGE)
	state_changed.emit(previous, _state)


func _reset_visual_transform() -> void:
	if is_instance_valid(_dodge_tween):
		_dodge_tween.kill()
	visual_root.position = Vector2.ZERO
	visual_root.rotation = 0.0
	visual_root.skew = 0.0
	visual_root.scale = Vector2.ONE


func _play_audio(event_id: StringName) -> void:
	var audio := get_tree().get_first_node_in_group("audio_manager")
	if audio != null and audio.has_method("play_game_sfx"):
		audio.play_game_sfx(event_id, global_position, 1.0)


func _update_walk_audio(moving: bool) -> void:
	var audio := get_tree().get_first_node_in_group("audio_manager")
	if audio != null and audio.has_method("set_player_walking"):
		audio.set_player_walking(moving and _state == PlayerState.MOVE)


func _update_dodge_recharge(delta: float) -> void:
	var maximum := get_max_dodge_charges()
	_dodge_charges = mini(_dodge_charges, maximum)
	if _dodge_charges >= maximum:
		_dodge_cooldown_remaining = 0.0
		return
	_dodge_cooldown_remaining = maxf(_dodge_cooldown_remaining - delta, 0.0)
	if _dodge_cooldown_remaining <= 0.0:
		_dodge_charges += 1
		if _dodge_charges < maximum:
			_dodge_cooldown_remaining = _modifiers.get_dodge_cooldown()


func _emit_footstep_dust(distance: float, interval: float) -> void:
	if distance <= 0.0:
		return
	_footstep_distance += distance
	if _footstep_distance < interval:
		return
	_footstep_distance = fmod(_footstep_distance, interval)
	var feedback := get_tree().get_first_node_in_group("feedback_manager")
	if feedback != null and feedback.has_method("spawn_footstep_dust"):
		feedback.spawn_footstep_dust(
			global_position + Vector2(0.0, 3.0),
			Color(0.64, 0.73, 0.82, 0.70),
			0.90
		)
