class_name UpgradeCard
extends Button

signal selected(index: int)

const LIGHT_TEXT := Color(0.96, 0.96, 0.96, 1.0)
const MUTED_TEXT := Color(0.62, 0.62, 0.67, 1.0)
const DARK_TEXT := Color(0.035, 0.035, 0.039, 1.0)
const DARK_MUTED := Color(0.2, 0.2, 0.22, 1.0)

@onready var title_label: Label = %TitleLabel
@onready var description_label: Label = %DescriptionLabel
@onready var category_label: Label = %CategoryLabel
@onready var stack_label: Label = %StackLabel
@onready var divider: TextureRect = %Divider

var _choice_index := -1
var _hovered := false
var _held := false
var _scale_tween: Tween


func _ready() -> void:
	pressed.connect(_on_pressed)
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)
	focus_entered.connect(_on_focus_changed)
	focus_exited.connect(_on_focus_changed)
	button_down.connect(_on_button_down)
	button_up.connect(_on_button_up)
	resized.connect(_update_pivot)
	_update_pivot()
	_refresh_visual_state()


func setup(
	definition: UpgradeDefinition,
	current_stack: int,
	index: int
) -> void:
	_choice_index = index
	title_label.text = tr(definition.title_key).to_upper()
	description_label.text = tr(definition.description_key)
	category_label.text = tr(definition.category_key).to_upper()
	stack_label.text = tr(&"UPGRADE_STACK_FORMAT") % [
		current_stack,
		definition.max_stacks,
	]
	tooltip_text = "%s\n%s" % [title_label.text, description_label.text]


func _on_pressed() -> void:
	if _choice_index >= 0:
		selected.emit(_choice_index)


func _on_mouse_entered() -> void:
	_hovered = true
	_refresh_visual_state()
	_animate_emphasis()


func _on_mouse_exited() -> void:
	_hovered = false
	_refresh_visual_state()
	_animate_emphasis()


func _on_button_down() -> void:
	_held = true
	_refresh_visual_state()


func _on_button_up() -> void:
	_held = false
	_refresh_visual_state()


func _on_focus_changed() -> void:
	_refresh_visual_state()
	_animate_emphasis()


func _refresh_visual_state() -> void:
	if not is_node_ready():
		return
	var inverted := _hovered or _held
	var primary := DARK_TEXT if inverted else LIGHT_TEXT
	var secondary := DARK_MUTED if inverted else MUTED_TEXT
	if disabled:
		primary = MUTED_TEXT
		secondary = Color(0.43, 0.43, 0.48, 1.0)
	for label in [title_label]:
		label.add_theme_color_override("font_color", primary)
	for label in [description_label, category_label, stack_label]:
		label.add_theme_color_override("font_color", secondary)
	divider.modulate = primary


func reset_visual_state() -> void:
	if is_instance_valid(_scale_tween):
		_scale_tween.kill()
	_hovered = false
	_held = false
	scale = Vector2.ONE
	z_index = 0
	_refresh_visual_state()


func _animate_emphasis() -> void:
	if not is_node_ready():
		return
	if is_instance_valid(_scale_tween):
		_scale_tween.kill()
	var emphasized := _hovered or has_focus()
	z_index = 2 if emphasized else 0
	_scale_tween = create_tween()
	_scale_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_scale_tween.tween_property(
		self,
		"scale",
		Vector2.ONE * (1.035 if emphasized else 1.0),
		0.12 if emphasized else 0.10
	).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


func _update_pivot() -> void:
	pivot_offset = size * 0.5
