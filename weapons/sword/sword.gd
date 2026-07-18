class_name SwordController
extends Node2D

signal charge_changed(progress: float, size_factor: float)
signal swing_started(size_factor: float)
signal attack_hit(target: Node, damage: float, size_factor: float)
signal swing_finished

const BASE_HITBOX_SIZE := Vector2(10.0, 4.0)
const BASE_HITBOX_CENTER_X := 5.5

@onready var visual_root: Node2D = $VisualRoot
@onready var sword_sprite: Sprite2D = $VisualRoot/SwordSprite
@onready var attack_area: Area2D = $AttackArea
@onready var hitbox_shape: CollisionShape2D = $AttackArea/CollisionShape2D

var _owner_actor: PlayerController
var _modifiers := RunModifiers.new()
var _charge_time := 0.0
var _charge_progress := 0.0
var _size_factor := CombatMath.MIN_SIZE
var _locked_move_multiplier := 1.0
var _locked_aim_direction := Vector2.RIGHT
var _is_charging := false
var _is_swinging := false
var _is_backswing := false
var _attack_sequence := 0
var _hit_instance_ids: Dictionary = {}
var _targets_hit_this_attack := 0
var _quake_used := false
var _swing_tween: Tween
var _combo_target_id := 0
var _combo_stacks := 0
var _combo_expires_msec := 0
var _lifesteal_this_release := 0.0


func _ready() -> void:
	attack_area.monitoring = false
	attack_area.body_entered.connect(_on_attack_area_body_entered)
	attack_area.area_entered.connect(_on_attack_area_area_entered)
	_apply_size(CombatMath.MIN_SIZE)


func _process(_delta: float) -> void:
	if _combo_target_id != 0 and Time.get_ticks_msec() >= _combo_expires_msec:
		_clear_combo()


func set_owner_actor(actor: PlayerController) -> void:
	_owner_actor = actor


func set_run_modifiers(modifiers: RunModifiers) -> void:
	_modifiers = modifiers
	if not _is_charging and not _is_swinging:
		_apply_size(CombatMath.MIN_SIZE)


func set_aim_direction(direction: Vector2) -> void:
	if _is_swinging or direction.length_squared() < 0.0001:
		return
	rotation = direction.angle()


func begin_charge() -> void:
	if _is_swinging:
		return
	_is_charging = true
	_charge_time = 0.0
	_charge_progress = 0.0
	_apply_size(CombatMath.MIN_SIZE)
	charge_changed.emit(_charge_progress, _size_factor)
	_play_audio(&"charge_start", 1.0)


func advance_charge(delta: float) -> void:
	if not _is_charging:
		return
	var charge_rate := 1.0
	if (
		_modifiers.has(&"desperate_charge")
		and is_instance_valid(_owner_actor)
		and _owner_actor.get_health_ratio() < 0.35
	):
		charge_rate = 1.30
	_charge_time += delta * charge_rate
	_charge_progress = CombatMath.charge_progress(
		_charge_time,
		_modifiers.get_full_charge_time()
	)
	_apply_size(
		CombatMath.size_factor_from_progress(
			_charge_progress,
			_modifiers.get_max_size()
		)
	)
	var pulse := sin(Time.get_ticks_msec() * 0.012) * 0.08 * _charge_progress
	sword_sprite.modulate = Color(
		1.0 + pulse,
		1.0,
		1.0 - 0.12 * _charge_progress,
		1.0
	)
	charge_changed.emit(_charge_progress, _size_factor)
	var audio := get_tree().get_first_node_in_group("audio_manager")
	if audio != null and audio.has_method("update_charge"):
		audio.update_charge(_charge_progress)


func release_attack(direction: Vector2) -> void:
	if not _is_charging or _is_swinging:
		return
	_is_charging = false
	_is_swinging = true
	_play_audio(&"charge_stop", 1.0)
	_is_backswing = false
	_locked_aim_direction = (
		direction.normalized()
		if direction.length_squared() > 0.0001
		else Vector2.RIGHT
	)
	_locked_move_multiplier = CombatMath.move_multiplier(_charge_progress)
	_locked_move_multiplier = _modifiers.apply_charge_movement_modifier(
		_locked_move_multiplier,
		_charge_progress,
		false
	)
	if (
		_modifiers.has(&"light_swordplay")
		and CombatMath.get_size_tier(_charge_progress) == CombatMath.SizeTier.SMALL
	):
		_locked_move_multiplier *= 1.10
	if CombatMath.get_size_tier(_charge_progress) != CombatMath.SizeTier.SMALL:
		_clear_combo()
	_attack_sequence += 1
	_targets_hit_this_attack = 0
	_quake_used = false
	_lifesteal_this_release = 0.0
	swing_started.emit(_size_factor)
	_play_audio(
		&"swing_heavy"
		if CombatMath.is_tier_at_least(_charge_progress, CombatMath.SizeTier.LARGE)
		else &"swing_light",
		1.0
	)
	if (
		_modifiers.has(&"gravity_slash")
		and CombatMath.is_tier_at_least(_charge_progress, CombatMath.SizeTier.LARGE)
	):
		_apply_gravity_pull()
	_start_slash(false)


