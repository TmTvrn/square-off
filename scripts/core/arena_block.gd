@tool
class_name ArenaBlock
extends StaticBody2D
## A rectangle of level geometry. Move it and change `size` in the Inspector; collision follows.
## The origin is the TOP-LEFT corner so positions read like a level layout.

enum Kind {
	SOLID,       ## Blocks everything.
	ONE_WAY,     ## Player can jump up through it and drop down with Down + Jump. Enemies ignore it.
	ENEMY_ONLY,  ## Invisible floor only enemies stand on (lets the boss cross the spike pit).
}

@export var size := Vector2(200, 40):
	set(value):
		size = value
		_sync()
@export var kind := Kind.SOLID:
	set(value):
		kind = value
		_sync()

var _shape: CollisionShape2D


func _ready() -> void:
	_sync()


func _sync() -> void:
	if not is_inside_tree():
		return
	if _shape == null:
		_shape = CollisionShape2D.new()
		_shape.shape = RectangleShape2D.new()
		add_child(_shape)
	(_shape.shape as RectangleShape2D).size = size
	_shape.position = size * 0.5
	_shape.one_way_collision = kind == Kind.ONE_WAY
	match kind:
		Kind.SOLID: collision_layer = 1
		Kind.ONE_WAY: collision_layer = 2
		Kind.ENEMY_ONLY: collision_layer = 128
	collision_mask = 0
	queue_redraw()


func _draw() -> void:
	var rect := Rect2(Vector2.ZERO, size)
	match kind:
		Kind.SOLID:
			draw_rect(rect, Palette.color(Palette.Role.ARENA))
			draw_rect(rect.grow(-1.0), Palette.color(Palette.Role.ARENA_EDGE), false, 2.0)
			# Top surfaces catch a little more light so "you can stand here" reads at a glance.
			draw_line(Vector2(0, 1), Vector2(size.x, 1), Palette.color(Palette.Role.ARENA_EDGE, 1.5), 2.0)
		Kind.ONE_WAY:
			# Hollow body + bright top edge: "you can pass through this, but you can stand on top."
			draw_rect(rect, Palette.color(Palette.Role.ARENA, 1.0, 0.6))
			draw_line(Vector2(0, 1.5), Vector2(size.x, 1.5), Palette.color(Palette.Role.ONE_WAY, 1.6), 3.0)
			var dash := 14.0
			var x := 0.0
			while x < size.x:
				draw_line(Vector2(x, size.y - 1), Vector2(minf(x + dash * 0.5, size.x), size.y - 1),
					Palette.color(Palette.Role.ARENA_EDGE), 2.0)
				x += dash
		Kind.ENEMY_ONLY:
			if Engine.is_editor_hint():
				draw_rect(rect, Color(1, 0.3, 0.4, 0.25))
