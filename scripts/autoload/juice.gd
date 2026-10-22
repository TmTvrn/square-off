extends Node
## The feel toolkit. Freeze frames, screen shake, slow motion, particles, and grid ripples all go
## through here, so the "weight" of the whole game can be tuned in one place.
##
## Rough scale for freeze(): 0.03 small hit, 0.06 solid hit, 0.1 getting hurt, 0.2+ big moments.
## Rough scale for shake():  0.15 tap, 0.3 hit, 0.6 heavy, 1.0 the world is ending.

var camera: ShakeCamera
var fx: FxLayer
var grid: WarpGrid

var _freeze_until := 0.0
var _slowmo_until := 0.0
var _slowmo_scale := 1.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func reset() -> void:
	_freeze_until = 0.0
	_slowmo_until = 0.0
	Engine.time_scale = 1.0


# --- Time ------------------------------------------------------------------

## Stops the game for `seconds` of real time. The single strongest impact tool.
func freeze(seconds: float) -> void:
	_freeze_until = maxf(_freeze_until, _now() + seconds)
	_update_time_scale()


## Runs the game at `time_scale` for `seconds` of real time.
func slowmo(time_scale: float, seconds: float) -> void:
	_slowmo_scale = time_scale
	_slowmo_until = maxf(_slowmo_until, _now() + seconds)
	_update_time_scale()


func _process(_delta: float) -> void:
	_update_time_scale()


func _update_time_scale() -> void:
	var now := _now()
	if now < _freeze_until:
		Engine.time_scale = 0.0
	elif now < _slowmo_until:
		Engine.time_scale = _slowmo_scale
	else:
		Engine.time_scale = 1.0


func _now() -> float:
	return Time.get_ticks_usec() / 1_000_000.0


# --- Camera ----------------------------------------------------------------

func shake(trauma: float) -> void:
	if camera:
		camera.add_trauma(trauma)


## A directional shove of the camera that springs back. Point it the way the force travels.
func kick(offset: Vector2) -> void:
	if camera:
		camera.kick(offset)


func ripple(position: Vector2, strength: float, radius: float = 220.0) -> void:
	if grid:
		grid.ripple(position, strength, radius)


# --- Particle recipes ------------------------------------------------------

func sparks(position: Vector2, color: Color, count := 10, speed := 520.0, angle := 0.0,
		spread := TAU, life := 0.3, width := 3.0) -> void:
	if not fx:
		return
	for i in count:
		var a := angle + randf_range(-spread, spread) * 0.5
		fx.add({
			"kind": FxLayer.Kind.SPARK, "pos": position, "color": color, "width": width,
			"vel": Vector2.from_angle(a) * speed * randf_range(0.4, 1.0),
			"life": life * randf_range(0.6, 1.0), "drag": 7.0, "length": 20.0,
		})


## Little spinning squares that fall with gravity: bodies chipping.
func shards(position: Vector2, color: Color, count := 6, speed := 380.0, size := 7.0, life := 0.55,
		angle := -PI * 0.5, spread := TAU) -> void:
	if not fx:
		return
	for i in count:
		var a := angle + randf_range(-spread, spread) * 0.5
		fx.add({
			"kind": FxLayer.Kind.SHARD, "pos": position, "color": color,
			"vel": Vector2.from_angle(a) * speed * randf_range(0.35, 1.0),
			"life": life * randf_range(0.6, 1.0), "size": size * randf_range(0.6, 1.2),
			"rot": randf() * TAU, "spin": randf_range(-14.0, 14.0), "gravity": 1400.0, "drag": 2.0,
		})


## An expanding (or contracting, if to < from) ring. `flatten` < 1 squashes it into an ellipse.
func ring(position: Vector2, color: Color, from_radius: float, to_radius: float, life := 0.3,
		width := 4.0, flatten := 1.0) -> void:
	if fx:
		fx.add({
			"kind": FxLayer.Kind.RING, "pos": position, "color": color, "r0": from_radius,
			"r1": to_radius, "life": life, "width": width, "flatten": flatten,
		})


## A fading copy of a body, for dash trails.
func ghost(rect: Rect2, color: Color, life := 0.16) -> void:
	if fx:
		fx.add({"kind": FxLayer.Kind.GHOST, "rect": rect, "color": color, "life": life})


## Soft puffs at the feet (or against a wall) when you land, jump, or touch a wall.
func dust(position: Vector2, count := 6, direction := Vector2.UP, spread := PI * 0.9, speed := 160.0) -> void:
	if not fx:
		return
	for i in count:
		var a := direction.angle() + randf_range(-spread, spread) * 0.5
		fx.add({
			"kind": FxLayer.Kind.ORB, "pos": position + Vector2(randf_range(-8, 8), 0),
			"color": Palette.color(Palette.Role.ONE_WAY, 1.2, 0.55),
			"vel": Vector2.from_angle(a) * speed * randf_range(0.3, 1.0),
			"life": randf_range(0.25, 0.45), "size": randf_range(3.0, 6.0), "drag": 6.0, "gravity": -60.0,
		})


## The standard "something got hit" composite: white pop, colored sparks, a ring.
func impact(position: Vector2, color: Color, strength := 1.0, angle := 0.0, spread := TAU) -> void:
	ring(position, Palette.color(Palette.Role.FLASH, 2.0), 6.0, 34.0 * strength, 0.14, 5.0)
	sparks(position, color, int(10 * strength), 620.0 * strength, angle, spread, 0.28)
	sparks(position, Palette.color(Palette.Role.FLASH, 2.2), int(4 * strength), 760.0 * strength, angle, spread * 0.6, 0.16, 2.0)
