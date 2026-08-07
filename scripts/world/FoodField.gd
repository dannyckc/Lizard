## Scattered pellets that keep the world populated around the player and give
## the prototype something to do. Eating them grows the creature, which is the
## only "evolution" hook here — it feeds Creature.size_scale, and every system
## above already scales off that, so the body, limbs and stride grow together.
class_name FoodField
extends Node2D

@export var target_count: int = 46
@export var spawn_inner: float = 320.0
@export var spawn_outer: float = 1250.0
@export var cull_radius: float = 1900.0

var pellets: PackedVector2Array = PackedVector2Array()
var _phase: float = 0.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	z_index = 1  # above Main's ground grid, below the creature


## Culls pellets left far behind and tops the field back up in a ring ahead of
## and around `center`, so the player never walks into an empty world.
func refresh(center: Vector2) -> void:
	for i in range(pellets.size() - 1, -1, -1):
		if pellets[i].distance_to(center) > cull_radius:
			pellets.remove_at(i)
	while pellets.size() < target_count:
		var angle: float = _rng.randf() * TAU
		var radius: float = lerpf(spawn_inner, spawn_outer, sqrt(_rng.randf()))
		pellets.append(center + Vector2.RIGHT.rotated(angle) * radius)


## Removes every pellet within `radius` of `pos` and returns how many were eaten.
func consume(pos: Vector2, radius: float) -> int:
	var eaten: int = 0
	var r2: float = radius * radius
	for i in range(pellets.size() - 1, -1, -1):
		if pellets[i].distance_squared_to(pos) <= r2:
			pellets.remove_at(i)
			eaten += 1
	return eaten


func _process(delta: float) -> void:
	_phase += delta
	queue_redraw()


func _draw() -> void:
	for i in pellets.size():
		var p: Vector2 = pellets[i]
		# Gentle desynchronised pulse so the field reads as alive, not as dots.
		var pulse: float = 0.85 + 0.15 * sin(_phase * 2.1 + float(i) * 1.7)
		draw_circle(p, 6.5 * pulse, Color(0.85, 0.62, 0.30, 0.22))
		draw_circle(p, 3.2 * pulse, Color(0.98, 0.80, 0.38))
