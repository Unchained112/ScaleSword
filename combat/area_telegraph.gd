class_name AreaTelegraph
extends Node2D

var radius := 24.0
var progress := 0.0
var color := Color(1.0, 0.24, 0.10, 0.85)
var _pulse := 0.0


func configure(new_radius: float, new_color := Color(1.0, 0.24, 0.10, 0.85)) -> void:
	radius = new_radius
	color = new_color
	queue_redraw()


func set_progress(new_progress: float) -> void:
	progress = clampf(new_progress, 0.0, 1.0)
	queue_redraw()


func _process(delta: float) -> void:
	_pulse += delta
	queue_redraw()


func _draw() -> void:
	var visible_radius := maxf(radius * maxf(progress, 0.08), 2.0)
	var fill := color
	fill.a = 0.12 + 0.08 * sin(_pulse * 10.0)
	draw_circle(Vector2.ZERO, visible_radius, fill)
	draw_arc(Vector2.ZERO, visible_radius, 0.0, TAU, 32, color, 1.25)
	draw_arc(
		Vector2.ZERO,
		maxf(visible_radius - 2.0, 1.0),
		0.0,
		TAU,
		32,
		Color(color.r, color.g, color.b, 0.45),
		0.7
	)

