class_name PlayerChargeMeter
extends Node2D

const BAR_SIZE := Vector2(28.0, 4.0)
const BAR_ORIGIN := Vector2(-14.0, -11.0)
const TIER_THRESHOLDS := [0.25, 0.50, 0.80]
const BACKGROUND_COLOR := Color(0.035, 0.035, 0.039, 0.96)
const BORDER_COLOR := Color(0.96, 0.96, 0.96, 1.0)
const FILL_COLOR := Color(1.0, 0.894, 0.471, 1.0)

var _progress := 0.0


func _ready() -> void:
	z_index = 42
	visible = false


func set_charge_progress(progress: float, _size_factor: float = 0.0) -> void:
	_progress = clampf(progress, 0.0, 1.0)
	queue_redraw()


func set_charging(charging: bool) -> void:
	visible = charging
	if not charging:
		_progress = 0.0
	queue_redraw()


func reset() -> void:
	set_charging(false)


func _draw() -> void:
	var outer_rect := Rect2(BAR_ORIGIN, BAR_SIZE)
	draw_rect(outer_rect, BACKGROUND_COLOR, true)
	var inner_rect := outer_rect.grow(-0.75)
	if _progress > 0.0:
		draw_rect(
			Rect2(
				inner_rect.position,
				Vector2(inner_rect.size.x * _progress, inner_rect.size.y)
			),
			FILL_COLOR,
			true
		)
	draw_rect(outer_rect, BORDER_COLOR, false, 0.75)
	for threshold in TIER_THRESHOLDS:
		var separator_x: float = (
			outer_rect.position.x + outer_rect.size.x * float(threshold)
		)
		draw_line(
			Vector2(separator_x, outer_rect.position.y),
			Vector2(separator_x, outer_rect.end.y),
			BORDER_COLOR,
			0.65
		)
