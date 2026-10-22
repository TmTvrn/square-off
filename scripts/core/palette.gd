@tool
class_name Palette
extends RefCounted
## One hue = one meaning. Change a color here and the whole game follows.
##
## Value hierarchy, darkest to brightest:
##   background < grid < arena < hazards < boss < player < projectiles < impact flashes
## Temperature: cool = you (cyan, violet), warm = everything that wants you dead.
## Colors are multiplied by a glow factor when drawn; anything above 1.0 blooms (HDR 2D + glow).
## Sanity check: press G in game to view in grayscale. The fight must still read.

enum Role {
	ARENA,       ## Solid geometry fill. Quiet, low value.
	ARENA_EDGE,  ## Edge lines on geometry so silhouettes read against the background.
	ONE_WAY,     ## Pass-through platforms: bright top edge, hollow body.
	GRID,        ## Background warp grid. Barely visible until disturbed.
	VOID,        ## The background color itself, for cut-outs like eyes.
	PLAYER,      ## Cyan = you. The only cool, bright body on screen.
	BOSS,        ## Warm red-pink threat body.
	THREAT,      ## Things that hurt you right now: enemy projectiles, telegraph outlines.
	HAZARD,      ## Static danger (spikes). Same warm family as THREAT, lower value.
	HEAL,        ## Violet = restoration. Used for nothing else.
	FLASH,       ## Pure white. Reserved for impact frames.
}

const BACKGROUND := Color("0a0d13")

const COLORS := {
	Role.ARENA: Color("131926"),
	Role.ARENA_EDGE: Color("2a3449"),
	Role.ONE_WAY: Color("51628a"),
	Role.GRID: Color("0f1420"),
	Role.VOID: Color("0a0d13"),
	Role.PLAYER: Color("3fe3ff"),
	Role.BOSS: Color("ff2d55"),
	Role.THREAT: Color("ff6a3d"),
	Role.HAZARD: Color("6e1a2c"),
	Role.HEAL: Color("a46bff"),
	Role.FLASH: Color("ffffff"),
}


## Returns the role's color with RGB multiplied by `glow` (alpha untouched).
static func color(role: Role, glow: float = 1.0, alpha: float = 1.0) -> Color:
	var c: Color = COLORS[role]
	return Color(c.r * glow, c.g * glow, c.b * glow, c.a * alpha)
