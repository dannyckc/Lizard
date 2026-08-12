## The mark on whatever the cursor has hold of — v1's `TargetMark`, reading v2's
## census.
##
## Its own node for one reason, and it is the reason the mark exists: it has to
## sit *on* the thing it has selected. Drawn with the field it would go
## underneath every animal in the lab, so the one mark whose whole job is to say
## "this piece of this animal" would end up hidden behind that animal, legible
## only when it landed on bare ground. Above them it is a marker; below them it
## is a rumour.
##
## Nothing here decides anything. `Quarry` resolves what is under the pointer,
## `Maw` decides whether it can be bitten and `Likeness` owns what the thing
## underneath looks like; this file is the one place that turns those answers
## into strokes.
class_name AimMark
extends Node2D

const INK := Color("14140f")
const PAPER := Color("f3f1ec")

## How far off the surface the marker floats, in screen pixels. Enough to clear
## the strokes the thing under it is drawn with, and no more: a marker any
## further out stops reading as being *on* what it has selected, which is the
## one thing this whole mark exists to say.
const LIFT: float = 5.0

## Whose aim is being drawn, and how far the camera is zoomed in — so the marker
## is the same size on screen at every zoom. Both are handed in by the lab each
## frame; this node looks nothing up for itself.
var actor: Creature2 = null
var zoom: float = 1.0


func _ready() -> void:
	# Over the animals, which draw at 10: this is the only thing on screen that
	# is not part of the world being looked at.
	z_index = 40


func show_aim(who: Creature2, camera_zoom: float) -> void:
	actor = who
	zoom = maxf(camera_zoom, 0.0001)
	queue_redraw()


## What the cursor has selected, drawn so the third axis is legible.
##
## Two marks and a line between them, because that is exactly what the pick is:
## a ring where the target is in the picture, a tick where it stands on the
## ground plane, and the drop between the two, which is its height. Nothing else
## in a top-down view can show that a click landed on a shoulder rather than on
## the floor a shoulder's height behind it, and the whole feature is unreadable
## without it.
##
## A ring where the jaws can be got onto it and a cross where they cannot, so
## "out of reach" is something the player sees before pressing the button rather
## than something they infer from a bite that did nothing. And where the marker
## has had to stop short of what was selected, a faint line runs on to it: the
## ring is where this animal's mouth gets to, and the far end of that line is
## what it was pointed at.
func _draw() -> void:
	if actor == null or actor.aim == null or not actor.alive:
		return
	var pick: Quarry.Pick = actor.aim
	var reachable: bool = actor.can_reach_aim()
	var scale: float = 1.0 / zoom
	var selected: Quarry.Pick = pick.selected()
	# Where the marker actually goes: off the surface, toward the viewer. The
	# picture carries height up the screen, so "off the surface" is up it — and
	# the lift is a fixed handful of screen pixels rather than anything derived,
	# because what it has to clear is the width of the strokes it is drawn over.
	var over: Vector2 = pick.seen + Vector2(0.0, -LIFT) * scale
	# Drawn in whichever ink reads against what it has landed on. The same
	# problem v1's mark had and the same answer: a mark the colour of the flank
	# it is describing is not a mark, and this animal's flank is very nearly the
	# colour of the ink everything else is drawn in.
	var ink: Color = _ink_over(pick)
	var tint := Color(ink, 0.85 if reachable else 0.7)

	_draw_bite_zone(scale)
	if selected != pick:
		draw_dashed_line(over, selected.seen, Color(_ink_over(selected), 0.35),
			scale, 5.0 * scale, true)
	_draw_target_shape(selected, scale)
	# The drop: where the thing is in the picture against where it stands on the
	# floor, which is the one reading that says how high up it is.
	if pick.seen.distance_squared_to(pick.at) > 1.0:
		draw_line(pick.at, over, Color(INK, 0.20), scale, true)
		draw_line(pick.at + Vector2(-4.0, 0.0) * scale,
			pick.at + Vector2(4.0, 0.0) * scale, Color(INK, 0.20), scale, true)
	var arm: float = 7.0 * scale
	if reachable:
		draw_circle(over, 3.0 * scale, tint)
		draw_arc(over, 7.0 * scale, 0.0, TAU, 20, tint, scale, true)
		return
	# A cross, and nothing else: a hollow ring reads as a fainter target rather
	# than as a refusal, and a great deal of what a cursor can land on in a world
	# with a third axis cannot be bitten.
	draw_line(over + Vector2(-arm, -arm), over + Vector2(arm, arm), tint, 1.4 * scale, true)
	draw_line(over + Vector2(-arm, arm), over + Vector2(arm, -arm), tint, 1.4 * scale, true)


