class_name EnemyBullet
extends Area2D

const DEFAULT_SPEED := 62.0
const DEFAULT_DAMAGE := 9.0
const LIFE_TIME := 4.0

var _velocity := Vector2.ZERO
var _damage := DEFAULT_DAMAGE
var _life_remaining := LIFE_TIME


func _ready() -> void:
	add_to_group("enemy_bullet")
	body_entered.connect(_on_body_entered)


func launch(direction: Vector2, speed := DEFAULT_SPEED, damage := DEFAULT_DAMAGE) -> void:
	var safe_direction := direction.normalized() if direction.length_squared() > 0.0001 else Vector2.RIGHT
	_velocity = safe_direction * speed
	_damage = damage
	rotation = safe_direction.angle()


func _physics_process(delta: float) -> void:
	position += _velocity * delta
	_life_remaining -= delta
	if _life_remaining <= 0.0:
		queue_free()


func _on_body_entered(body: Node2D) -> void:
	var player := body as PlayerController
	if player != null:
		var direction := _velocity.normalized()
		player.take_hit(HitData.new(_damage, direction * 22.0, self, 1.0, get_instance_id()))
	queue_free()
