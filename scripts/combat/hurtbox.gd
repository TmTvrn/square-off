class_name Hurtbox
extends Area2D
## The part of an enemy that can be hit. Attacks call `receive_hit`; the owner listens to `hurt`.

signal hurt(damage: int, source_position: Vector2)

## When false, hits are ignored (invulnerability windows).
var vulnerable := true


func receive_hit(damage: int, source_position: Vector2) -> bool:
	if not vulnerable:
		return false
	hurt.emit(damage, source_position)
	return true