func cancel_charge() -> void:
	if not _is_charging:
		return
	_is_charging = false
	_charge_time = 0.0
	_charge_progress = 0.0
	sword_sprite.modulate = Color.WHITE
	_apply_size(CombatMath.MIN_SIZE)
	charge_changed.emit(0.0, CombatMath.MIN_SIZE)
	_play_audio(&"charge_stop", 1.0)


func reset_sword() -> void:
	if is_instance_valid(_swing_tween):
		_swing_tween.kill()
	_is_charging = false
	_is_swinging = false
	_is_backswing = false
	_charge_time = 0.0
	_charge_progress = 0.0
	_size_factor = CombatMath.MIN_SIZE
	_locked_move_multiplier = 1.0
	_hit_instance_ids.clear()
	attack_area.set_deferred("monitoring", false)
	sword_sprite.modulate = Color.WHITE
	_apply_size(CombatMath.MIN_SIZE)
	charge_changed.emit(0.0, CombatMath.MIN_SIZE)
	_play_audio(&"charge_stop", 1.0)


func get_charge_progress() -> float:
	return _charge_progress


func get_charge_time() -> float:
	return _charge_time


func get_size_factor() -> float:
	return _size_factor


func get_movement_multiplier() -> float:
	if _is_swinging:
		return _locked_move_multiplier
	return _modifiers.apply_charge_movement_modifier(
		CombatMath.move_multiplier(_charge_progress),
		_charge_progress
	)


func is_swinging() -> bool:
	return _is_swinging


func _get_half_angle() -> float:
	var degrees := 95.0 if _modifiers.has(&"arc_extension") else 70.0
	return deg_to_rad(degrees)


func _get_swing_duration() -> float:
	var duration := CombatMath.swing_duration(_charge_progress)
	duration *= _modifiers.get_swing_duration_multiplier()
	if (
		_modifiers.has(&"light_swordplay")
		and CombatMath.get_size_tier(_charge_progress) == CombatMath.SizeTier.SMALL
	):
		duration /= 1.35
	if (
		_modifiers.has(&"balanced_edge")
		and CombatMath.get_size_tier(_charge_progress) == CombatMath.SizeTier.MEDIUM
	):
		duration /= 1.15
	if _modifiers.has(&"titan_worship") and _charge_progress >= 0.90:
		duration *= 1.15
	return duration


func _start_slash(reverse: bool) -> void:
	_is_backswing = reverse
	_hit_instance_ids.clear()
	_attack_sequence += 1
	var center_angle := _locked_aim_direction.angle()
	var half_angle := _get_half_angle()
	var start_angle := center_angle + half_angle if reverse else center_angle - half_angle
	var end_angle := center_angle - half_angle if reverse else center_angle + half_angle
	rotation = start_angle
	attack_area.set_deferred("monitoring", true)
	if is_instance_valid(_swing_tween):
		_swing_tween.kill()
	_swing_tween = create_tween()
	_swing_tween.set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	_swing_tween.set_trans(Tween.TRANS_QUAD)
	_swing_tween.set_ease(Tween.EASE_IN_OUT)
	_swing_tween.tween_property(self, "rotation", end_angle, _get_swing_duration())
	_swing_tween.finished.connect(_on_slash_finished)


func _on_slash_finished() -> void:
	attack_area.set_deferred("monitoring", false)
	if _modifiers.has(&"double_slash") and not _is_backswing:
		await get_tree().create_timer(0.08).timeout
		if _is_swinging:
			_play_audio(&"swing_light", 0.93)
			_start_slash(true)
		return
	_finish_swing()


func _finish_swing() -> void:
	attack_area.set_deferred("monitoring", false)
	_is_swinging = false
	_is_backswing = false
	_charge_time = 0.0
	_charge_progress = 0.0
	_locked_move_multiplier = 1.0
	rotation = _locked_aim_direction.angle()
	sword_sprite.modulate = Color.WHITE
	_apply_size(CombatMath.MIN_SIZE)
	charge_changed.emit(0.0, CombatMath.MIN_SIZE)
	swing_finished.emit()


func _apply_size(new_size: float) -> void:
	_size_factor = clampf(new_size, CombatMath.MIN_SIZE, _modifiers.get_max_size())
	visual_root.scale = Vector2.ONE * _size_factor
	var rectangle := hitbox_shape.shape as RectangleShape2D
	rectangle.size = BASE_HITBOX_SIZE * _size_factor
	attack_area.position.x = BASE_HITBOX_CENTER_X * _size_factor


