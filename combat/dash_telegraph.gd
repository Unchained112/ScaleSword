class_name DashTelegraph
extends Node2D

var _path_length := 60.0
var _path_width := 7.0
var _progress := 1.0
var _segmented := false
var _pulse_time := 0.0
var _fill_color := Color(1.0, 0.16, 0.08, 0.30)
var _edge_color := Color(1.0, 0.52, 0.18, 0.88)


func configure(
	direction: Vector2,
	path_length: float,
	path_width: float,
	segmented: bool,
	fill_color := Color(1.0, 0.16, 0.08, 0.30),
	edge_color := Color(1.0, 0.52, 0.18, 0.88)
) -> void:
	rotation = direction.angle()
	_path_length = path_length
	_path_width = path_width
	_segmented = segmented
	_fill_color = fill_color
	_edge_color = edge_color
	_progress = 0.0 if segmented else 1.0
	queue_redraw()


func set_progress(progress: float) -> void:
	_progress = clampf(progress, 0.0, 1.0)
	queue_redraw()


func _process(delta: float) -> void:
	_pulse_time += delta
	queue_redraw()


func _draw() -> void:
	var fill_color := _fill_color
	fill_color.a = clampf(
		_fill_color.a + sin(_pulse_time * 12.0) * 0.08,
		0.0,
		1.0
	)
	if _segmented:
		var segment_count := 10
		var visible_segments := ceili(segment_count * _progress)
		var segment_length := _path_length / float(segment_count)
		for index in visible_segments:
			var start_x := float(index) * segment_length + 1.0
			var end_x := float(index + 1) * segment_length - 1.0
			_draw_rect_segment(start_x, end_x, fill_color, _edge_color)
	else:
		_draw_rect_segment(0.0, _path_length * _progress, fill_color, _edge_color)


func _draw_rect_segment(
	start_x: float,
	end_x: float,
	fill_color: Color,
	edge_color: Color
) -> void:
	if end_x <= start_x:
		return
	var half_width := _path_width * 0.5
	var polygon := PackedVector2Array([
		Vector2(start_x, -half_width),
		Vector2(end_x, -half_width),
		Vector2(end_x, half_width),
		Vector2(start_x, half_width),
	])
	draw_colored_polygon(polygon, fill_color)
	draw_polyline(
		PackedVector2Array([
			Vector2(start_x, -half_width),
			Vector2(end_x, -half_width),
			Vector2(end_x, half_width),
			Vector2(start_x, half_width),
			Vector2(start_x, -half_width),
		]),
		edge_color,
		0.75
	)
