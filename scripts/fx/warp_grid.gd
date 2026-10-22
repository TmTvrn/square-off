class_name WarpGrid
extends Node2D
## Geometry-Wars-style background grid that ripples when something hits hard.
## It's the darkest layer of the value hierarchy and only lights up where it's disturbed.

@export var area := Rect2(0, 0, 1920, 1080)
@export var spacing := 48.0
## Pull of each point back to rest.
@export var stiffness := 70.0
## Pull between neighbours. Higher = waves travel further and faster.
@export var coupling := 150.0
@export var damping := 6.5
@export var line_width := 1.5
## How bright a strongly displaced line gets.
@export var disturbed_glow := 2.2

var _cols := 0
var _rows := 0
var _rest := PackedVector2Array()
var _offset := PackedVector2Array()
var _velocity := PackedVector2Array()
var _awake_time := 0.0


func _ready() -> void:
	Juice.grid = self
	_cols = int(area.size.x / spacing) + 1
	_rows = int(area.size.y / spacing) + 1
	for y in _rows:
		for x in _cols:
			_rest.append(area.position + Vector2(x, y) * spacing)
	_offset.resize(_rest.size())
	_velocity.resize(_rest.size())
	queue_redraw()


## Pushes grid points away from `center`. Negative strength pulls them in.
func ripple(center: Vector2, strength: float, radius: float) -> void:
	for i in _rest.size():
		var d := _rest[i] - center
		var dist := d.length()
		if dist < radius and dist > 0.01:
			var f := 1.0 - dist / radius
			_velocity[i] += d / dist * strength * f * f
	_awake_time = 3.0


func _physics_process(delta: float) -> void:
	if _awake_time <= 0.0:
		return
	_awake_time -= delta
	var old := _offset.duplicate()
	for y in range(1, _rows - 1):
		for x in range(1, _cols - 1):
			var i := y * _cols + x
			var o := old[i]
			var laplacian := old[i - 1] + old[i + 1] + old[i - _cols] + old[i + _cols] - o * 4.0
			var accel := laplacian * coupling - o * stiffness - _velocity[i] * damping
			_velocity[i] += accel * delta
			_offset[i] = o + _velocity[i] * delta
	queue_redraw()


func _draw() -> void:
	var calm := Palette.color(Palette.Role.GRID)
	var lit := Palette.color(Palette.Role.ARENA_EDGE, disturbed_glow)
	for y in _rows:
		var points := PackedVector2Array()
		var colors := PackedColorArray()
		for x in _cols:
			var i := y * _cols + x
			points.append(_rest[i] + _offset[i])
			colors.append(calm.lerp(lit, clampf(_offset[i].length() / 22.0, 0.0, 1.0)))
		draw_polyline_colors(points, colors, line_width, true)
	for x in _cols:
		var points := PackedVector2Array()
		var colors := PackedColorArray()
		for y in _rows:
			var i := y * _cols + x
			points.append(_rest[i] + _offset[i])
			colors.append(calm.lerp(lit, clampf(_offset[i].length() / 22.0, 0.0, 1.0)))
		draw_polyline_colors(points, colors, line_width, true)