## Which ink reads against what the mark has landed on. Flesh is drawn in
## something very close to the ink the field itself is drawn in, so a mark on an
## animal is drawn in the paper instead — the same reversal v1 made, and made off
## the same question rather than off a rule about creatures.
func _ink_over(pick: Quarry.Pick) -> Color:
	return PAPER if pick.creature != null else INK


## The ground this mouth can be brought to bear on, drawn once, faintly.
##
## Not a decoration and not a radius somebody chose: it is the maw's own purse
## read out loud. The radius is `Maw.plan_reach` at the height being aimed at —
## the arm plus the throw plus the gape's grab, less whatever the height costs —
## which is the same number the strike is priced against, and it is swept either
## side of where the head is pointing by exactly the cone a strike must address
## its target inside. So the shape a player learns to read here is the shape that
## decides every bite, and the two cannot drift apart.
##
## Centred on the withers, because that is where the purse is centred: the neck
## is an arc rooted at the shoulders, and anchoring the drawing anywhere else
## would make it shrink and swell as the animal dipped its head.
func _draw_bite_zone(scale: float) -> void:
	var maw: Maw = actor.maw
	if maw == null or actor.armature == null:
		return
	var arm: float = maw.plan_reach(actor.aim.height)
	if arm <= 1.0:
		return
	var root: Vector2 = actor.armature.plan(actor.armature.withers_index())
	# Swept about the *body's* facing rather than the head's, because that is
	# what the refusal is measured against: a mouth does not bite what is behind
	# the animal wearing it, however far round the neck has turned.
	var facing: float = actor.heading
	var edge := Color(INK, 0.18)
	draw_arc(root, arm, facing - Maw.ADDRESS_CONE, facing + Maw.ADDRESS_CONE,
		36, edge, scale, true)
	# The two ends of the sweep, so the arc reads as a region the mouth covers
	# rather than as a stray curve lying on the ground.
	for side in [-Maw.ADDRESS_CONE, Maw.ADDRESS_CONE]:
		var out: Vector2 = Vector2.RIGHT.rotated(facing + side)
		draw_line(root + out * (arm * 0.82), root + out * arm, edge, scale, true)


## The outline of whatever is targeted, traced over the thing itself.
##
## Off the same posed rings the painter paints and the bite wounds — the ring
## the cursor landed on, drawn in the picture — so what is highlighted is
## exactly what a bite would take. Anything that reconstructed its own idea of
## where a leg is would eventually disagree with the thing that decides the
## damage, and the highlight would start lying at precisely the moments it
## matters.
func _draw_target_shape(pick: Quarry.Pick, scale: float) -> void:
	var target: Creature2 = pick.creature
	if target == null or target.contour == null or pick.contact.is_empty():
		return
	var mark := Color(_ink_over(pick), 0.55)
	var name: StringName = pick.contact["band"]
	var t: float = float(pick.contact["t"])
	var band: Contour.Band = target.contour.band(name)
	if band == null:
		return
	# The ring the cursor is on, as it is drawn: the span of flesh one bite there
	# would be taken out of.
	var points := PackedVector2Array()
	for s in band.sectors:
		var theta: float = atan2(band.sines[s], band.cosines[s])
		points.append(Contour.seen(target.contour.place(name, t, theta)))
	if points.size() < 2:
		return
	points.append(points[0])
	draw_polyline(points, mark, scale, true)
