## Procedural locomotion: decides where each foot wants to be, when it should
## pick up, and where it should land. No animation clips, no timelines.
##
## The rule is entirely reactive:
##   * every foot has an ideal position derived from the body's current pose;
##   * a planted foot stays nailed to the world until it drifts further than
##     `stride_distance` from that ideal;
##   * when it does, it arcs to a new spot slightly *ahead* of the ideal and
##     re-plants there.
##
## Because the trigger is distance rather than a timer, step frequency falls out
## of movement speed for free — walk slowly and steps are rare, sprint and they
## come fast — and the creature is naturally still when idle.
##
## Order within update(): retarget -> solve the footfall pattern -> advance
## in-flight steps -> decide new steps -> let the body down onto them -> solve IK.
## Steps are advanced before new ones are chosen so the "is anything from another
## beat still in the air?" test sees this tick's truth, and the body is settled
## before the chains are posed so each leg is solved to the height its own foot
## has just put the shoulder at.
##
## Which foot goes next is not decided here — see Footfall, where it falls out of
## the animal's proportions and how fast it is going for its size. What this file
## owns is when a foot is *due*, which is still the distance rule above.
class_name Gait
extends RefCounted

## A few target/IK passes are enough for a two-bone chain to route around a
## smooth body capsule. Corrections are capped so a deeply spawned overlap
## unfolds over adjacent frames rather than making a foot teleport.
const LIMB_CONTACT_ITERATIONS: int = 6
const LIMB_CONTACT_SLOP: float = 0.35
const STEP_RETARGET_RESPONSE: float = 14.0
const LANDING_PREDICTION_STRIDES: float = 0.65

# --- what a failing limb does -------------------------------------------------
# Every constant below shapes how one number from BodyState turns into movement.
# None of them names a behaviour: there is no limp here, no drag, no collapse.
# There is a shorter stride, a slower swing, a lower foot and a limb that stops
# asking to be picked up — and a creature doing all four at once on one leg is
# limping, without anything having decided to.

## Stride left to a limb with no force at all, as a fraction of its healthy one.
## This is the whole of the limp: a weak leg reaches less far, its diagonal
## partner does not, and the gait's own distance trigger turns that asymmetry into
## a short-long-short rhythm on its own.
const STRIDE_FLOOR: float = 0.34
## How much longer a spent limb takes to swing through. Weakness is slowness as
## well as shortness, and without this a feeble leg would flick through its little
## stride at full speed and read as twitchy rather than laboured.
const SWING_SLOWEST: float = 2.1
## Foot clearance left to a limb that cannot work its own joint. At zero the foot
## never leaves the ground, so a limb with a cut nerve is dragged along it — the
## drag is a consequence of no lift, not a mode.
const LIFT_FLOOR: float = 0.0
## Working envelope left to a limb with no range of motion, and the further
## collapse a limb that cannot carry itself folds to. Kept clear of Limb.REACH_MIN
## so the envelope never inverts.
const REACH_FLOOR: float = 0.60
const FOLD_REACH: float = 0.70
## Swing fan left to a stiffened limb.
const SWING_FAN_FLOOR: float = 0.55
## Load-bearing at which a limb stops being asked to carry the body. It still
## exists, is still solved and is still dragged; it just is not stood on.
const SUPPORT_MIN: float = 0.30
## Below this much command a limb no longer initiates steps at all.
const CONTROL_MIN: float = 0.12
## How far a badly controlled foot misses its mark by, as a fraction of stride. A
## damaged nerve does not merely weaken a limb — it makes it inaccurate, and this
## is that: the foot is put down near where it was aimed rather than on it.
const PLACEMENT_SCATTER: float = 0.55

## Working envelope a limb keeps once there is no longer any ground under it.
## Nothing is holding a foot out in mid-air, so it comes in under the body — but
## the leg is still a leg and still attached, so this is a tuck rather than a
## fold. Feet do not plant, do not land and make no sound while it applies,
## because there is nothing there for them to do any of that against.
const TUCK_REACH: float = 0.62
## How fast a tucked limb draws in. Slower than a step, because the leg is being
## carried rather than placed.
const TUCK_RESPONSE: float = 7.0

# --- how far the body comes down ----------------------------------------------
# How high the foot comes up, how long it takes to get there, how far it goes and
# how quickly the body follows it are all `Locomotion`'s answers now — they are
# arithmetic on the animal's own mass, muscle and bones, and none of them can be a
# number typed into a preset. What is left here is the one rule about how far the
# body is allowed to sag when nothing is holding it up properly.

## Least the body may sag toward, as a share of the height its posture asks for.
## A creature whose feet have all fallen behind it is crouching, not collapsing.
const SUPPORT_FLOOR: float = 0.45


var limbs: Array[Limb] = []
## What this body can do about moving itself: its stride, its cadence, how long
## its feet stay down and how much of the vault its joints swallow. Owned by the
## creature and handed in each tick, for the same reason the anatomy is — it is a
## description of the whole animal, and three other systems read it too.
var loco: Locomotion = Locomotion.new()
## What this body can do about leaving the ground. Handed in beside the
## locomotion and for the same reason: the footfall pattern needs to know whether
## a girdle can throw the animal at all before it will let the two limbs of one
## work as a single pair, and that is a question about muscle, joint travel and
## elastic tissue rather than about anything this file measures.
var leap: Leap = Leap.new()
## How this body holds its legs under it. Owned here rather than passed in for
## the same reason the limbs are: it is a fixed property of the animal being
## walked, not a per-tick input, and every line below that reads it would
## otherwise have to be handed it.
var posture: Posture = Posture.new()
## In what order the four feet come down. Solved here each tick because every
## input it takes is something this file has just measured — the travel each limb
## has, how far apart the girdles are, how fast the sockets are going — and
## because it is the one part of the gait that changes several times a second as
## the animal speeds up. See Footfall: it is three numbers, and every gait a
## terrestrial animal has is a point in them.
var footfall: Footfall = Footfall.new()
## World-space contacts completed during the most recent update. This is motion
## state, not audio: Creature announces the landing and the world decides what
## sensory event, if any, it produces.
var landed: PackedVector2Array = PackedVector2Array()

# --- what the legs are currently holding the body at --------------------------
# Read out rather than set: each is a measurement of the four feet, taken after
# they have been placed. Between them they are the whole of the creature's weight
# shift, and none of them is animated — a body bobs because its feet moved, and
# leans because the ones on one side are further out than the ones on the other.

## Height the shoulders and the hips are actually being held at. Two numbers
## because they are held up by two different pairs of legs, and an animal whose
## arms are shorter than its legs stands nose-down without anything saying so.
var shoulder_height: float = 0.0
var hip_height: float = 0.0
## Height of the middle of the back — what Stature reads as the body's clearance.
var support: float = 0.0
## Whether the three above are a measurement yet. False until the first tick has
## placed four feet, and until then nothing may read them: a body with no gait
## solved has no feet to be standing on and has to fall back on its posture.
var measured: bool = false

# --- how the body is tipped on its feet ---------------------------------------
# The other half of the same measurement `shoulder_height` and `hip_height` are.
# Four legs hold a body up at four corners, and a body held at four different
# heights is a body that is tipped — nose down as it reaches, rolled toward the
# side its weight is on. Both are read off the feet and neither is animated: a
# camel rolls because the two legs on one side are up together, and a walking
# elephant sways because it puts its weight over the three that are down.

## How steeply the body is tipped, nose to tail and flank to flank: world height
## gained per world pixel travelled along the animal, in its own frame. Positive
## pitch is nose-up; positive roll is the +perp flank held high.
##
## A slope rather than a height difference, because the difference on its own is
## meaningless without knowing what it is spread over — four pixels between the
## shoulders and the hips is a level animal on a long body and a steep one on a
## short body, and the thing that has to draw it needs the second answer. Measured
## against the animal's actual stance, so a narrow-tracked build genuinely rolls
## further for the same difference in how its two sides are held, which is exactly
## why a narrow-tracked build rolls.
var pitch: float = 0.0
var roll: float = 0.0
## Height each corner is being carried at, keyed as the limbs are. What `pitch`
## and `roll` are the two differences of.
var corner: Dictionary = {"FL": 0.0, "FR": 0.0, "RL": 0.0, "RR": 0.0}
## How far the two ends of the animal have converged: +1 is a back folded right
## up with the hind feet swung forward under the shoulders, -1 one stretched out
## at full extension, 0 a body of its ordinary length.
##
## The measurement is the difference between where the hind feet are standing
## fore-and-aft and where the fore feet are, and it tells the two regimes apart on
## its own without being told which one it is in. Under any alternating gait the
## limbs of a pair are half a cycle apart, so their offsets cancel and this stays
## at nothing however hard the animal is working. Under a bound or a gallop the
## pair moves *together* — both hind feet forward, both fore feet back — and it
## swings across its whole range twice a stride, which is a back folding and
## extending. Nothing had to detect a gallop to make the spine flex in one.
var gather: float = 0.0

# --- the beat -----------------------------------------------------------------
# Two values and they are the whole of the sequencing state. Which foot last left
# the ground, and how long ago — everything about which foot goes next is that
# pair measured against the pattern `Footfall` has derived. No clock runs: this is
# a stamp taken when something happens, so a creature standing still has a stale
# one and nothing reads it.

## How fast something outside is moving these joints this tick — see `update`.
## Zero on every walking animal, which is the guarantee that nothing below
## behaves differently for the existence of the jump.
var _drive: float = 0.0

