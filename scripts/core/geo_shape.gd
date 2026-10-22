@tool
class_name GeoShape
extends Node2D
## The game's only body-drawing primitive.
## Shape language:  SQUARE = bodies,  CIRCLE = projectiles,  TRIANGLE = hazards.
## Fill language:   filled = real and dangerous now,  outline only = warning / not yet real.

enum Kind { SQUARE, CIRCLE, TRIANGLE }

@export var kind := Kind.SQUARE:
	set(value):
		kind = value
		queue_redraw()
@export var size := Vector2(40, 40):
	set(value):
		size = value
		queue_redraw()
## Puts the origin on the bottom edge instead of the center, so squash and stretch press into the floor.
@export var pivot_at_bottom := false:
	set(value):
		pivot_at_bottom = value
		queue_redraw()
@export var role := Palette.Role.PLAYER:
	set(value):
		role = value
		queue_redraw()
## Brightness multiplier. Above 1.0 blooms.
@export_range(0.0, 6.0, 0.05) var glow := 1.0:
	set(value):
		glow = value
		queue_redraw()
@export var filled := true:
	set(value):
		filled = value
		queue_redraw()
@export_range(0.0, 16.0, 0.5) var outline_width := 0.0:
	set(value):
		outline_width = value
		queue_redraw()

## 0..1 blend toward white. Gameplay sets this to 1 on impact and lets it decay.
var flash := 0.0:
	set(value):
		flash = value
		queue_redraw()
## Optional blend toward another color; the alpha channel is the blend amount.
var tint := Color(0, 0, 0, 0):
	set(value):
		tint = value
		queue_redraw()


func current_color() -> Color:
	var c := Palette.color(role, glow)
	if tint.a > 0.0:
		c = c.lerp(Color(tint.r * glow, tint.g * glow, tint.b * glow), tint.a)
	if flash > 0.0:
		c = c.lerp(Palette.color(Palette.Role.FLASH, maxf(glow, 1.8)), clampf(flash, 0.0, 1.0))
	return c


func _draw() -> void:
	var c := current_color()
	var center := Vector2(0, -size.y * 0.5) if pivot_at_bottom else Vector2.ZERO
	match kind:
		Kind.SQUARE:
			var rect := Rect2(center - size * 0.5, size)
			if filled:
				draw_rect(rect, c)
			if outline_width > 0.0:
				draw_rect(rect.grow(-outline_width * 0.5), c, false, outline_width)
		Kind.CIRCLE:
			var radius := size.x * 0.5
			if filled:
				draw_circle(center, radius, c, true, -1.0, true)
			if outline_width > 0.0:
				draw_arc(center, radius - outline_width * 0.5, 0.0, TAU, 48, c, outline_width, true)
		Kind.TRIANGLE:
			var h := size * 0.5
			var points := PackedVector2Array([
				center + Vector2(-h.x, h.y), center + Vector2(0, -h.y), center + Vector2(h.x, h.y)])
			if filled:
				draw_colored_polygon(points, c)
			if outline_width > 0.0:
				points.append(points[0])
				draw_polyline(points, c, outline_width, true)
