class_name BossTelegraph
extends Node2D
## Draws the boss's warnings in world space. Outline = "coming soon"; the fill grows as the attack nears,
## so the telegraph is also a timer the player can read without thinking.

enum Kind { LANE, RING, MARKER, COLUMN, RAYS }

var _items: Array[Dictionary] = []


func _ready() -> void:
	top_level = true
	global_position = Vector2.ZERO


## A rectangle the boss is about to charge through.
func lane(rect: Rect2, duration: float, toward_right: bool) -> void:
	_items.append({"kind": Kind.LANE, "rect": rect, "age": 0.0, "duration": duration,
		"toward_right": toward_right})


## A ring that will become bullets. Gaps are drawn as gaps, so the safe spot is visible in advance.
func ring(center: Vector2, radius: float, duration: float, gap_angle := 0.0, gap_size := 0.0) -> void:
	_items.append({"kind": Kind.RING, "center": center, "radius": radius, "age": 0.0,
		"duration": duration, "gap_angle": gap_angle, "gap_size": gap_size})


## A landing zone on the floor.
func marker(rect: Rect2, duration: float) -> void:
	_items.append({"kind": Kind.MARKER, "rect": rect, "age": 0.0, "duration": duration})


## A vertical strip that something will fall through. Fills from the top down.
func column(rect: Rect2, duration: float) -> void:
	_items.append({"kind": Kind.COLUMN, "rect": rect, "age": 0.0, "duration": duration})


## Lines fanning out from `center`: the exact paths of shots about to be fired.
func rays(center: Vector2, angles: Array[float], length: float, duration: float) -> void:
	_items.append({"kind": Kind.RAYS, "center": center, "angles": angles, "length": length,
		"age": 0.0, "duration": duration})


func clear() -> void:
	_items.clear()
	queue_redraw()


func _process(delta: float) -> void:
	var i := _items.size() - 1
	while i >= 0:
		_items[i].age += delta
		if _items[i].age > _items[i].duration:
			_items.remove_at(i)
		i -= 1
	queue_redraw()


func _draw() -> void:
	for item in _items:
		var p := clampf(item.age / item.duration, 0.0, 1.0)
		var blink := 1.0 if p < 0.75 else (0.5 + 0.5 * sin(item.age * 60.0))
		var line := Palette.color(Palette.Role.THREAT, 1.2 + p, (0.35 + 0.5 * p) * blink)
		var fill := Palette.color(Palette.Role.THREAT, 1.0, 0.04 + 0.08 * p)
		var edge := Palette.color(Palette.Role.THREAT, 1.6 + p, 0.5 + 0.5 * p)
		match item.kind:
			Kind.LANE, Kind.MARKER:
				var rect: Rect2 = item.rect
				draw_rect(rect, line, false, 2.0)
				var filled := rect
				if item.kind == Kind.LANE:
					# Fills from the boss toward the wall it will hit.
					filled.size.x *= p
					if not item.toward_right:
						filled.position.x = rect.end.x - filled.size.x
					var front := filled.position.x if not item.toward_right else filled.end.x
					draw_line(Vector2(front, rect.position.y), Vector2(front, rect.end.y), edge, 2.0)
				else:
					filled = rect.grow_individual(0, -rect.size.y * (1.0 - p), 0, 0)
				draw_rect(filled, fill)
			Kind.COLUMN:
				var rect: Rect2 = item.rect
				draw_rect(rect, line, false, 2.0)
				var filled := rect
				filled.size.y *= p
				draw_rect(filled, Color(fill, fill.a * 0.3))  # Tall columns: keep the wash very faint.
				draw_line(Vector2(rect.position.x, filled.end.y), Vector2(rect.end.x, filled.end.y), edge, 2.0)
			Kind.RAYS:
				for angle: float in item.angles:
					var dir := Vector2.from_angle(angle)
					var start: Vector2 = item.center + dir * 50.0
					draw_line(start, start + dir * item.length * (0.4 + 0.6 * p), line, 1.5 + p, true)
			Kind.RING:
				var r: float = item.radius * (1.6 - 0.6 * p)
				var gap: float = item.gap_size
				if gap <= 0.0:
					draw_arc(item.center, r, 0.0, TAU, 64, line, 2.0, true)
				else:
					var g0: float = item.gap_angle + gap * 0.5
					draw_arc(item.center, r, g0, g0 + TAU - gap, 64, line, 2.0 + p * 2.0, true)