func _on_attack_area_body_entered(body: Node2D) -> void:
	if not _is_swinging or not body.has_method("take_hit"):
		return
	var instance_id := body.get_instance_id()
	if _hit_instance_ids.has(instance_id):
		return
	_hit_instance_ids[instance_id] = true
	var knockback_direction := _locked_aim_direction
	if is_instance_valid(_owner_actor):
		var away_from_player := body.global_position - _owner_actor.global_position
		if away_from_player.length_squared() > 0.0001:
			knockback_direction = away_from_player.normalized()
	var damage := CombatMath.damage_for_size(
		_size_factor,
		_modifiers.get_base_damage(),
		_modifiers.get_max_size()
	)
	if _modifiers.has(&"perfect_scale") and _charge_progress >= 0.90:
		damage *= 1.25
	var tier := CombatMath.get_size_tier(_charge_progress)
	if _modifiers.has(&"heavy_stride") and tier == CombatMath.SizeTier.SMALL:
		damage *= 0.80
	if _modifiers.has(&"balanced_edge") and tier == CombatMath.SizeTier.MEDIUM:
		damage *= 1.20
	if _modifiers.has(&"growing_momentum"):
		damage *= 1.0 + 0.08 * mini(_targets_hit_this_attack, 5)
	if _modifiers.has(&"combo_edge") and tier == CombatMath.SizeTier.SMALL:
		if _combo_target_id == instance_id:
			damage *= 1.0 + 0.12 * _combo_stacks
			_combo_stacks = mini(_combo_stacks + 1, 5)
		else:
			_combo_target_id = instance_id
			_combo_stacks = 1
		_combo_expires_msec = Time.get_ticks_msec() + 2500
	if _is_backswing:
		damage *= 0.45
	var knockback := (
		knockback_direction
		* CombatMath.knockback_for_progress(_charge_progress)
		* _modifiers.get_knockback_multiplier()
	)
	var hit_data := HitData.new(
		damage,
		knockback,
		_owner_actor,
		_size_factor,
		_attack_sequence,
		_charge_progress
	)
	var hit_result: Variant = body.call("take_hit", hit_data)
	var hit_applied: bool = hit_result == null or hit_result == true
	if (
		hit_applied
		and is_instance_valid(_owner_actor)
		and _modifiers.has(&"blood_anchor")
		and tier >= CombatMath.SizeTier.LARGE
		and not _is_backswing
	):
		var healing := minf(damage * 0.08, 12.0 - _lifesteal_this_release)
		if healing > 0.0:
			_lifesteal_this_release += _owner_actor.heal(healing)
	_targets_hit_this_attack += 1
	attack_hit.emit(body, damage, _size_factor)
	_play_audio(
		&"hit_heavy" if tier >= CombatMath.SizeTier.LARGE else &"hit_light",
		randf_range(0.96, 1.04)
	)
	var feedback := get_tree().get_first_node_in_group("feedback_manager") as FeedbackManager
	if feedback != null:
		feedback.request_hit_stop(CombatMath.hit_stop_for_size(_size_factor))
		feedback.request_camera_shake(
			CombatMath.shake_amplitude_for_size(_size_factor),
			lerpf(0.08, 0.15, _charge_progress)
		)
	if (
		_modifiers.has(&"ground_quake")
		and tier == CombatMath.SizeTier.COLOSSAL
		and not _quake_used
	):
		_quake_used = true
		_trigger_ground_quake(body, damage)


func _on_attack_area_area_entered(area: Area2D) -> void:
	if (
		_is_swinging
		and _modifiers.has(&"bullet_breaker")
		and CombatMath.is_tier_at_least(_charge_progress, CombatMath.SizeTier.LARGE)
		and area.is_in_group("enemy_bullet")
	):
		area.queue_free()


func _trigger_ground_quake(primary_target: Node2D, primary_damage: float) -> void:
	var center := primary_target.global_position
	for node in get_tree().get_nodes_in_group("enemy"):
		var enemy := node as Node2D
		if (
			enemy == primary_target
			or not is_instance_valid(enemy)
			or not enemy.has_method("take_hit")
		):
			continue
		if center.distance_to(enemy.global_position) <= 28.0:
			var direction: Vector2 = (enemy.global_position - center).normalized()
			enemy.take_hit(HitData.new(
				primary_damage * 0.35,
				direction * 18.0,
				_owner_actor,
				_size_factor,
				_attack_sequence + 1000000,
				_charge_progress
			))
	var feedback := get_tree().get_first_node_in_group("feedback_manager") as FeedbackManager
	if feedback != null and feedback.has_method("spawn_shockwave"):
		feedback.spawn_shockwave(center, 28.0)


func _apply_gravity_pull() -> void:
	if not is_instance_valid(_owner_actor):
		return
	for node in get_tree().get_nodes_in_group("enemy"):
		var enemy := node as Node2D
		if not is_instance_valid(enemy):
			continue
		if _owner_actor.global_position.distance_to(enemy.global_position) > 32.0:
			continue
		if enemy.has_method("apply_external_pull"):
			enemy.apply_external_pull(_owner_actor.global_position, 8.0)


func _clear_combo() -> void:
	_combo_target_id = 0
	_combo_stacks = 0
	_combo_expires_msec = 0


func _play_audio(event_id: StringName, pitch: float) -> void:
	var audio := get_tree().get_first_node_in_group("audio_manager")
	if audio != null and audio.has_method("play_game_sfx"):
		audio.play_game_sfx(event_id, global_position, pitch)
