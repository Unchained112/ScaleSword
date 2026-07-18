class_name TrainingDummy
extends CharacterBody2D

const MAX_HEALTH := 100.0
const KNOCKBACK_DECELERATION := 180.0

@onready var collision_shape: CollisionShape2D = $CollisionShape2D
@onready var sprite: Sprite2D = $Sprite2D
@onready var health_bar: ProgressBar = $HealthBar

var _health := MAX_HEALTH
var _spawn_position := Vector2.ZERO
var _alive := true
var _flash_tween: Tween
var _sprite_base_scale := Vector2.ONE


func _ready() -> void:
	add_to_group("training_dummy")
	_spawn_position = global_position
	_sprite_base_scale = sprite.scale
	health_bar.max_value = MAX_HEALTH
	health_bar.value = _health


func _physics_process(delta: float) -> void:
	if not _alive:
		return
	move_and_slide()
	velocity = velocity.move_toward(Vector2.ZERO, KNOCKBACK_DECELERATION * delta)


func take_hit(hit_data: HitData) -> void:
	if not _alive:
		return
	_health = maxf(_health - hit_data.amount, 0.0)
	health_bar.value = _health
	velocity += hit_data.knockback
	_flash()
	var feedback := get_tree().get_first_node_in_group("feedback_manager") as FeedbackManager
	if feedback != null:
		feedback.spawn_hit_particles(global_position, hit_data.size_factor)
	if _health <= 0.0:
		_die_and_respawn()


func is_alive() -> bool:
	return _alive


func get_health() -> float:
	return _health


func _flash() -> void:
	if is_instance_valid(_flash_tween):
		_flash_tween.kill()
	var material := sprite.material as ShaderMaterial
	material.set_shader_parameter("flash_amount", 1.0)
	sprite.scale = _sprite_base_scale * 1.35
	_flash_tween = create_tween()
	_flash_tween.tween_interval(0.05)
	_flash_tween.tween_method(
		func(value: float) -> void:
			material.set_shader_parameter("flash_amount", value),
		1.0,
		0.0,
		0.14
	)
	_flash_tween.parallel().tween_property(sprite, "scale", _sprite_base_scale, 0.14)


func _die_and_respawn() -> void:
	_alive = false
	velocity = Vector2.ZERO
	sprite.hide()
	health_bar.hide()
	collision_shape.set_deferred("disabled", true)
	await get_tree().create_timer(1.0).timeout
	if not is_inside_tree():
		return
	global_position = _spawn_position
	_health = MAX_HEALTH
	health_bar.value = _health
	sprite.show()
	health_bar.show()
	collision_shape.set_deferred("disabled", false)
	_alive = true
