class_name PlayerShot
extends Area2D
## The player's charge shot. Level 2 is bigger, hits harder, and plows through enemy projectiles.

var velocity := Vector2.ZERO
var damage := 1
var level := 1
var life := 1.4

@onready var art: GeoShape = $Art
@onready var shape: CollisionShape2D = $Shape


func setup(shot_level: int, direction: Vector2, shot_damage: int, speed: float) -> void:
	level = shot_level
	damage = shot_damage
	velocity = direction * speed


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	area_entered.connect(_on_area_entered)
	if level == 2:
		art.size = Vector2(32, 32)
		art.glow = 2.8
		(shape.shape as CircleShape2D).radius = 14.0
	art.scale = Vector2(0.4, 0.4)


func _physics_process(delta: float) -> void:
	position += velocity * delta
	life -= delta
	if life <= 0.0:
		_pop()
		return
	art.rotation = velocity.angle()
	art.scale = art.scale.lerp(Vector2(1.35, 0.8), 1.0 - exp(-25.0 * delta))
	Juice.sparks(global_position, Palette.color(Palette.Role.PLAYER, 1.8, 0.7), level, 60.0,
		(-velocity).angle(), 0.5, 0.2, art.size.x * 0.3)


func _on_body_entered(body: Node2D) -> void:
	var block := body as ArenaBlock
	if block and block.kind == ArenaBlock.Kind.SOLID:
		_pop()


func _on_area_entered(area: Area2D) -> void:
	if area is Hurtbox:
		if (area as Hurtbox).receive_hit(damage, global_position):
			var big := level == 2
			Juice.freeze(0.07 if big else 0.035)
			Juice.shake(0.4 if big else 0.18)
			Juice.impact(global_position, Palette.color(Palette.Role.PLAYER, 2.2), 1.6 if big else 1.0,
				velocity.angle(), PI)
			Juice.ripple(global_position, 300.0 if big else 150.0, 260.0)
			Sfx.play("hit", 0.0 if big else -3.0, 0.8 if big else 1.0)
		_pop()
	elif area is EnemyShot and level == 2:
		(area as EnemyShot).deflect()


func _pop() -> void:
	if is_queued_for_deletion():
		return
	Juice.sparks(global_position, Palette.color(Palette.Role.PLAYER, 2.0), 8, 300.0, 0.0, TAU, 0.2, 2.0)
	Juice.ring(global_position, Palette.color(Palette.Role.PLAYER, 1.8), 4.0, 30.0, 0.15, 3.0)
	queue_free()
