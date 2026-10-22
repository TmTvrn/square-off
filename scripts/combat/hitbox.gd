@tool
class_name Hitbox
extends Area2D
## Hurts the player on contact. The player's Hurtbox checks for these every physics tick.
## Put hitboxes on the "enemy_attack" or "hazard" physics layer.

@export var damage := 1
## Hazards launch the player upward instead of sideways, and can be pogoed off with a down-swing.
@export var is_hazard := false
## Turn off to make this harmless without removing it (for example, a dying boss).
@export var active := true
