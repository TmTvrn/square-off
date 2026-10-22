class_name EnemyShot
extends Hitbox
## A boss projectile. Circles always mean "projectile".
## A melee swing destroys it (and a down-swing pogos off it). Solid walls pop it.

var velocity := Vector2.ZERO
var life := 4.0
## How much the art stretches along its motion. Needles use ~3 so they read as needles.
var stretch_factor := 1.0

# Orbiting (satellites): while `_orbit_center` is set, the shot circles it instead of flying.
var _orbit_center: Node2D
var _orbit_angle := 0.0
var _orbit_radius := 0.0
var _orbit_target_radius := 0.0
var _orbit_speed := 0.0

@onready var art: GeoShape = $Art


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	art.scale = Vector2(1.8, 1.8)  # Pops into existence, then settles.


## Circle `center` at `radius`, spinning at `angular_speed` radians per second, until released.
func orbit(center: Node2D, angle: float, radius: float, angular_speed: float) -> void:
	_orbit_center = center
	_orbit_angle = angle
	_orbit_radius = 20.0
	_orbit_target_radius = radius
	_orbit_speed = angular_speed


## Stop orbiting and fly straight outward.
func release(speed: float) -> void:
	_orbit_center = null
	velocity = Vector2.from_angle(_orbit_angle) * speed
	life = 3.0


func _physics_process(delta: float) -> void:
	if _orbit_center and is_instance_valid(_orbit_center):
		_orbit_angle += _orbit_speed * delta
		_orbit_radius = lerpf(_orbit_radius, _orbit_target_radius, 1.0 - exp(-6.0 * delta))
		global_position = _orbit_center.global_position + Vector2.from_angle(_orbit_angle) * _orbit_radius
		velocity = Vector2.from_angle(_orbit_angle + PI * 0.5 * signf(_orbit_speed)) * absf(_orbit_speed) * _orbit_radius
	else:
		position += velocity * delta
	life -= delta
	if life <= 0.0:
		pop()
		return
	# Stretch along the direction of travel: fast things look fast.
	var speed := velocity.length()
	art.rotation = velocity.angle()
	var stretch := Vector2(1.0 + speed / 2400.0 * stretch_factor, maxf(0.35, 1.0 - speed / 6000.0 * stretch_factor))
	art.scale = art.scale.lerp(stretch, 1.0 - exp(-18.0 * delta))
	if Engine.get_physics_frames() % 2 == 0:
		Juice.sparks(global_position, Palette.color(Palette.Role.THREAT, 1.3, 0.6), 1, 40.0,
			(-velocity).angle(), 0.4, 0.18, art.size.x * 0.35)


func _on_body_entered(body: Node2D) -> void:
	var block := body as ArenaBlock
	if block and block.kind == ArenaBlock.Kind.SOLID:
		pop()


## Harmless fizzle (hit a wall, timed out, or hit the player).
func pop() -> void:
	if is_queued_for_deletion():
		return
	Juice.sparks(global_position, Palette.color(Palette.Role.THREAT, 1.8), 6, 260.0, 0.0, TAU, 0.2, 2.0)
	queue_free()


## Destroyed by the player's swing: flashes in the player's color to credit the player.
func deflect() -> void:
	if is_queued_for_deletion():
		return
	Juice.impact(global_position, Palette.color(Palette.Role.PLAYER, 2.0), 0.7)
	queue_free()