var _beat_key: String = ""
var _beat_age: float = 0.0
## Monotonic seconds this gait has been solved for. Only ever read as differences
## — when did this limb last lift, how long ago was that — so it never has to be
## reconciled with anything else's clock.
var _clock: float = 0.0
## How much of a new interval is believed at once. Half, because a cycle that
## followed every stumble would be no more use than no cycle at all, and one that
## crawled would still be describing the walk after the animal had broken into a
## run.
const CYCLE_BLEND: float = 0.5
## Longest gap between two lifts of the same limb that still counts as a cycle
## rather than as the animal having stopped and started again.
const CYCLE_MAX: float = 4.0
## Weight given to the pattern against sheer overdue-ness when the two disagree.
## The pattern has to win most contests or it is not a pattern; it may never win
## all of them or a limb held off the beat by an obstacle would be towed forever.
## Every limb's beat comes round once a cycle, so this is a delay at worst.
const BEAT_AUTHORITY: float = 2.4
## Past this much of a cycle since anything last stepped, the beat is stale and
## the body is simply standing. Sequencing off it would be sequencing off a
## creature that stopped for a second and started again.
const BEAT_STALE: float = 2.0


func setup() -> void:
	limbs.clear()
	landed.clear()
	var fl: Limb = Limb.new(); fl.setup("FL", Limb.FRONT, 1.0)
	var fr: Limb = Limb.new(); fr.setup("FR", Limb.FRONT, -1.0)
	var rl: Limb = Limb.new(); rl.setup("RL", Limb.REAR, 1.0)
	var rr: Limb = Limb.new(); rr.setup("RR", Limb.REAR, -1.0)
	# Order matters only as a last tie-breaker: two feet exactly as overdue as each
	# other and exactly as close to their own beat are separated by this and
	# nothing else. Interleaved rather than listed by girdle so that when it does
	# decide, it does not hand a whole pair the same slot.
	limbs = [fl, rr, fr, rl]


