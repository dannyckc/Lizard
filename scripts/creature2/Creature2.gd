## The v2 creature as it stands in the lab: one armature, stepped and drawn.
##
## Deliberately thin. The armature owns the physics, the spec owns the
## anatomy, and until SpecimenMesh2 lands (Phase 4) what this node draws is
## the solved skeleton itself — sticks at their bone radii, feet where they
## are planted, a shadow under whatever is off the ground. A debug view, but
## an honest one: every line is a node the solver put somewhere, so if the
## drawing looks wrong the state is wrong, which is the point of a lab.
class_name Creature2
extends Node2D

const INK := Color(0.16, 0.15, 0.13)
const LIMB_INK := Color(0.35, 0.33, 0.30)
const SHADOW := Color(0.0, 0.0, 0.0, 0.10)
const FOOT := Color(0.72, 0.34, 0.18)
## How much a node's height lightens its ink — enough to read a carried neck
## against a dropped tail without pretending the top-down view has a horizon.
const HEIGHT_LIFT: float = 0.006

@export var body: BodySpec

var armature: Armature = Armature.new()


func _ready() -> void:
	if body == null:
		body = load("res://scripts/creature2/CatBody.tres")
	armature.build(body, Vector2.ZERO, 0.0)


func _physics_process(delta: float) -> void:
	armature.step(delta, 0.0)
	queue_redraw()


func centre() -> Vector2:
	return armature.centre()


func reset() -> void:
	armature.reset()


func toggle_collapsed() -> void:
	if armature.collapsed:
		armature.revive()
	else:
		armature.collapse()


func drop(height: float) -> void:
	armature.drop(height)


func pick_node(world: Vector2, radius: float) -> int:
	return armature.pick_node(to_local(world), radius)


func haul_node(i: int, world: Vector2) -> void:
	armature.haul_to(i, to_local(world))


func _draw() -> void:
	var a: Armature = armature
	# Shadows first: a soft line under any stick carried off the ground, so
	# height reads in a view that has no vertical axis.
	for s in a.stick_count():
		var pa: Vector3 = a.pos[a.stick_a[s]]
		var pb: Vector3 = a.pos[a.stick_b[s]]
		if maxf(pa.z, pb.z) > 1.0:
			draw_line(Vector2(pa.x, pa.y), Vector2(pb.x, pb.y),
				SHADOW, a.stick_radius[s] * 2.0)
	for s in a.stick_count():
		var pa: Vector3 = a.pos[a.stick_a[s]]
		var pb: Vector3 = a.pos[a.stick_b[s]]
		var limb_stick: bool = a.stick_hold[s] < 1.0 or _is_limb_stick(s)
		var ink: Color = LIMB_INK if limb_stick else INK
		ink = ink.lightened(clampf((pa.z + pb.z) * 0.5 * HEIGHT_LIFT, 0.0, 0.35))
		draw_line(Vector2(pa.x, pa.y), Vector2(pb.x, pb.y),
			ink, maxf(a.stick_radius[s] * 2.0, 1.5))
	# Feet: marked where they are actually planted.
	for limb in a.limbs:
		var toe: Vector3 = a.pos[limb.nodes[limb.nodes.size() - 1]]
		if toe.z <= 0.5:
			draw_circle(Vector2(toe.x, toe.y), 2.4, FOOT)
	# The head, so the animal has a front.
	var head: Vector3 = a.pos[a.head_index()]
	draw_circle(Vector2(head.x, head.y), a.spec.skull_radius,
		INK.lightened(clampf(head.z * HEIGHT_LIFT, 0.0, 0.35)))


func _is_limb_stick(s: int) -> bool:
	for limb in armature.limbs:
		if s in limb.sticks:
			return true
	return false
