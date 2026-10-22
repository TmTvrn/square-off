class_name FxLayer
extends Node2D
## Code-driven particles, drawn additively so overlapping light adds up and blooms.
## Every effect in the game is built from these five primitives; the recipes live in juice.gd.

enum Kind {
	SPARK,  ## A streak that points along its velocity.
	SHARD,  ## A small spinning square (debris).
	RING,   ## An expanding or contracting outline circle.
	GHOST,  ## A fading rectangle (afterimage).
	ORB,    ## A soft shrinking dot (dust, motes).
}

const MAX_PARTICLES := 1500
const DEFAULTS := {
	"age": 0.0, "life": 0.4, "vel": Vector2.ZERO, "drag": 0.0, "gravity": 0.0, "width": 2.0,
	"size": 6.0, "rot": 0.0, "spin": 0.0, "length": 16.0, "r0": 0.0, "r1": 40.0, "flatten": 1.0,
}

var _particles: Array[Dictionary] = []


func _ready() -> void:
	Juice.fx = self
	var additive := CanvasItemMaterial.new()
	additive.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	material = additive


func add(particle: Dictionary) -> void:
	if _particles.size() >= MAX_PARTICLES:
		_particles.pop_front()
	particle.merge(DEFAULTS)
	_particles.append(particle)


func _process(delta: float) -> void:
	if delta <= 0.0:
		return
	var i := _particles.size() - 1
	while i >= 0:
		var p := _particles[i]
		p.age += delta
		if p.age >= p.life:
			_particles.remove_at(i)
		else:
			p.vel = p.vel * exp(-p.drag * delta) + Vector2(0, p.gravity * delta)
			if p.has("pos"):
				p.pos += p.vel * delta
			p.rot += p.spin * delta
		i -= 1
	queue_redraw()


func _draw() -> void:
	for p in _particles:
		var t: float = p.age / p.life
		var fade := 1.0 - t
		var c: Color = p.color
		c.a *= fade
		match p.kind:
			Kind.SPARK:
				var v: Vector2 = p.vel
				var dir := v.normalized() if v.length_squared() > 1.0 else Vector2.RIGHT
				var streak: float = p.length * (0.35 + 0.65 * fade) * clampf(v.length() / 500.0, 0.3, 1.6)
				draw_line(p.pos - dir * streak, p.pos, c, maxf(0.75, p.width * fade), true)
			Kind.SHARD:
				var s: float = p.size * (0.4 + 0.6 * fade)
				draw_set_transform(p.pos, p.rot, Vector2.ONE)
				draw_rect(Rect2(-s * 0.5, -s * 0.5, s, s), c)
				draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
			Kind.RING:
				var e := 1.0 - pow(1.0 - t, 3.0)
				var r: float = lerpf(p.r0, p.r1, e)
				draw_set_transform(p.pos, 0.0, Vector2(1.0, p.flatten))
				draw_arc(Vector2.ZERO, maxf(r, 0.5), 0.0, TAU, 64, c, maxf(0.75, p.width * fade), true)
				draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
			Kind.GHOST:
				draw_rect(p.rect, c)
			Kind.ORB:
				draw_circle(p.pos, maxf(0.5, p.size * fade), c, true, -1.0, true)