## `state` is what the anatomy says the four limbs can currently do. Left null —
## or given a body with nothing wrong with it — every line below runs on the
## values it always did, so a healthy creature is unaffected by the existence of
## the whole system.
## `reference` is the height the picture is registered to, and `airborne` says
## there is no ground under the feet at all. Both are consequences of the 2.5D
## layer above this one; left at their defaults every line below runs exactly as
## it did before it existed.
##
## `surface_query` is what is under a foot: handed a plan position, a foot radius
## and the highest that foot could be put down, it answers with the height of the
## surface there. Left out, the floor is at zero everywhere, which is the flat
## world this solver was written in and every line below still runs unchanged in
## it. `load` is what each girdle's joints are being asked for this tick — folded
## toward a crouch in x for the forelimbs and y for the hind, or extended toward a
## push where it is negative — and `drive` is how quickly whatever is asking is
## moving them, in response per second. See `_stance_extension` for the first and
## `_carry_body` for why the second has to come from outside: a body follows its
## feet at the pace its feet are moving, and when the feet are being driven rather
## than walked, only the thing driving them knows what that pace is.
func update(delta: float, body: BodyShape, move_dir: Vector2, speed_norm: float,
		p: CreatureParams, scale: float,
		collision_query: Callable = Callable(),
		state: BodyState = null,
		reference: float = 0.0, airborne: bool = false,
		surface_query: Callable = Callable(), load: Vector2 = Vector2.ZERO,
		drive: float = 0.0) -> void:
	landed.clear()
	_drive = maxf(drive, 0.0)
	if body.anchors.is_empty():
		return

	var top_speed: float = maxf(p.move_speed * scale, 1.0)
	var impaired: bool = state != null and state.impaired
	var arm: float = p.arm_length * scale
	var leg: float = p.leg_length * scale
	# What the posture asks for, before the feet get a say. The two pairs are
	# quoted separately because they are held up by different bones: a body with
	# short arms stands nose-down, and nothing had to decide that it should.
	#
	# Against what the joint stands at rather than against the whole bone, and that
	# is an angle rather than a fudge factor: an elbow at a hundred and two degrees
	# is a chain measuring seventy-eight per cent of itself, and one at a hundred
	# and seventy-three is a chain measuring ninety-nine and a half. Both are legs
	# a real animal stands on, and the second was previously unreachable — which is
	# why every build in the game stood in the same crouch. See Articulation.
	#
	# ...and then folded, by however much of its fold the animal is spending on
	# being lower. Nothing else about the crouch is written anywhere: a leg held
	# at less of itself is a shorter leg, so the stance comes in, the body comes
	# down with it, and the bands, the silhouette and the picture follow because
	# every one of them is read off the height the feet are holding.
	#
	# Per girdle, because the two ends of an animal are not the same limb. A cat
	# carries a straight strut in front and a folded spring behind, so its
	# shoulders and its hips are held up by legs standing at quite different
	# fractions of themselves — and the fact that they arrive at nearly the same
	# height is a consequence of the bones being different lengths, not of anything
	# levelling the body.
	var wants := Vector2(
		_rest_clearance(arm, _stance_extension(load.x, Limb.FRONT), p, Limb.FRONT),
		_rest_clearance(leg, _stance_extension(load.y, Limb.REAR), p, Limb.REAR))
	if not measured:
		# Somewhere for the first limb solve to hang its sockets from. Replaced by
		# a real reading of the feet at the end of this same tick.
		shoulder_height = wants.x
		hip_height = wants.y
		support = (wants.x + wants.y) * 0.5

	# --- 1. retarget: recompute each foot's ideal position ------------------
	for limb in limbs:
		_read_function(limb, state, impaired)
		# Whether this limb is one of the ones the animal is standing on. False on
		# a forelimb too short to reach the ground the hips are holding the body
		# over — see Locomotion.BEARING_RATIO — and it is not an injury or a mode:
		# the leg is sound, it is simply carried rather than walked, exactly as
		# every limb is while the body is off the ground.
		limb.bearing = limb.pair == Limb.REAR or loco.forelimbs_bear
		if airborne or not limb.bearing:
			# Nothing to stand on. The limb keeps every capability it had — this is
			# not damage — it simply loses the ground those capabilities were being
			# spent against, so its envelope draws in and it stops being placed.
			#
			# ...unless it is being put out for something, which is the one thing a
			# leg with no floor under it still does. A limb asked to extend is a limb
			# reaching, and it reaches out of the same tuck rather than round it: at
			# full extension the envelope is the whole of the limb's again, so a body
			# coming down out of an arc genuinely has its legs down before it arrives
			# rather than snapping them out on contact. On a limb nobody is asking
			# anything of, `load` is zero and this is the line it always was.
			limb.reach *= lerpf(TUCK_REACH, 1.0,
				clampf(-(load.x if limb.pair == Limb.FRONT else load.y), 0.0, 1.0))
		if _skip(limb):
			continue
		var a: Spine.Frame = body.anchors[limb.key]
		var front: bool = limb.pair == Limb.FRONT
		var bone: float = arm if front else leg
		# How much of the stance radius goes out to the side rather than fore and
		# aft: the tilt again, taken a second time, and the species' own width.
		var lean: float = cos(posture.tilt) * p.stance_width
		# What this limb's own girdle does with itself, cached onto the limb before
		# anything below asks. Everything that used to be a whole-animal parameter —
		# how extended it stands, how far it may straighten, how tightly it folds,
		# how wide it swings, how the two bones divide — is read here and read once,
		# so the gait, the IK, the height solve and the overlay cannot disagree.
		var joint: Articulation.Joint = loco.joint(limb.pair)
		limb.read_joint(joint)
		limb.working = _stance_extension(
			load.x if limb.pair == Limb.FRONT else load.y, limb.pair)
		limb.set_lengths(bone, posture.drawn_reach(bone), joint.upper)
		limb.foot_size = limb.foot_radius(scale)
		limb.swing_base = loco.swing_time(bone)
		limb.reference = reference
		# How high this socket is being carried — measured last tick off the feet
		# that were under it, so the leg is solved to the body it is actually
		# holding up rather than to the one the posture would like it to.
		limb.socket_height = shoulder_height if front else hip_height

		# How fast is *this* socket travelling? Every timing below is sized off
		# that rather than off the body's linear speed, so a limb on the outside
		# of a turn takes long quick strides while one near the turn centre
		# barely shuffles — and a creature pivoting on the spot, whose linear
		# speed is zero, still walks its hind feet around.
		limb.track_socket(a.pos, delta, move_dir, body.head.pos)
		limb.pace = maxf(speed_norm, clampf(limb.socket_speed / top_speed, 0.0, 1.0))

		# How far from directly beneath its own socket the foot may be put down.
		# The triangle rather than a flat projection of the leg, and that is what
		# an upright animal's stride is made of: a near-vertical limb shows barely a
		# third of itself in plan view, so measured that way its foot could never
		# be set down far enough forward to be walking — while the actual leg, most
		# of it spent going down and the rest available to lean, has half as much
		# again to reach with.
		# Quoted against the height this animal *stands* at rather than the height
		# it happens to be at this instant, and that is not a shortcut — measuring
		# it off the current sag closes a loop with nothing damping it. A body
		# carried low reaches further across the ground, feet placed further out
		# hold the body lower still, and a creature that dipped once on being set
		# down would settle into a permanent splay-legged crouch with its shoulders
		# at half height. The envelope is a property of the stance; the sag is what
		# happens inside it.
		# ...and how much of the gap the foot's own toe takes out of it over the
		# stance. Half the peak, because the toe rolls up progressively and the disc
		# it is sizing is symmetrical while the push-off is not: all of it happens at
		# the back, where the foot needs the reach, and none at the front.
		var push: float = limb.foot_size * limb.push * 0.5 * limb.flex
		limb.plan_limit = loco.walking_reach(bone, wants.x if front else wants.y,
			_max_reach(limb), limb.pair, push)
		# ...and again, now that there is a reach to narrow the stance against. The
		# height everything below is sized at is the height this animal *stands* at,
		# which is neither the posture's guess nor where the wave has it this
		# instant: the stance is squeezed inward to leave the stride room, and a
		# squeezed stance is a foot closer in, which is a socket held higher.
		#
		# With the wave taken out, and that is not a detail. The envelope is sized
		# off this height and a height that breathed with the body's own undulation
		# would be an envelope that breathed — so the radius a planted foot is
		# clamped into would move under it twice a cycle and skid it along.
		var steady: float = sqrt(maxf(pow(bone * limb.working, 2.0)
			- _steady_stance(limb, p, lean), 0.0))
		limb.plan_limit = loco.walking_reach(bone, steady, _max_reach(limb),
			limb.pair, push)

		# Where this foot rests, then: the circle the leg reaches across at the
		# stance it stands in, and how much of it the swing plane has left out to
		# the side. Both are the tilt — the first is the leg seen from above, the
		# second is that same cosine again.
		#
		# ...and then narrowed, if it has to be, to leave the stride somewhere to
		# happen — see Locomotion.stance_limit. The two are spent out of one disc,
		# and a stance that uses the whole of it is an animal with no stride and
		# feet that are dragged by its own wave.
		limb.set_stance(a, p, minf(
			posture.plan_reach(bone * limb.working) * limb.reach,
			loco.stance_limit(limb.plan_limit, limb.sway) / maxf(lean, 0.0001)), lean)
		limb.inboard_limit = body.socket_out.get(limb.key, 0.0) * posture.adduction()

		# ...and now the height again, off the stance the limb actually stands in
		# rather than the one it was quoted. The two are the same whenever the
		# posture gets the width it asked for and they part company whenever it does
		# not — which is every sprawled build, whose stance is squeezed inward to
		# leave the stride room. Left unrefined, the levelling term spends every
		# tick pulling the body below what its own legs are holding it at and the
		# legs bend to meet it, which is a creature standing a good deal more folded
		# than its joints say.
		#
		# Measured with the sway taken out, and that is not a detail. The envelope
		# is sized off this height, and a height that breathed with the body's own
		# wave would be an envelope that breathed — so the radius a planted foot is
		# clamped into would move under it twice a cycle and skid it. The stance is
		# narrowed by the wave; where the animal *stands* is not.
		# ...and the height this limb is actually holding its end of the body at,
		# which is the stance it ended up in and so does move with the wave. It is
		# the levelling term rather than the envelope: where the body wants to be
		# rather than where its foot may go, and the two want different answers to
		# the same question for the reason above.
		limb.rest_height = sqrt(maxf(pow(bone * limb.working, 2.0)
			- Vector2(limb.rest_lat, limb.rest_fore).length_squared(), 0.0))

		# ...and how much of that the fore-and-aft swing may use — see
		# Locomotion.excursion. Quoted at the bottom of the animal's own bob, so it
		# is the travel the limb has over a whole stride rather than the travel it
		# has at this instant, and what the sideways stance is spending is already
		# taken off it. That last part is not a detail: a sprawled foot rests most
		# of a leg out to the side, so the fore-and-aft room left on the same disc
		# is a good deal less than the disc is wide, and a stride sized off the
		# whole disc would have the foot skidding along the boundary for the last
		# third of every step.
		# Against where the sway puts the foot rather than where it rests, because
		# the boundary is met at the worst instant of the wave and not at the
		# average one.
		# Nothing is added here for what the spine contributes to a stride, and that
		# is deliberate rather than an omission. The back's share of a gallop is
		# real, but it is not extra travel for the *limb*: it moves the shoulder,
		# and a foot whose socket has been carried forward has covered more ground
		# without having reached any further from it. It arrives on its own through
		# `track_socket`, which measures where the socket actually went. Written in
		# here instead it would be a stride longer than the envelope the same line
		# clamps the foot into — and a stride longer than the travel a limb has is
		# not a long stride, it is no stride at all: the trigger can never fire and
		# the leg is towed for as long as the creature walks.
		# ...and the width that travel was measured against, kept so the placement
		# cannot exceed it. One disc, spent once: whatever the stance and the body's
		# own wave are using sideways is not available fore-and-aft, and a foot put
		# down outside it would be taking the stride's share of the budget.
		limb.lat_limit = absf(limb.rest_lat) + limb.sway
		limb.sweep_limit = maxf(
			loco.excursion(bone, steady, limb.lat_limit,
				_max_reach(limb), _swing_fan(limb), limb.pair, push),
			0.001)

		# Stride is that travel, and nothing else. Not a species number capped by
		# the envelope afterwards — a stride longer than the travel the limb has is
		# not a long stride, it is no stride at all: the clamp skids the planted
		# foot along the boundary, the distance trigger is never reached, and the
		# leg is towed for as long as the creature keeps walking. That is what a
		# columnar animal's hind legs were doing, and there was no value of
		# `stride_distance` that would have fixed it, because the number that
		# decides it is the length of the leg and the angle it is carried at.
		#
		# What is left over from the anatomy is the two things that are genuinely
		# about this tick: a slow limb shuffles rather than lunging, and a limb with
		# no force left in it reaches less far. Both of them only ever make the
		# stride *shorter*, and that is not a coincidence — it is the invariant. The
		# posture used to have a `stride_gain` here as well, a per-stance number
		# that made an upright animal stride further than its own travel, and it was
		# the same mistake the paragraph above is about, hidden behind a table: at
		# 1.15 it spent exactly the headroom `Locomotion.STRIDE_SHARE` reserves, so
		# the trigger fired only after the foot had been skidded along its own
		# envelope for the last few pixels. A stance that wants a longer stride
		# already has one, because it stands its legs at a different angle.
		# ...and how long a step this limb could take if nothing else on the animal
		# had a say. It has not got the last word — see `_share_stride`, which is
		# where a body of four legs becomes one gait — so what is written here is a
		# capacity rather than the answer.
		limb.stride = loco.stride(limb.sweep_limit, p.foot_lead)

	# --- 1a. one animal, one stride -----------------------------------------
	_share_stride()

	for limb in limbs:
		if _skip(limb):
			continue
		var a: Spine.Frame = body.anchors[limb.key]
		limb.plan[0] = a.pos
		limb.joints[0] = a.pos + Posture.drop(limb.socket_height, reference)
		limb.heights[0] = limb.socket_height
		# Where this foot would like to be: its rest stance, thrown ahead along the
		# way its own socket is travelling. Clamped into the envelope, because an
		# ideal outside it is not an ideal — it is a point the foot is measured
		# against, aimed at and can never arrive at, so the limb reads as
		# permanently overdue and is skidded along the boundary trying to close a
		# gap that does not shut.
		#
		# It matters most on a body that walks with its spine. A sprawled animal's
		# socket is swinging sideways as fast as the animal is going forwards, so
		# half of "ahead" for that shoulder is out past the side of its own leg —
		# and the wave puts it there twice a cycle, every cycle.
		limb.ideal = limb.clamp_to_envelope(a, limb.rest_point(a)
			+ limb.travel * (p.foot_lead * limb.stride * limb.pace))

		if not limb.initialised:
			# First tick: plant the feet where they already want to be so the
			# creature does not start by taking four simultaneous steps.
			limb.planted = limb.ideal
			limb.ground = limb.ideal
			limb.visual = limb.ideal + limb.rise()
			limb.initialised = true

		# With nothing underneath it a foot has nowhere to be nailed to, so it is
		# carried with the socket instead of being left behind by it. This is the
		# whole of the tuck: the error never grows, so nothing further down asks
		# this limb to step, and a leg that is not stepping is a leg being held.
		#
		# The same is true of a forelimb that never reaches the ground, and it is
		# the same line rather than a second one. There is no difference between an
		# arm with no floor under it because the animal has jumped and an arm with
		# no floor under it because the animal is standing on two legs — in both
		# cases nothing is holding the limb out, so it comes in under the chest and
		# is carried there.
		if airborne or not limb.bearing:
			limb.stepping = false
			limb.planted = limb.planted.lerp(limb.ideal, 1.0 - exp(-TUCK_RESPONSE * delta))

		# A foot the body has outrun skids to the edge of what the limb can
		# reach rather than staying nailed down and dislocating the leg. The
		# error stays large either way, so it is still first in line to step.
		#
		# This is also, unchanged, what dragging a dead limb looks like: a leg that
		# never picks up is a leg the body permanently outruns, so it is towed
		# along its own envelope for as long as the creature keeps walking. The
		# behaviour was already here — all a severed nerve does is stop the limb
		# taking the step that would have ended it.
		#
		# Placement is always decided for a foot on the ground, whatever the foot is
		# doing at this instant: a plant happens on a surface, so the reach that has
		# to be there is the reach down to whatever is under it. Which is no longer
		# always the floor — it is the top of whatever this foot is standing on, and
		# on the open plain that is the same number it always was.
		limb.surface = _surface_under(limb, limb.planted, scale, surface_query)
		_read_toe(limb, a)
		limb.foot_height = _hold(limb, airborne)
		# Against what the joint can do rather than against the stride, and the two
		# are different questions. `sweep_limit` is how far this limb *walks*: it is
		# where the gait may choose to put a foot down. Where a foot may legally
		# *be* is the joint's own fan, which is wider — and a foot that has been
		# shoved outside the walking envelope by something it bumped into is
		# somewhere it can perfectly well stand. Held to the stride instead, it is
		# hauled back into the corridor every tick while the contact pass pushes it
		# out again, and the leg buzzes between the two forever.
		limb.planted = limb.clamp_to_envelope(a, limb.planted, _swing_fan(limb))
		limb.error = limb.planted.distance_to(limb.ideal)

	# --- 1b. what pattern are these four feet in? ---------------------------
	# Here rather than higher up because every input it takes is something the
	# loop above has just measured: how far each limb actually travels, how fast
	# its socket is going, how far apart the girdles have ended up on a body that
	# is bent into a turn. Deriving it from the parameters instead would be a
	# second opinion about a body that is already solved, and the two would
	# disagree exactly when the animal was doing something interesting.
	_solve_pattern(delta, body, p)

	# --- 2. advance any step already in flight ------------------------------
	for limb in limbs:
		if _skip(limb):
			continue
		if not limb.stepping:
			limb.ground = limb.planted
			limb.foot_height = _hold(limb, airborne)
			limb.visual = limb.planted + limb.rise()
			continue

		# Keep re-aiming the landing spot at the (moving) ideal while airborne,
		# otherwise feet land in stale positions during a turn. The aim point is
		# where the ideal will be when the foot actually touches down, not where
		# it is now — see _landing_spot().
		var remaining: float = (1.0 - limb.step_t) * limb.step_duration
		var retarget: float = 1.0 - exp(-STEP_RETARGET_RESPONSE * delta)
		var aim: Vector2 = limb.clamp_to_envelope(
			body.anchors[limb.key], _landing_spot(limb, remaining))
		limb.step_to = limb.step_to.lerp(aim, retarget)
		# The spot keeps moving, so what is under it keeps changing: a foot aimed
		# past the edge of a ledge while it is in the air is a foot that is about to
		# be put down on the floor instead, and it has to arrive at the right height
		# or the leg lands inside the ground.
		limb.step_to_surface = _surface_under(limb, limb.step_to, scale, surface_query)

		limb.step_t += delta / maxf(limb.step_duration, 0.001)
		if limb.step_t >= 1.0:
			limb.step_t = 1.0
			limb.stepping = false
			limb.planted = limb.step_to
			limb.surface = limb.step_to_surface
			landed.append(limb.planted)

		# Smoothstep along the ground path (ease out of and into the plant) with
		# a sine arc for the height — a half period is exactly one hop.
		var eased: float = smoothstep(0.0, 1.0, limb.step_t)
		limb.ground = limb.step_from.lerp(limb.step_to, eased)
		# Two terms now, and only the second is the step. The first is the ramp from
		# the surface the foot left to the one it is arriving at, which is what makes
		# a step onto a ledge a step *up* rather than a step that ends underground —
		# and on flat ground the two surfaces are equal and it contributes nothing,
		# which is why the arc below is unchanged.
		#
		# Clearance is the joint's own doing, so it is priced off what is still
		# working the knee rather than off the limb as a whole. A leg that can
		# still be swung from the shoulder but cannot flex below it scuffs.
		limb.foot_height = lerpf(limb.step_from_surface, limb.step_to_surface, eased) \
			+ sin(limb.step_t * PI) * _step_clearance(limb) \
			* (0.45 + 0.55 * limb.pace) * lerpf(LIFT_FLOOR, 1.0, limb.flex)
		limb.visual = limb.ground + limb.rise()

	# --- 3. decide which feet pick up ---------------------------------------
	# A body with nothing under it never picks a foot up, because a step is a
	# push against the ground and there is none. Skipping the contest outright
	# rather than failing every limb's test is the same distinction `_skip` draws:
	# these legs are not stepping badly, they are not stepping.
	if airborne:
		_carry_body(delta, wants)
		for limb in limbs:
			if not _skip(limb):
				_solve_limb(limb, body, p, scale, collision_query)
		return

	var aloft: int = 0
	var candidates: Array[Limb] = []
	for limb in limbs:
		if _skip(limb):
			continue
		if limb.stepping:
			aloft += 1
			continue
		# Recompute against this tick's plant: step 2 may have just landed this
		# foot, and deciding on the pre-landing error would re-fire it instantly.
		limb.error = limb.planted.distance_to(limb.ideal)
		# A limb with no command does not decline to step — nothing asks it to.
		# It stays out of the contest entirely and is dragged by the clamp above.
		if not _can_step(limb):
			continue
		if limb.error >= limb.stride:
			candidates.append(limb)

	# Best fit to the beat first, and overdue-ness is now the tie-breaker rather
	# than the rule. This is where a footfall pattern actually becomes an order.
	#
	# Overdue-ness alone was what the gait had, and it is not a pattern: it says
	# only that a foot that has drifted a long way should go before one that has
	# not, so the sequence that came out was whatever the geometry happened to
	# produce — which, on every build in the game, was the same near-trot. What
	# each candidate is scored on now is how close lifting it *this tick* comes to
	# the phase `Footfall` says it belongs at, measured from whichever foot last
	# left the ground. The pattern wins most contests, because it has to be a
	# pattern; it cannot win all of them, because a foot held off its beat by an
	# obstacle would then be towed forever. Both are one number: BEAT_AUTHORITY.
	#
	# Overdue-ness is still quoted against each limb's own stride rather than in
	# raw pixels, because the four are not asking the same question: an arm is
	# shorter than a leg, strides shorter for it, and is due at a smaller drift.
	var elapsed: float = _beat_phase()
	candidates.sort_custom(func(a: Limb, b: Limb) -> bool:
		return _bid(a, elapsed) > _bid(b, elapsed))

	# How many feet this build will lift at once — see Footfall.lift_limit. One
	# while the animal still has to be standing at every instant, two through any
	# ordinary symmetrical gait, and every foot at once only for a body going fast
	# enough, and built well enough, to genuinely throw itself.
	var limit: int = footfall.lift_limit
	var coupling: float = clampf(p.beat_coupling * posture.coupling_gain, 0.0, 1.0)

	for limb in candidates:
		if limb.stepping:
			continue
		if aloft >= limit:
			break
		# Never lift a foot while one that belongs to a *different* beat is still
		# in the air. That is what keeps the animal standing, and it is the same
		# rule the hard-wired diagonal gate used to be — only now which limbs are
		# opposed is read off the pattern instead of off which corner of the body
		# a leg happens to be on. In a trot the diagonal is the partner; in a pace
		# it is the leg on the same side; in a bound it is the other girdle.
		if _beat_blocked(limb):
			continue

		_start_step(limb, body, p, scale, surface_query)
		_mark_beat(limb)
		aloft += 1

		# ...and pull anything that shares this beat onto it, if it is anywhere
		# near due. This is the difference between a readable gait and four legs
		# doing their own thing, and it is what makes a pair land *together*: a
		# bound, a pace and a pronk are all this line firing on limbs the pattern
		# has put in phase. Coupling 0 disables it entirely.
		for other in limbs:
			if other == limb or other.stepping:
				continue
			if aloft >= limit:
				break
			if not footfall.shares_beat(limb.key, other.key):
				continue
			# The same gate as the contest above, and it has to be here too: a beat
			# is an invitation, not an order. Without this a dead limb is pulled
			# into its partner's step and picks itself up, which is the one thing a
			# limb with no nerve reaching it must never do — and it would happen on
			# the alternate ticks, so the leg would appear to work intermittently.
			if not _can_step(other):
				continue
			if other.error > other.stride * (1.0 - coupling):
				_start_step(other, body, p, scale, surface_query)
				aloft += 1

	# --- 4. let the body down onto the feet that were just placed -------------
	# Before the limbs are posed rather than after, and the ordering is the whole
	# difference between a leg that reaches and one that skids. A foot is put down
	# where the stride says, which is out at the reach the leg has once the body
	# has come down over it; solve the chain first and the shoulder is still up
	# where it was last tick, the leg is a fraction too short for its own foot, and
	# the envelope drags the foot back in. Then the body sinks, the foot is let out
	# again, and the two chase each other for the whole of the stance phase — which
	# is exactly what a planted foot creeping backward under a walking animal is.
	#
	# Settling first, the chain is solved to a body that is already standing where
	# these feet put it.
	_carry_body(delta, wants)
	for limb in limbs:
		if _skip(limb):
			continue
		# Its *own* corner, not its girdle's. The two are the same on a body
		# standing square and they part company the moment it is not: a shoulder on
		# the side the animal has its weight over is genuinely carried higher than
		# the one on the side that is swinging through, so that leg is solved more
		# extended and its partner more folded. Which is what a roll is — and it is
		# a fact about the limb rather than a lean drawn over the top of one, so it
		# reaches the picture through the leg poses whether anything ever draws the
		# torso tipped or not.
		limb.socket_height = float(corner[limb.key])

	# --- 5. solve the limbs ---------------------------------------------------
	for limb in limbs:
		if _skip(limb):
			continue
		_solve_limb(limb, body, p, scale, collision_query)


