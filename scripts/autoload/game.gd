extends Node
## Scene-wide references so entities can find each other without hard-coded node paths.
## Each object registers itself in its own _ready().

var player: Player
var boss: Boss
## Parent node for spawned projectiles.
var projectiles: Node2D
## Parent node for spawned minions.
var enemies: Node2D


func spawn(node: Node2D, at: Vector2) -> void:
	(enemies if node is Minion else projectiles).add_child(node)
	node.global_position = at
	node.reset_physics_interpolation()
