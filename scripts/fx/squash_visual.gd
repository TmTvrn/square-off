class_name SquashVisual
extends Node2D
## Springs its scale, rotation, and offset back to a target. Gameplay "punches" it; the spring does the rest.
## Place this node at the body's FEET and give child art a bottom pivot, so squash presses into the floor.
## Collision never changes: this is purely how the body looks.

## Higher = snappier return. Damping ratio is damping / (2 * sqrt(stiffness)); ~0.45 gives one clean overshoot.
@export var stiffness := 260.0
@export var damping := 15.0
@export var rotation_stiffness := 240.0
@export var rotation_damping := 17.0
@export var offset_stiffness := 400.0
@export var offset_damping := 22.0

## Held shape the spring settles toward (set every tick by the owner, e.g. stretched while wall sliding).
var target_scale := Vector2.ONE
var target_rotation := 0.0

var _scale_velocity := Vector2.ZERO
var _rotation_velocity := 0.0
var _offset := Vector2.ZERO
var _offset_velocity := Vector2.ZERO
var _home := Vector2.ZERO


func _ready() -> void:
	_home = position


## Instantly sets the shape (e.g. (1.3, 0.7) = flattened) and lets the spring recover.
func punch(new_scale: Vector2, scale_velocity := Vector2.ZERO) -> void:
	scale = new_scale
	_scale_velocity = scale_velocity


func spin(angular_velocity: float) -> void:
	_rotation_velocity += angular_velocity


## Shoves the art sideways (e.g. away from a hit) and lets it spring home.
func nudge(offset: Vector2) -> void:
	_offset += offset


func _physics_process(delta: float) -> void:
	var accel := (target_scale - scale) * stiffness - _scale_velocity * damping
	_scale_velocity += accel * delta
	scale += _scale_velocity * delta
	scale = scale.clamp(Vector2(0.3, 0.3), Vector2(2.0, 2.0))

	var rotation_accel := (target_rotation - rotation) * rotation_stiffness - _rotation_velocity * rotation_damping
	_rotation_velocity += rotation_accel * delta
	rotation += _rotation_velocity * delta

	var offset_accel := -_offset * offset_stiffness - _offset_velocity * offset_damping
	_offset_velocity += offset_accel * delta
	_offset += _offset_velocity * delta
	position = _home + _offset