## Re-derives the footfall pattern from the limbs as they have just been solved.
##
## Everything handed over is a measurement taken this tick. The speed is the mean
## of the four sockets rather than the body's linear speed, for the reason every
## other timing in this file is: a creature pivoting on the spot has a linear
## speed of zero and hips going as fast as they ever do. The girdle gap is
## measured between the sockets on one flank, so a body curled into a turn reports
## the shorter distance its own feet actually have to share — which is exactly
## when a long-legged animal's feet start interfering.
func _solve_pattern(delta: float, body: BodyShape, p: CreatureParams) -> void:
	_clock += delta
	_beat_age += delta
	var pace: float = 0.0
	var walking: int = 0
	var fore: float = 0.0
	var rear: float = 0.0
	var lead_left: float = 0.0
	var lead_right: float = 0.0
	for limb in limbs:
		if _skip(limb):
			continue
		pace += limb.socket_speed
		walking += 1
		if limb.pair == Limb.FRONT:
			fore = maxf(fore, limb.sweep_limit)
		else:
			rear = maxf(rear, limb.sweep_limit)
			# Which way the animal is coming round, measured rather than asked for:
			# the hind socket on the outside of a turn sweeps the wider arc. On a
			# body running straight the two are equal and the gallop below has no
			# lead at all, which is honest — a straight-line asymmetric gait is a
			# bound, and animals pick a lead when they turn.
			if limb.side > 0.0:
				lead_left = limb.socket_speed
			else:
				lead_right = limb.socket_speed
	var speed: float = pace / maxf(float(walking), 1.0)
	var gap: float = 0.0
	if body.anchors.has("FL") and body.anchors.has("RL"):
		gap = (body.anchors["FL"] as Spine.Frame).pos.distance_to(
			(body.anchors["RL"] as Spine.Frame).pos)
	var lead: float = (lead_left - lead_right) / maxf(speed, 1.0)

	footfall.update(posture, loco, p, maxf(hip_height, 1.0), speed,
		Vector2(fore, rear), gap, lead, loco.forelimbs_bear, leap.launch)
	_measure_gather(body)


