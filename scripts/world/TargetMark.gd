## The mark on whatever the cursor has hold of, drawn over the world rather than
## into it.
##
## Its own node for one reason, and it is the reason the mark exists: it has to
## sit *on* the thing it has selected. Drawn with the field — which is what it
## was — it goes underneath every creature in the habitat, so the one mark whose
## whole job is to say "this piece of this animal" ends up hidden behind that
## animal, legible only when it lands on bare ground. Above them it is a marker;
## below them it is a rumour.
##
## Nothing here decides anything. `Reticle` resolves what is under the pointer,
## `Reach` decides whether it can be bitten and `CreatureView` owns what colour
## the thing underneath is drawn in; this file is the one place that turns those
## three answers into strokes.
class_name TargetMark
extends Node2D

const INK := Color("14140f")

## How far off the surface the marker floats, in screen pixels. Enough to clear
## the strokes the thing under it is drawn with, and no more: a marker any
## further out stops reading as being *on* what it has selected, which is the one
## thing this whole mark exists to say.
const MARKER_LIFT: float = 5.0

## Whose aim is being drawn, and how far the camera is zoomed in — so the marker
## is the same size on screen at every zoom, exactly as the field's own
## registration dots are. Both are handed in by the habitat each frame; this node
## looks nothing up for itself.
var actor: Creature = null
var zoom: float = 1.0


func _ready() -> void:
	# Over the creatures, which sit at CreatureView.render_z_index, and over the
	# bite prints too: this is the only thing on screen that is not part of the
	# world being looked at.
	z_index = 40


## One frame of it. Called by the habitat with whatever the cursor resolved to,
## because which of the several things under one pixel was meant is a question
## about the world and only the world can see all of them.
func show_aim(who: Creature, camera_zoom: float) -> void:
	actor = who
	zoom = maxf(camera_zoom, 0.0001)
	queue_redraw()


## What the cursor has selected, drawn so the third axis is legible.
##
## Two marks and a line between them, because that is exactly what the pick is: a
## ring where the target is in the picture, a tick where it stands on the ground
## plane, and the drop between the two, which is its height. Nothing else in a
## top-down view can show that a click landed on a shoulder rather than on the
## floor a shoulder's height behind it, and the whole feature is unreadable
## without it.
##
## A ring where the jaws can be got onto it and a cross where they cannot, so
## "out of reach" is something the player sees before pressing the button rather
## than something they infer from a bite that did nothing.
##
## Two more marks, now that the pick knows what it is on. The structure itself is
## traced — the actual bone, the actual span of flank — because a ring alone
## cannot say *which* of the four legs overlapping one another in a top-down
## picture the click has hold of. And when the marker has had to stop short of
## what was selected, a faint line runs on to it: the ring is where this animal's
## mouth gets to, and the far end of that line is what it was pointed at.
##
## Drawn in whichever of the two inks reads against the surface it has landed on,
## and lifted a little clear of it. Both are the same problem: this mark sits on
## a thing rather than beside one, and a mark the same colour as a black flank on
## a black flank, or buried a pixel inside the silhouette it is describing, is not
## a mark. See `CreatureView.surface_color`, which answers what is underneath in
## the palette that thing is drawn in.
func _draw() -> void:
	if actor == null or actor.aim == null:
		return
	var pick: Reticle.Pick = actor.aim
	var reachable: bool = actor.can_reach_aim()
	var scale: float = 1.0 / zoom
	var selected: Reticle.Pick = pick.selected()
	# Where the marker actually goes: off the surface, toward the viewer. The
	# picture carries height up the screen, so "off the surface" is up it — the
	# same direction a thing standing taller would have moved — and the lift is a
	# fixed handful of screen pixels rather than anything derived, because what it
	# has to clear is the width of the strokes it is drawn over.
	var over: Vector2 = pick.drawn + Vector2(0.0, -MARKER_LIFT) * scale
	var ink: Color = CreatureView.ink_over(CreatureView.surface_color(selected))
	var tint := Color(ink, 0.85 if reachable else 0.7)
	# The zone is drawn in the ordinary ink rather than the marker's, because it
	# lies on the floor: it is the ground this mouth covers, and the ground is
	# paper whatever the cursor happens to be resting on.
	_draw_bite_zone(scale)
	if selected != pick:
		draw_dashed_line(over, selected.drawn, Color(ink, 0.22),
			scale, 5.0 * scale, true)
	_draw_target_shape(selected, scale, ink)
	if pick.drawn.distance_squared_to(pick.at) > 1.0:
		draw_line(pick.at, over, Color(ink, 0.20), scale, true)
		draw_line(pick.at + Vector2(-4.0, 0.0) * scale, pick.at + Vector2(4.0, 0.0) * scale,
			Color(ink, 0.20), scale, true)
	if reachable:
		draw_circle(over, 3.0 * scale, tint)
		draw_arc(over, 7.0 * scale, 0.0, TAU, 20, tint, scale, true)
		return
	# A cross, and nothing else: a hollow ring reads as a fainter target rather
	# than as a refusal, and the whole point of the third axis is that a great deal
	# of what the cursor can land on cannot be bitten.
	var arm: float = 7.0 * scale
	draw_line(over + Vector2(-arm, -arm), over + Vector2(arm, arm), tint, 1.4 * scale, true)
	draw_line(over + Vector2(-arm, arm), over + Vector2(arm, -arm), tint, 1.4 * scale, true)


