class_name ArenaBounds
extends StaticBody2D

@onready var top_shape: CollisionShape2D = $Top
@onready var bottom_shape: CollisionShape2D = $Bottom
@onready var left_shape: CollisionShape2D = $Left
@onready var right_shape: CollisionShape2D = $Right


func _ready() -> void:
	add_to_group("arena_bounds")


func get_interior_rect() -> Rect2:
	var top_rectangle := top_shape.shape as RectangleShape2D
	var bottom_rectangle := bottom_shape.shape as RectangleShape2D
	var left_rectangle := left_shape.shape as RectangleShape2D
	var right_rectangle := right_shape.shape as RectangleShape2D
	var top_edge := top_shape.global_position.y + top_rectangle.size.y * 0.5
	var bottom_edge := bottom_shape.global_position.y - bottom_rectangle.size.y * 0.5
	var left_edge := left_shape.global_position.x + left_rectangle.size.x * 0.5
	var right_edge := right_shape.global_position.x - right_rectangle.size.x * 0.5
	return Rect2(
		Vector2(left_edge, top_edge),
		Vector2(maxf(right_edge - left_edge, 1.0), maxf(bottom_edge - top_edge, 1.0))
	)


func get_safe_rect(margin: float) -> Rect2:
	var interior := get_interior_rect()
	var safe_margin := maxf(margin, 0.0)
	var maximum_margin := minf(interior.size.x, interior.size.y) * 0.5 - 1.0
	return interior.grow(-minf(safe_margin, maximum_margin))


func clamp_position(world_position: Vector2, margin: float) -> Vector2:
	var safe_rect := get_safe_rect(margin)
	return Vector2(
		clampf(world_position.x, safe_rect.position.x, safe_rect.end.x),
		clampf(world_position.y, safe_rect.position.y, safe_rect.end.y)
	)


func get_spawn_candidates(margin: float) -> Array[Vector2]:
	var safe_rect := get_safe_rect(margin)
	var result: Array[Vector2] = []
	for fraction in [0.0, 0.25, 0.5, 0.75, 1.0]:
		var x := lerpf(safe_rect.position.x, safe_rect.end.x, fraction)
		result.append(Vector2(x, safe_rect.position.y))
		result.append(Vector2(x, safe_rect.end.y))
	for fraction in [0.33, 0.67]:
		var y := lerpf(safe_rect.position.y, safe_rect.end.y, fraction)
		result.append(Vector2(safe_rect.position.x, y))
		result.append(Vector2(safe_rect.end.x, y))
	return result


func get_ray_boundary_hit(
	origin: Vector2,
	direction: Vector2,
	margin: float
) -> Dictionary:
	var safe_rect := get_safe_rect(margin)
	var ray_direction := direction.normalized()
	if ray_direction.length_squared() < 0.0001:
		return {}
	var ray_origin := clamp_position(origin, margin)
	var x_time := INF
	var y_time := INF
	var x_normal := Vector2.ZERO
	var y_normal := Vector2.ZERO
	if ray_direction.x > 0.00001:
		x_time = (safe_rect.end.x - ray_origin.x) / ray_direction.x
		x_normal = Vector2.LEFT
	elif ray_direction.x < -0.00001:
		x_time = (safe_rect.position.x - ray_origin.x) / ray_direction.x
		x_normal = Vector2.RIGHT
	if ray_direction.y > 0.00001:
		y_time = (safe_rect.end.y - ray_origin.y) / ray_direction.y
		y_normal = Vector2.UP
	elif ray_direction.y < -0.00001:
		y_time = (safe_rect.position.y - ray_origin.y) / ray_direction.y
		y_normal = Vector2.DOWN
	var travel_time := minf(x_time, y_time)
	if not is_finite(travel_time) or travel_time < 0.0:
		return {}
	var normal := x_normal if x_time < y_time else y_normal
	if absf(x_time - y_time) <= 0.001:
		normal = x_normal + y_normal
	return {
		"position": clamp_position(
			ray_origin + ray_direction * travel_time,
			margin
		),
		"normal": normal,
	}