## Reads how far the two ends of the animal have converged — see `gather`.
##
## Each foot's offset from its own socket along the body, as a share of the travel
## that limb has. The hind pair's mean less the fore pair's: positive when the
## hind feet have come forward and the fore feet have gone back, which is the two
## girdles closing on each other, which is a folded back.
func _measure_gather(body: BodyShape) -> void:
	var ends := Vector2.ZERO
	var counted := Vector2.ZERO
	for limb in limbs:
		if _skip(limb) or not limb.bearing or not body.anchors.has(limb.key):
			continue
		var a: Spine.Frame = body.anchors[limb.key]
		var along: float = limb.local(a, limb.ground - a.pos).y - limb.rest_fore
		var share: float = clampf(along / maxf(limb.sweep_limit, 0.001), -1.0, 1.0)
		if limb.pair == Limb.FRONT:
			ends.x += share
			counted.x += 1.0
		else:
			ends.y += share
			counted.y += 1.0
	if counted.y <= 0.0:
		gather = 0.0
		return
	var hind: float = ends.y / counted.y
	# With no forelimbs on the ground there is nothing at the front to converge
	# with, so what the hind pair alone says is the whole of it. That is a hop
	# rather than a bound, and a hopping body does fold — over its hips.
	var forelimb: float = ends.x / counted.x if counted.x > 0.0 else 0.0
	gather = clampf((hind - forelimb) * 0.5, -1.0, 1.0)


## How far through a cycle it is since the last foot left the ground.
##
## Negative when there is no beat to measure from — nothing has stepped recently,
## or the body has been standing long enough that what did step is no longer
## telling us anything. Sequencing a creature that stopped and started again off
## a stamp from before it stopped would be sequencing off a coincidence.
func _beat_phase() -> float:
	if _beat_key.is_empty():
		return -1.0
	var cycle: float = _measured_cycle()
	if cycle <= 0.0001 or _beat_age > cycle * BEAT_STALE:
		return -1.0
	return _beat_age / cycle


## How long one limb's whole cycle is actually taking, averaged over the legs
## that have done one.
##
## The observed interval rather than the predicted one, and the difference
## matters here in a way it does not anywhere else in this file. `_body_cycle`
## divides the stride a limb is *about to* take by the speed its socket is going,
## which is the right answer for how quickly a body should settle onto its feet;
## it is the wrong one for placing a beat, because the beat has to be placed
## against the last beat that really happened. Falls back to the prediction until
## the legs have stepped twice and there is an interval to measure.
func _measured_cycle() -> float:
	var total: float = 0.0
	var count: int = 0
	for limb in limbs:
		if _skip(limb) or not limb.bearing or limb.cycle <= 0.0:
			continue
		total += limb.cycle
		count += 1
	return total / float(count) if count > 0 else _body_cycle()


## What one candidate is worth this tick: how overdue it is, less how far off its
## own beat lifting it now would be.
func _bid(limb: Limb, elapsed: float) -> float:
	var overdue: float = limb.error / maxf(limb.stride, 0.001)
	if elapsed < 0.0:
		return overdue
	return overdue - BEAT_AUTHORITY * footfall.off_beat(limb.key, _beat_key, elapsed)


## Whether a limb still in the air belongs to a different part of the cycle than
## this one — in which case this foot waits, because the two were never meant to
## be off the ground together.
func _beat_blocked(limb: Limb) -> bool:
	for other in limbs:
		if other == limb or not other.stepping:
			continue
		if not footfall.may_overlap(limb.key, other.key):
			return true
	return false


## Marks this limb as the beat everything else is now placed against.
##
## Only the limb that *won* the contest does this, not the ones pulled onto its
## beat with it: a beat is one event however many feet leave the ground on it, and
## stamping each of them in turn would make a bounding pair read as two beats a
## fraction of a second apart.
func _mark_beat(limb: Limb) -> void:
	_beat_key = limb.key
	_beat_age = 0.0


## How high the four feet are actually holding the body, and how the body follows
## them down.
##
## Nothing here decides anything. A leg is a fixed length, so a foot set down
## further from its socket is a socket held lower — that is Pythagoras, and it is
## the only rule in this function. Everything that reads as weight comes out of
## it: the body sinks as a stride reaches its extreme and rises again as the foot
## comes back under the shoulder, which is a bob at exactly step frequency
## because that is what it is a measurement of; a short-armed animal stands
## nose-down because its shoulders are held by shorter bones than its hips; and a
## columnar creature barely moves at all, because a leg held near vertical loses
## almost no height to being swung.
##
## Only feet that are down are asked. A limb in the air is not carrying anything,
## and a limb that cannot bear weight has already said so.
func _carry_body(delta: float, wants: Vector2) -> void:
	var rear: float = _pair_support(Limb.REAR, wants.y)
	# A girdle with nothing under it is not held up by legs — it is held up by the
	# back. That is what the front of a two-legged animal is doing, and it is why
	# nothing had to write a special pose for one: the shoulders ride level over
	# the hips because the spine between them is what is carrying them, and the
	# tail is what makes that balance possible. Everything else about the body —
	# the height bands, the bite reach, the drawn attitude — follows without a
	# single line knowing the creature is bipedal.
	var front: float = rear if not loco.forelimbs_bear \
		else _pair_support(Limb.FRONT, wants.x)
	# Weight takes a moment to settle onto a leg, but a body that has just been
	# built is not settling onto anything — it is already standing there. Easing
	# in from the posture's guess instead would spend the first third of a second
	# lowering the animal onto its own feet, and the feet, whose envelope is a
	# function of how high their socket is, would take a step to keep up. A
	# creature that shuffles once on being placed is a creature no fixture can
	# take aim at.
	#
	# How fast it settles is quoted per step cycle rather than per second, because
	# that is what it is a measurement of: the body follows its feet at the pace
	# its feet are moving. A response tuned for a lizard taking four steps a second
	# would smooth an elephant's whole walk into a glide.
	#
	# ...and the same sentence applies when the feet are not the ones moving. A
	# limb whose joint is being driven open is changing length on the timescale of
	# whatever is driving it rather than of the walk, and the body riding on it has
	# to keep up or the push arrives as a lag — the animal would extend its legs
	# fully and only then begin, slowly, to rise on them. So the floor under the
	# response is whatever has hold of the legs, handed in with the demand itself.
	# Nothing has hold of them on a walking animal, `_drive` is zero, and this is
	# the line it always was.
	var response: float = 1.0 - exp(-maxf(loco.settle(_body_cycle()), _drive) * delta) \
		if measured else 1.0
	measured = true
	# Eased toward what the legs are offering, and then cut off hard at what they
	# can physically reach. The two are different claims and only the second is a
	# law: a body may take its time settling onto its feet, but it may never for
	# one tick be held higher than the leg standing under it is long. Easing alone
	# leaves it a fraction of a second above its own feet after every fast
	# placement, and a body above its feet is a body floating — which is the whole
	# thing the vertical limb solve exists to prevent.
	shoulder_height = minf(lerpf(shoulder_height, front, response), _pair_ceiling(Limb.FRONT))
	hip_height = minf(lerpf(hip_height, rear, response), _pair_ceiling(Limb.REAR))
	support = (shoulder_height + hip_height) * 0.5
	_carry_corners(response)