## The ground this mouth can be brought to bear on, drawn once, faintly.
##
## Not a decoration and not a radius someone chose: it is `Reach` read out loud.
## The arc's radius is the arm onto whatever is being aimed at — the gape plus
## the throw, less what the neck gives up sweeping the mouth to that height, which
## is the same number the strike is priced against — and it is swept either side
## of where the head is pointing by exactly the off-axis the jaws cover before the
## animal has to turn its body. So the shape a player learns to read here is the
## shape that decides every bite, and the two cannot drift apart.
##
## Anchored on the resting mouth rather than the live one for the same reason the
## reach is solved from there: a zone that shrank as the animal dipped its head
## toward something would be telling the player their target had moved away.
func _draw_bite_zone(scale: float) -> void:
	if actor.stature == null or actor.body == null:
		return
	var band: Vector2 = actor.aim.band if actor.aim != null else Volume.ground()
	var arm: float = Reach.span_onto(actor, band)
	if arm <= 1.0:
		return
	var mouth: Vector2 = actor.jaw_rest_point()
	var facing: float = actor.head_look_dir.angle()
	var edge := Color(INK, 0.18)
	draw_arc(mouth, arm, facing - Reach.OFF_AXIS, facing + Reach.OFF_AXIS,
		36, edge, scale, true)
	# The two ends of the sweep, so the arc reads as a region the mouth covers
	# rather than as a stray curve lying on the ground.
	for side in [-Reach.OFF_AXIS, Reach.OFF_AXIS]:
		var out: Vector2 = Vector2.RIGHT.rotated(facing + side)
		draw_line(mouth + out * (arm * 0.82), mouth + out * arm, edge, scale, true)


## The outline of whatever is targeted, traced over the thing itself.
##
## Off the same primitives the hit test scored and the view drew, so what is
## highlighted is exactly what a bite would name: the bone between two joints,
## the circle of the head, the width of the body at the station picked. Anything
## that had to reconstruct its own idea of where a leg is would eventually
## disagree with the one that decides the damage, and the highlight would start
## lying at precisely the moments it matters.
func _draw_target_shape(pick: Reticle.Pick, scale: float, ink: Color = INK) -> void:
	var mark := Color(ink, 0.42)
	if pick.obstacle != null:
		draw_arc(pick.obstacle.drawn(pick.height), pick.obstacle.girth(),
			0.0, TAU, 28, mark, scale, true)
		return
	var target := pick.creature as Creature
	if target == null or pick.hit == null or target.body == null:
		return
	match pick.hit.kind:
		AnatomyState.HEAD:
			draw_arc(target.body.head.pos, target.body.head_radius + 2.0 * scale,
				0.0, TAU, 24, mark, scale, true)
		AnatomyState.LIMB:
			var limb: Limb = target._limb_by_key(pick.hit.limb_key)
			if limb == null:
				return
			if pick.hit.limb_segment >= 2:
				draw_arc(limb.joints[2], limb.foot_radius(target.size_scale) + 2.0 * scale,
					0.0, TAU, 18, mark, scale, true)
			else:
				# The drawn chain rather than the plan one: this is the leg as the
				# player sees it, hanging below the body, and it is the thing that has
				# to be picked out from the three others crossing it.
				draw_line(limb.joints[pick.hit.limb_segment],
					limb.joints[pick.hit.limb_segment + 1], mark, 2.0 * scale, true)
		_:
			# The body's own width at the station picked, which is the span of flesh
			# one bite there would be taken out of.
			draw_line(target.body_point(Vector2(pick.hit.spine_t, -1.0)),
				target.body_point(Vector2(pick.hit.spine_t, 1.0)), mark, 2.0 * scale, true)
