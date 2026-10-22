@tool
class_name SpikeStrip
extends Hitbox
## A row of spikes. Triangles always mean "static hazard".
## The origin is the bottom-left corner and spikes grow upward.
## The damaging area is shorter than the art on purpose: near misses should feel like skill, not robbery.

@export var width := 560.0:
	set(value):
		width = value
		_sync()
@export var tooth_width := 28.0:
	set(value):
		tooth_width = value
		_sync()
@export var height := 44.0:
	set(value):
		height = value
		_sync()
@export_range(0.2, 1.0) var lethal_height_ratio := 0.65:
	set(value):
		lethal_height_ratio = value
		_sync()

var _shape: CollisionShape2D


func _ready() -> void:
	is_hazard = true
	_sync()


func _sync() -> void:
	if not is_inside_tree():
		return
	if _shape == null:
		_shape = CollisionShape2D.new()
		_shape.shape = RectangleShape2D.new()
		add_child(_shape)
	var lethal := height * lethal_height_ratio
	(_shape.shape as RectangleShape2D).size = Vector2(width - 8.0, lethal)
	_shape.position = Vector2(width * 0.5, -lethal * 0.5)
	queue_redraw()


func _draw() -> void:
	var count := maxi(1, roundi(width / tooth_width))
	var w := width / count
	var fill := Palette.color(Palette.Role.HAZARD)
	var edge := Palette.color(Palette.Role.HAZARD, 2.4)
	for i in count:
		var x0 := i * w
		var tip := Vector2(x0 + w * 0.5, -height)
		draw_colored_polygon(PackedVector2Array([Vector2(x0, 0), tip, Vector2(x0 + w, 0)]), fill)
		draw_polyline(PackedVector2Array([Vector2(x0 + 2, 0), tip, Vector2(x0 + w - 2, 0)]), edge, 2.0, true)