## The same measurement again, one leg at a time, and the whole of the creature's
## weight transfer.
##
## `_pair_support` above asks what a *pair* of legs is holding its end of the body
## at and answers with whichever of the two is doing worse, because the body
## cannot ride higher than the shortest reach underneath it. That is right for the
## height, and it throws away the thing that makes a walk read as heavy: the two
## legs of a pair are usually holding their own corners at different heights, and
## a body held at four different heights is a body that is *tipped*.
##
## So the same Pythagoras, per corner, and the two differences between the four
## are the attitude. Nothing here is animated and nothing here is a lean anybody
## authored:
##
##   * a pacing animal has both legs on one side in the air at once, so that side
##     drops and the body rolls — which is a camel's roll, and it is the footfall
##     pattern showing up in the picture rather than a second system agreeing with
##     it;
##   * a bounding one has a whole girdle off the ground, so it pitches nose-up and
##     nose-down over the stride, which is what a bound is;
##   * a heavy animal walking one foot at a time leans onto the three that are
##     down, because that is where its legs are holding it;
##   * and a two-legged one pitches from its hips alone, because that is the only
##     girdle it has anything under.
##
## A limb in the air holds nothing, so its corner eases toward the *pair's* height
## rather than toward the floor — the body over an unsupported corner is held by
## the girdle and the back, not dropped.
func _carry_corners(response: float) -> void:
	for limb in limbs:
		var held: float = shoulder_height if limb.pair == Limb.FRONT else hip_height
		if not _skip(limb) and limb.bearing and not limb.stepping \
				and limb.carry >= SUPPORT_MIN:
			# The clearance this pair asks for, measured from wherever its foot
			# currently is rather than from the floor — which on a foot rolled up
			# onto its toe is a little above the floor. Left off, the levelling term
			# spends the whole push-off arguing with it: the leg lifts the body and
			# the level pulls it back down, and what comes out is a columnar limb
			# solved twenty degrees more bent than it stands.
			held = lerpf(limb.support_height(limb.working),
				limb.surface + limb.toe_rise() + limb.rest_height, loco.absorbed)
		# Eased toward what the leg is offering, and *then* cut off at what it can
		# physically reach — the same two-step the girdles get and in the same
		# order, which is the whole of why the order matters. Clamping the target
		# before the ease only limits where the corner is heading: a ceiling that
		# drops this tick leaves the corner sitting above it all the way down, and a
		# socket above what its own leg can reach is a body floating on that leg.
		# It applies to a corner with a foot in the air too — that limb is carrying
		# nothing, but it is still attached, and the body may not ride away from it.
		var settled: float = lerpf(float(corner[limb.key]), held, response)
		if not _skip(limb) and limb.bearing and limb.carry >= SUPPORT_MIN:
			settled = minf(settled, limb.carry_ceiling(_max_reach(limb)))
		corner[limb.key] = settled

	# The two differences, over the two lengths they are spread across. The levers
	# are the animal's own stance — how far apart the girdles are and how wide it
	# is standing — so both slopes come out of the geometry rather than out of a
	# constant, and a build whose feet fall close under the midline tips further
	# for the same difference in how its sides are held than one standing splayed.
	var along: float = maxf(_span(Limb.FRONT, Limb.REAR), 1.0)
	var across: float = maxf(_track(), 1.0)
	pitch = (shoulder_height - hip_height) / along
	roll = ((float(corner["FL"]) + float(corner["RL"]))
		- (float(corner["FR"]) + float(corner["RR"]))) * 0.5 / across


## The line the body tips about: the midpoint of the four sockets, and the
## animal's own fore-aft axis through it.
##
## The same two the picture is sheared about — shoulders to hips, which is the one
## line on a creature that does not swing when it looks at something — so the
## drawn attitude and the volume underneath it cannot disagree about which way the
## body is leaning or where it is leaning about.
func girdle_line() -> Array:
	var fore := Vector2.ZERO
	var rear := Vector2.ZERO
	var counted := Vector2.ZERO
	for limb in limbs:
		if limb.pair == Limb.FRONT:
			fore += limb.plan[0]
			counted.x += 1.0
		else:
			rear += limb.plan[0]
			counted.y += 1.0
	if counted.x <= 0.0 or counted.y <= 0.0:
		return [Vector2.ZERO, Vector2.RIGHT]
	fore /= counted.x
	rear /= counted.y
	var axis: Vector2 = fore - rear
	if axis.length_squared() < 0.0001:
		return [(fore + rear) * 0.5, Vector2.RIGHT]
	return [(fore + rear) * 0.5, axis.normalized()]


## Distance between the two girdles' sockets, measured on the ground plane.
func _span(a: int, b: int) -> float:
	var first: Vector2 = Vector2.ZERO
	var second: Vector2 = Vector2.ZERO
	for limb in limbs:
		if limb.pair == a:
			first = limb.plan[0]
		elif limb.pair == b:
			second = limb.plan[0]
	return first.distance_to(second)


## How wide this animal is actually standing: the mean gap between the feet on
## one side and the feet on the other. The lever a roll turns about, and the whole
## reason a columnar build rolls where a sprawled one merely leans.
func _track() -> float:
	var left: Vector2 = Vector2.ZERO
	var right: Vector2 = Vector2.ZERO
	var counted := Vector2.ZERO
	for limb in limbs:
		if _skip(limb) or not limb.bearing:
			continue
		if limb.side > 0.0:
			left += limb.ground
			counted.x += 1.0
		else:
			right += limb.ground
			counted.y += 1.0
	if counted.x <= 0.0 or counted.y <= 0.0:
		return 0.0
	return (left / counted.x).distance_to(right / counted.y)


## The height one pair of legs is holding its end of the body at: whichever of the
## two is doing worse, since the body cannot ride higher than the shortest reach
## underneath it.
##
## Each leg answers twice and the truth is between them. Held at one length it
## vaults — high with the foot underneath the shoulder, low with the foot thrown
## out fore or aft — and that is what a step does to a body. Levelling perfectly,
## it simply stands at the height the stance asks for and extends as required,
## which is what an animal is doing when it carries a head steady over rough
## ground. Neither alone is a walk.
##
## `wants` is a *clearance* rather than a height — how far this pair of legs likes
## to hold its end of the body above whatever it is standing on — so it is quoted
## against each foot's own surface rather than against the world's floor. On flat
## ground every surface is zero and the two are the same number, which is why
## nothing about this function changed for an animal on a plain. On a ledge they
## are not: a leg standing six pixels up holds the shoulder six pixels higher, and
## a levelling term that had forgotten to say so would cap the body at the height
## it stands at on the floor and quietly pin the animal to the ground it had just
## climbed off.
func _pair_support(pair: int, wants: float) -> float:
	var held: float = INF
	var floor_height: float = INF
	for limb in limbs:
		if limb.pair != pair or _skip(limb) or limb.stepping or not limb.bearing:
			continue
		if limb.carry < SUPPORT_MIN:
			continue
		var vault: float = limb.support_height(limb.working)
		var level: float = minf(limb.surface + limb.toe_rise() + limb.rest_height,
			limb.support_height(_max_reach(limb)))
		held = minf(held, lerpf(vault, level, loco.absorbed))
		floor_height = minf(floor_height, limb.surface)
		wants = minf(wants, limb.rest_height)
	if is_inf(held):
		return wants
	# The sag is measured from the ground under the feet for the same reason the
	# stance is. A body crouching on a ledge crouches toward the ledge.
	return maxf(held, floor_height + wants * SUPPORT_FLOOR)


## The highest one pair of legs could possibly hold its end of the body, with the
## feet where they are now. Pythagoras again, and at the limb's outright limit
## rather than the reach it prefers to stand at: this is not where the body wants
## to be, it is the line it may not be on the wrong side of.
##
## Every limb of the pair answers, including one in the air — see
## Limb.carry_ceiling. Carrying and reaching are different questions and only the
## first is about being planted.
##
## Infinite when nothing is attached — a body with no legs of that pair left is
## not being held up by them, and whatever is deciding its height, it is not this.
func _pair_ceiling(pair: int) -> float:
	var ceiling: float = INF
	for limb in limbs:
		if limb.pair != pair or _skip(limb) or not limb.bearing \
				or limb.carry < SUPPORT_MIN:
			continue
		ceiling = minf(ceiling, limb.carry_ceiling(_max_reach(limb)))
	return ceiling


## How high a foot that is not taking a step is being held.
##
## On the surface it is standing on, which is the answer for the overwhelming
## majority of feet and the only answer this solver used to have. A limb that is
## not standing on anything is hung from its own socket instead — see
## Limb.hang_height — and that covers both bodies with no ground under them and
## forelimbs that never had any business on it. Without it a vestigial arm is
## solved to a floor a whole leg below its shoulder, which is a target it cannot
## reach and is drawn as a spike; and a leaping animal's legs hang at their full
## standing length beneath a body that is in the air.
func _hold(limb: Limb, airborne: bool) -> float:
	if not airborne and limb.bearing:
		return limb.surface + limb.toe_rise()
	return limb.hang_height(TUCK_REACH)


## How far this foot has rolled forward onto its toe.
##
## Where the foot sits in its own fore-and-aft travel, and nothing else: nothing
## ahead of the rest stance, everything at the back of it. So it comes round once
## per stance phase because that is what a stance phase is — the foot arrives
## ahead of the shoulder, the body walks over it, and by the time it leaves the
## animal is up on the toe pushing off it. No clock and no curve; the same
## reading of the same geometry the stride is measured in.
##
## It is the whole of the propulsion left to a limb that does not bend. A
## columnar leg is a pillar by construction — that is what makes it good at
## carrying and useless as a lever — so it has no knee flexion to push out of and
## no sinking to lengthen its stride with. What it has is a foot, and this is the
## foot working. Zero on anything the animal is not standing on, because a push
## needs something to push against, and zero the instant a limb loses the joint
## that would do it: see Limb.toe_rise.
func _read_toe(limb: Limb, a: Spine.Frame) -> void:
	if limb.stepping or not limb.bearing or limb.push <= 0.0:
		limb.toe = 0.0
		return
	var behind: float = limb.rest_fore - limb.local(a, limb.planted - a.pos).y
	limb.toe = clampf(behind / maxf(limb.sweep_limit, 0.001), 0.0, 1.0)


