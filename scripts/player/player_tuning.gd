class_name PlayerTuning
extends Resource
## Every number that shapes how the player feels. Edit in the Inspector via res://tuning/player_tuning.tres.
## Jumps are authored as HEIGHT + TIME, so they stay meaningful: gravity is derived, never typed in.
## For scale: the player is 40 px tall and the arena is 1920 x 1080.

@export_group("Run")
@export var run_speed := 400.0
## Seconds from standing to full speed on the ground.
@export var ground_accel_time := 0.06
@export var ground_stop_time := 0.05
@export var air_accel_time := 0.08
@export var air_stop_time := 0.14
## Acceleration multiplier when reversing direction. Makes turnarounds feel sharp.
@export var turn_boost := 1.8

@export_group("Jump")
@export var jump_height := 150.0
@export var time_to_apex := 0.4
## Falling is heavier than rising: snappy arcs instead of moon jumps.
@export var fall_gravity_multiplier := 1.5
@export var max_fall_speed := 900.0
## Holding Down while falling.
@export var fast_fall_speed := 1350.0
## Upward speed kept when Jump is released early (short hops).
@export_range(0.0, 1.0) var jump_cut := 0.5
## Near the top of a jump (|vertical speed| below this), gravity eases off while Jump is held.
@export var apex_threshold := 130.0
@export var apex_gravity_multiplier := 0.5
@export var double_jump_height := 115.0
## How much the body stretches along its vertical speed in the air (0 = rigid).
@export_range(0.0, 0.3) var air_stretch := 0.12
@export var coyote_time := 0.1
@export var jump_buffer := 0.12

@export_group("Wall")
@export var wall_slide_speed := 150.0
@export var wall_coyote_time := 0.1
@export var wall_jump_height := 125.0
@export var wall_jump_push := 470.0
## After a wall jump your input is damped for this long so the push away reads.
## Hold toward the wall to climb it; hold away or neutral to leap off.
@export var wall_jump_control_lock := 0.13

@export_group("Drop Through")
@export var drop_through_time := 0.22

@export_group("Dash")
@export var dash_speed := 1150.0
@export var dash_time := 0.14
@export var dash_cooldown := 0.38
## Fraction of dash speed kept when the dash ends.
@export_range(0.0, 1.0) var dash_exit_keep := 0.45
@export var dash_buffer := 0.1

@export_group("Melee")
@export var attack_active_time := 0.1
@export var attack_cooldown := 0.26
@export var attack_buffer := 0.1
@export var melee_damage := 1
## Push back on yourself when a side swing connects.
@export var hit_recoil := 260.0
@export var pogo_height := 120.0

@export_group("Charge Shot")
## Holding Attack after a swing charges a shot. Release to fire.
@export var charge_level_1_time := 0.38
@export var charge_level_2_time := 1.0
@export var shot_1_damage := 1
@export var shot_2_damage := 4
@export var shot_1_speed := 1050.0
@export var shot_2_speed := 1200.0
@export var shot_1_recoil := 140.0
@export var shot_2_recoil := 380.0

@export_group("Health & Heal")
@export var max_health := 5
@export var invulnerable_time := 1.2
## Seconds of lost control after being hit.
@export var hurt_control_lock := 0.18
@export var knockback := Vector2(480, 420)
@export var spike_bounce_height := 140.0
## Hold Down + Jump on the ground to heal. Rooted for this long.
@export var heal_time := 1.3
## Landed melee hits (and deflects) needed to earn one heal charge.
@export var hits_per_heal_charge := 4
@export var max_heal_charges := 3


func rise_gravity() -> float:
	return 2.0 * jump_height / (time_to_apex * time_to_apex)


func jump_velocity() -> float:
	return 2.0 * jump_height / time_to_apex


## Launch speed that reaches `height` under rising gravity.
func velocity_for_height(height: float) -> float:
	return sqrt(2.0 * rise_gravity() * height)