## Limbs this solver has no business touching: the ones that are not there, and
## the ones nothing is holding out.
##
## The second is not a weaker version of walking, which is why it is a skip rather
## than another number to multiply a stride by. A leg whose bone has been ground
## through has no stance to be placed in and no step to take badly; it hangs from
## the socket and goes where the body drags it, and that is `Ragdoll`'s business.
func _skip(limb: Limb) -> bool:
	return limb.severed or limb.carried


## Caches what the anatomy says about one limb, so everything downstream reads a
## single agreed set of numbers rather than re-deriving them.
##
## An unimpaired body — or one with no anatomy attached at all — leaves every
## value at 1.0, which is the guarantee that a healthy creature walks exactly as
## it did before this existed.
func _read_function(limb: Limb, state: BodyState, impaired: bool) -> void:
	if not impaired:
		limb.drive = 1.0
		limb.flex = 1.0
		limb.command = 1.0
		limb.carry = 1.0
		limb.reach = 1.0
		limb.severed = false
		limb.carried = false
		return
	var region: BodyState.Region = state.limb(limb.key)
	if region == null:
		return
	limb.severed = region.severed
	# A limb still on the animal but no longer on its skeleton stops being walked
	# and starts being carried. Nothing below is wrong for it — it is simply that
	# a stride, a plant and a swing are all answers about where to *put* a limb,
	# and there is nothing left to put this one anywhere.
	limb.carried = region.hanging
	limb.command = region.control
	limb.carry = region.load
	# Force across the socket is what pushes the body along, so that is what the
	# stride is priced off — not the limb's average. A shoulder eaten out and a
	# shank eaten out are different injuries and have to walk differently, and
	# these two lines are the whole of why they do.
	limb.drive = minf(region.strength,
		state.actuator(region.index, BodyPlan.JOINT_ROOT))
	limb.flex = state.actuator(region.index, BodyPlan.JOINT_MID)
	# A limb that cannot bear its own weight folds under the body as well as
	# reaching less far, so the two collapse into one envelope scale.
	var fold: float = 1.0 if region.load >= SUPPORT_MIN \
		else lerpf(FOLD_REACH, 1.0, region.load / SUPPORT_MIN)
	limb.reach = lerpf(REACH_FLOOR, 1.0, region.motion_range) * fold


## Whether this limb can pick itself up at all.
##
## Three ways to fail it, and they are different animals: no command reaching the
## limb, not enough of it left to stand the body on while the rest of the beat is
## in the air, and — the one that is not a failure at all — a limb that never had
## the ground under it to push off. Any of them and the leg still exists, is still
## solved and is still carried; it is only never *asked*.
func _can_step(limb: Limb) -> bool:
	return limb.bearing and limb.command >= CONTROL_MIN and limb.carry >= SUPPORT_MIN


## The reach and the fan this limb may currently be placed inside. Both narrow
## with its range of motion, which is what stops a stiffened leg from being
## solved to a stance it could no longer physically adopt.
func _max_reach(limb: Limb) -> float:
	return limb.lock * limb.reach


func _swing_fan(limb: Limb) -> float:
	return limb.swing * lerpf(SWING_FAN_FLOOR, 1.0, limb.reach)


func _start_step(limb: Limb, body: BodyShape, p: CreatureParams, scale: float,
		surface_query: Callable) -> void:
	# How long this limb has taken to come round to itself again. Every lift is a
	# reading, whether the limb won the contest or was pulled onto somebody else's
	# beat, because it is this limb's own cycle either way.
	if limb.last_lift >= 0.0:
		var span: float = _clock - limb.last_lift
		if span > 0.0 and span < CYCLE_MAX:
			limb.cycle = span if limb.cycle <= 0.0 \
				else lerpf(limb.cycle, span, CYCLE_BLEND)
	limb.last_lift = _clock
	limb.step_from = limb.planted
	limb.step_from_surface = limb.surface
	limb.step_index += 1
	limb.step_duration = _step_duration(limb)
	limb.step_to = limb.clamp_to_envelope(
		body.anchors[limb.key], _landing_spot(limb, limb.step_duration))
	limb.step_to_surface = _surface_under(limb, limb.step_to, scale, surface_query)
	limb.step_t = 0.0
	limb.stepping = true


## How high the ground is where this foot is being put down.
##
## The ceiling handed to the query is the one anatomical fact in it, and it is the
## same one `Traversal` makes its first condition of a climb: a foot goes as high
## as the joint that swings it and no higher, so anything whose top is above the
## socket is not a surface this leg can stand on and the query answers with
## whatever is underneath instead. That is the difference between stepping onto a
## ledge and walking into a wall, and it is decided here — per foot, per tick, off
## the height that foot's own shoulder is currently being carried at — rather than
## by anything that knows what the obstacle is.
##
## Zero with no query attached, which is the flat floor this solver was written
## against and the behaviour every line of it still has without one.
func _surface_under(limb: Limb, at: Vector2, scale: float, query: Callable) -> float:
	if not query.is_valid():
		return 0.0
	var foot: float = limb.foot_radius(scale)
	var answer: Variant = query.call(at, foot, limb.socket_height + foot)
	return (answer as Vector2).x if answer is Vector2 else 0.0


## How extended the legs stand this tick: what the animal's locomotion asks for,
## folded toward the tightest a limb may be drawn up by however much crouch is
## being spent.
##
## Settles what one step of this animal is worth, for all four legs at once.
##
## A body is one object. Over one cycle every foot on it returns to the same
## place relative to the shoulder it hangs from, and in between the whole animal
## has moved forward by exactly one stride — so each foot has travelled the same
## ground, and the four legs therefore have one step length between them rather
## than four. What sets it is the leg with the least to spend, because a girdle
## cannot take a longer step than it has room for and the rest of the body cannot
## walk away from it.
##
## Without this the two ends of an animal run at two cadences. It never showed
## while every limb on every creature was solved from one set of numbers; the
## moment a build could carry a straight strut in front and a folded spring
## behind, the girdle with the shorter travel simply stepped more often — three
## strides of the forelimbs to two of the hind — and the footfall pattern, which
## is a statement about *phase*, had no fixed cycle to be a phase of. What came
## out was a creature whose legs drifted continuously through every gait in the
## catalogue, which is not a gait at all.
##
## What is *not* shared is the two per-limb terms applied afterwards. A limb on
## the outside of a turn genuinely covers more ground than one near the centre,
## and a limb with no force left in it genuinely reaches less far — the first is
## the geometry of turning and the second is the whole of a limp. Both are
## differences in what a limb does with the animal's stride rather than
## disagreements about what the stride is.
func _share_stride() -> void:
	var shared: float = INF
	for limb in limbs:
		if _skip(limb) or not limb.bearing:
			continue
		shared = minf(shared, limb.stride)
	if is_inf(shared):
		return
	for limb in limbs:
		limb.stride = maxf(shared, 0.001) * (0.45 + 0.55 * limb.pace) \
			* lerpf(STRIDE_FLOOR, 1.0, limb.drive)


## The square of how far this limb's foot rests from directly beneath its socket,
## with the body's own wave taken out of it.
##
## The same split `Limb.set_stance` makes — as much of the stance radius out to
## the side as the swing plane has not rotated away, and the fore-and-aft bias
## spent out of what is left — asked of the width the animal stands at rather than
## the width the wave has squeezed it to this instant. Squared because the one
## caller wants it that way and a square root taken here would only be taken back.
func _steady_stance(limb: Limb, p: CreatureParams, lean: float) -> float:
	var wide: float = minf(limb.plan_limit,
		loco.stance_limit(limb.plan_limit, 0.0) / maxf(lean, 0.0001))
	var lat: float = wide * lean
	var fore: float = sqrt(maxf(wide * wide - lat * lat, 0.0)) \
		* (p.front_foot_bias if limb.pair == Limb.FRONT else p.rear_foot_bias)
	return lat * lat + fore * fore


## How high one pair of legs holds its end of the body with its feet where they
## rest — which is the height that pair *wants*, and the one the envelope has to
## be sized at.
##
## Not `Posture.clearance` of the same leg, and the difference is the whole of why
## a columnar build used to be solved twenty degrees more bent than it stands. The
## posture answers for a foot out at the full plan reach of the leg; a real rest
## stance is not there. The fore-and-aft bias spends only a fraction of what is
## left after the lateral offset, so the foot ends up well inside its own circle —
## and a foot closer in is a body held *higher*, by Pythagoras, exactly as it is
## everywhere else in this file. Asked for the posture's number instead, the
## levelling term spent every tick pulling the body down below what its own legs
## were holding it at, and the legs bent to meet it.
##
## Closed-form, from the parameters rather than from the solved stance, and that
## matters: the rest stance is narrowed by the room left for the stride, which is
## sized off this, which would be a loop. What it quotes is where the foot would
## rest if nothing narrowed it, which is where it rests on every build the
## narrowing does not bind on and a slight over-estimate of the height on the ones
## it does — a body a shade lower than its envelope was drawn for, which is the
## safe direction.
func _rest_clearance(bone: float, extension: float, p: CreatureParams,
		pair: int) -> float:
	var reach: float = bone * extension
	var stance: float = posture.plan_reach(reach)
	var lat: float = stance * cos(posture.tilt) * p.stance_width
	var fore: float = sqrt(maxf(stance * stance - lat * lat, 0.0)) \
		* (p.front_foot_bias if pair == Limb.FRONT else p.rear_foot_bias)
	var out: float = sqrt(minf(lat * lat + fore * fore, reach * reach))
	return sqrt(maxf(reach * reach - out * out, 0.0))


## Both stops are this girdle's own rather than numbers shared by every animal,
## and that is what makes a crouch and a push-off anatomical alike: a build whose
## joints close right up gets its mouth to the floor and can gather itself to
## spring, and one standing on pillars that barely bend lowers itself by a few
## pixels and has to reach the rest of the way with its neck. Nothing forbids the
## second animal anything — it simply has no travel to spend.
##
## Signed, and the sign is the difference between the two things a limb does about
## its own length. Positive folds toward the joint's fold stop, which is a crouch:
## a shorter leg, a body that comes down with it, and every band, silhouette and
## picture following because all of them are read off the height the feet hold.
## Negative extends toward the lock, which is the same statement upside down — a
## longer leg, and a body that goes up on it. That is a push-off, and it is why
## the take-off of a jump is visible before there is any elevation at all: the
## animal genuinely stands up on its legs first, exactly as it would have to.
func _stance_extension(load: float, pair: int) -> float:
	var joint: Articulation.Joint = loco.joint(pair)
	if load >= 0.0:
		return lerpf(joint.stand, maxf(joint.fold, Limb.REACH_MIN),
			clampf(load, 0.0, 1.0))
	return lerpf(joint.stand, joint.lock, clampf(-load, 0.0, 1.0))


## How high this limb picks its foot up at the top of a step. A real height in
## world pixels, not a screen offset, because it is the height something else has
## to be shorter than to pass underneath — see Locomotion.lift for why it is a
## share of the animal rather than a number.
func _step_clearance(limb: Limb) -> float:
	return loco.lift(limb.socket_height, limb.anatomical_length) * posture.step_height_gain


## How long this limb's swing phase should last.
##
## Three terms, and the middle one is new and is the reason a columnar animal now
## walks on four legs instead of two:
##
##   * the limb's own pendulum swing, shortened at pace. A leg is a weight hanging
##     off a shoulder, so a long one takes longer to come through however strong
##     the animal is — which is the whole of why an elephant's feet move
##     deliberately, and it is not a number anybody chose.
##   * the duty factor, as a deadline. A posture that keeps three feet on the
##     ground is a posture in which a foot may be in the air for a quarter of its
##     cycle and not a moment more. Without this the two front legs of a
##     single-support build used the whole of the airborne slot between them —
##     each of them aloft half the time — and the hind pair, which could never
##     find a gap, was towed along the ground for as long as the creature walked.
##     Nothing was wrong with the hind legs; there was simply never room for them.
##   * a weak limb swings *slower*, which is the second half of a limp. The
##     ceiling rises with it, because a leg that cannot keep up is exactly a leg
##     that should be seen labouring rather than one held to a healthy tempo.
func _step_duration(limb: Limb) -> float:
	var labour: float = lerpf(SWING_SLOWEST, 1.0, limb.drive)
	var base: float = limb.swing_base * (1.0 - 0.55 * limb.pace) * labour
	var budget: float = loco.swing_budget(limb.stride / maxf(limb.socket_speed, 1.0),
		float(footfall.lift_limit) / float(maxi(loco.bearing_limbs, 1)))
	return clampf(minf(base, budget), Locomotion.SWING_FLOOR, limb.swing_base * labour)


## How long one limb's whole step cycle currently is, averaged over the legs that
## are walking. A measurement rather than a setting: the stride each foot has and
## how fast its own socket is travelling through it.
func _body_cycle() -> float:
	var total: float = 0.0
	var count: int = 0
	for limb in limbs:
		if _skip(limb) or not limb.bearing:
			continue
		total += limb.stride / maxf(limb.socket_speed, 1.0)
		count += 1
	return total / maxf(float(count), 1.0)


## Where a foot should touch down if it lifts now and lands in `flight` seconds.
##
## Aiming at the present ideal is what made the hind feet look unplanted: by the
## time the foot lands the body has moved on, so it arrives already behind and
## is dragged the whole of its stance phase. Leading by the socket's own
## velocity puts the foot down where the ideal will actually be. The prediction
## is capped because `ideal` already contains the authored foot lead: an
## uncapped flight prediction plus another fixed lead makes a quick turn or
## reversal send the foot on a needlessly wide correction.
func _landing_spot(limb: Limb, flight: float) -> Vector2:
	var prediction: Vector2 = (limb.socket_vel * flight).limit_length(
		limb.stride * LANDING_PREDICTION_STRIDES)
	return limb.ideal + prediction + _scatter(limb)


## How far a poorly controlled foot misses by.
##
## Nerve damage is not only weakness — a limb the animal has partly lost track of
## is put down *near* where it was aimed. The offset is fixed for the whole of one
## step rather than resampled per frame, because a foot hunting about in mid-air
## reads as jitter while a foot planted in the wrong place reads as a stumble.
##
## Derived from the step count rather than drawn from a generator, so a given body
## placing a given step misses the same way every run — the same determinism the
## carcass's resting pose is built on.
func _scatter(limb: Limb) -> Vector2:
	if limb.command >= 0.999:
		return Vector2.ZERO
	var miss: float = (1.0 - limb.command) * PLACEMENT_SCATTER * limb.stride
	var phase: float = float(hash(Vector2i(limb.step_index, limb.group)) % 62831) * 0.0001
	return Vector2.RIGHT.rotated(phase) * miss


## Poses one limb, and then routes it around anything in the way.
##
## The target is where the foot is standing *on the ground plane* — its height is
## already on the limb — and the whole chain is built up from there, so a foot the
## solver was given stays exactly where it was given. Contact avoidance moves that
## target and asks again; it never touches a bone.
func _solve_limb(limb: Limb, body: BodyShape, p: CreatureParams,
		scale: float, collision_query: Callable) -> void:
	var a: Spine.Frame = body.anchors[limb.key]
	# The joint's own fan, not the stride: routing around an obstacle is a limb
	# being pushed somewhere, and where it may be pushed is an anatomical question.
	# Held to the walking corridor the leg has nowhere to go round a body parked
	# against its shank, and stands in it.
	var fan: float = _swing_fan(limb)
	var target: Vector2 = limb.clamp_to_envelope(a, limb.ground, fan)
	limb.solve_stance(a, target, p.fabrik_iterations)

	if not collision_query.is_valid():
		return

	# Contacts are tested where the limb *is*, on the ground plane, and each part
	# carries the heights it occupies alongside. Both halves are needed and the
	# first is not a detail: "underneath" is a statement about two things sharing a
	# position and differing in height, so it can only be asked in the one frame
	# where a foot and the animal walking under it have the same coordinates. Ask
	# it in the picture instead and a raised foot has simply moved somewhere else,
	# which is not the same claim at all.
	#
	# So a leg only routes around what it would actually walk into: a planted foot
	# is an obstacle at ankle height, and the same foot picked up is a doorway.
	var upper_radius: float = limb.girth(scale) * 0.5
	var lower_radius: float = upper_radius * 0.72
	var foot_radius: float = limb.foot_radius(scale)
	var contact_applied: bool = false
	for _iteration in LIMB_CONTACT_ITERATIONS:
		var upper_push: Vector2 = collision_query.call(
			limb.key, 0, limb.plan[0], limb.plan[1], upper_radius, limb.segment_band(0, scale))
		var lower_push: Vector2 = collision_query.call(
			limb.key, 1, limb.plan[1], limb.plan[2], lower_radius, limb.segment_band(1, scale))
		var foot_push: Vector2 = collision_query.call(
			limb.key, 2, limb.plan[2], limb.plan[2], foot_radius, limb.segment_band(2, scale))

		# Moving the target bends both bones through the ordinary IK solve.
		# The upper bone has only about half the foot's leverage, so amplify
		# its correction; lower-bone and foot contacts track more directly.
		var correction: Vector2 = foot_push
		if lower_push.length_squared() * 1.3 * 1.3 > correction.length_squared():
			correction = lower_push * 1.3
		if upper_push.length_squared() * 2.0 * 2.0 > correction.length_squared():
			correction = upper_push * 2.0
		if correction.length_squared() <= LIMB_CONTACT_SLOP * LIMB_CONTACT_SLOP:
			break

		var max_correction: float = maxf(limb.total_length * 0.22, 4.0 * scale)
		var next_target: Vector2 = limb.clamp_to_envelope(
			a, target + correction.limit_length(max_correction), fan)
		if next_target.distance_squared_to(target) <= 0.000001:
			# The direct route can point outside the limb's stance corridor. In
			# that case walk along the obstacle instead, keeping the choice of side
			# stable by preferring the limb's anatomical outward direction.
			var route: Vector2 = Vector2(-correction.y, correction.x).normalized()
			if route.dot(limb.rest_dir) < 0.0:
				route = -route
			next_target = limb.clamp_to_envelope(a, target + route * max_correction, fan)
			if next_target.distance_squared_to(target) <= 0.000001:
				next_target = limb.clamp_to_envelope(a, target - route * max_correction, fan)
			if next_target.distance_squared_to(target) <= 0.000001:
				break
		target = next_target
		contact_applied = true
		limb.solve_stance(a, target, p.fabrik_iterations)

	# Keep the gait's world-space foot state aligned with the collision-safe
	# solve. A planted foot slides around the obstacle; an airborne one keeps
	# its lift and is re-routed again as its procedural arc advances.
	if contact_applied:
		limb.ground = target
		limb.visual = target + limb.rise()
		if not limb.stepping:
			limb.planted = target


## True when the creature has at least one foot in the air.
func any_stepping() -> bool:
	for limb in limbs:
		if limb.stepping:
			return true
	return false
