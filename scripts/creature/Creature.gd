## Owns the creature's motion state and drives the four subsystems in order.
##
## Per physics tick:
##   1. integrate the head's position/heading from the movement command;
##   2. correct that position against other bodies — pushed out of the ones it is
##      inside, pulled back onto anything its jaws have hold of;
##   3. drag the spine after it (constraint solve);
##   4. rebuild the body shape from the solved spine;
##   5. run the gait, which reads the new body and solves the limb IK.
##
## The dependency chain is strictly one-way — input -> head -> contacts -> spine
## -> body -> limbs — which is why the whole thing is stable without any global
## solver. All state is in world space and this node stays at the origin, so the
## view can draw the raw coordinates.
##
## Step 2 is the only place two creatures affect each other, and both halves of
## it work the same way: each creature measures the error itself, corrects its
## own share of it, and never writes into the other's state. The share is its
## mass — see `_contact_share` — which is the whole of what weight does here.
class_name Creature
extends Node2D

signal ate_food(total: int)
## Emitted at the apex of the lunge, not on the click — see _physics_process.
## Carries the whole footprint of the closing: where every tooth landed and how
## deep it drove. The world resolves damage from that and nothing else.
signal bite_started(mark: BiteMark)
signal tissue_damaged(integrity: float)
## Chunks of skin and muscle a bite tore off, for the world to scatter.
signal tissue_shed(chunks: Array, origin: Vector2)
## Parts of this animal that are no longer joined to it — `TissueGrid.Piece`, one
## per surviving piece. Not meat: these arrive intact, and the world has to keep
## them that way until something eats them.
signal part_severed(pieces: Array)
## A piece of meat that has finished going down these jaws. The world owns it, so
## the world is what takes it out and says what it was worth.
signal swallowed(part: CarrionField.Part)
## Physical foot contact. The creature reports motion; the habitat decides how
## far that contact carries as sound.
signal foot_landed(at: Vector2, intensity: float)

@export var params: CreatureParams
## Simulation-space spawn because this node intentionally remains at the world
## origin while its procedural points are stored directly in world space.
@export var spawn_position: Vector2 = Vector2.ZERO
@export var spawn_heading: float = 0.0

## Whether anything is driving this body. Until there is an AI, everything placed
## in the habitat is a carcass — see the dead tick below.
##
## It is a property of the body rather than of who happens to be steering it, so
## the day something does drive one the only change here is that this becomes
## true; nothing else in the class is conditional on the player specifically.
@export var alive: bool = true
## Deterministic shape of a carcass's slump. Left at 0 one is derived from where
## the body was placed, so a given body lies the same way every run while two of
## them never lie identically.
@export var rest_seed: int = 0

var spine: Spine
var body: BodyShape
var gait: Gait
## How this animal holds its legs under it. An anatomical trait, rebuilt with the
## rest of the structure when the parameter changes — see Posture.
var posture: Posture = Posture.new()
## What each girdle does with the limbs hanging off it: how its bones divide, what
## angle its joint stands at, how far it locks out and how far it folds. Rebuilt
## beside the posture and for the same reason — it is skeleton rather than
## setting. See Articulation.
var articulation: Articulation = Articulation.new()
## What in this body stores work and gives it back — the elastic structures the
## joints above cross. Rebuilt beside the articulation and never apart from it: a
## spring is wound along a bone and released through a joint, so it cannot be
## described until both of those are. See Spring.
var spring: Spring = Spring.new()
## Where the body is in the one direction the plane does not have. Zero on
## anything standing on the ground, which is nearly everything nearly always.
var elevation: Elevation = Elevation.new()
## Whether this body can throw itself off the ground, and how far — read off the
## mass, the muscle, the joint travel and the store, once per tick and ahead of
## everything that uses it. Not a setting: there is no leap parameter any more,
## and a creature that cannot jump is one whose arithmetic came out small. See
## Leap.
var leap: Leap = Leap.new()
## And one jump in progress: how much of the store is wound, and what each
## girdle's joints are being asked to do about it. See Jump, which owns the order
## the phases come in and owns nothing else — every pose it produces is the same
## joint angle the crouch and the stance are already read off.
var jump: Jump = Jump.new()
## What heights this body occupies and what heights its jaws reach, read off the
## solved pose each tick beside the physique. Not settings — see Stature.
var stature: Stature = Stature.new()
## Whether the legs under this body are actually holding it up — where the weight
## is against where the feet are, and whether there is enough leg under it to
## matter. Read off the solved pose each tick, and the only thing in the class that
## can put a conscious animal on the ground. See Balance.
var balance: Balance = Balance.new()
## And what the back does about its own weight where nothing is holding it up:
## the height of the axial line, station by station, behind the last girdle. The
## tail hangs off this and nothing else — there is no tail pose anywhere. See
## Droop.
var droop: Droop = Droop.new()
## Owns the limbs while `alive` is false, exactly where Gait owns them while it is
## true. Null on a living creature.
var ragdoll: Ragdoll = null
var anatomy: AnatomyState = AnatomyState.new()
## What the jaws are armed with. Grown from the species' dentition parameters
## and regrown whenever they change, the same way the spine is rebuilt when the
## segment count does.
var dentition: Dentition = null
## Mass, strength and bite force, read off the solved body and the lattice each
## tick. Not settings — see Physique. Refreshed at the end of the tick with the
## rest of the derived state, so the contact and grip passes read the physique of
## the pose they are correcting, exactly as they already read its bounds.
var physique: Physique = Physique.new()
## Where all that weight actually is, counted off the same cells: the centre of
## gravity in the animal's own frame and posed into the world, and how far inside
## its own feet the line it drops comes down. What `Physique` is to how much
## there is, this is to where it is — see Plumb, which is the ground truth
## everything about balance is now argued from.
var plumb: Plumb = Plumb.new()
## What that body can do about moving itself: how hard it accelerates and turns,
## how far it strides, how long its feet stay down. Read off the physique above
## and the posture, once per tick and ahead of everything that uses it — not
## settings, see Locomotion.
var locomotion: Locomotion = Locomotion.new()
## ...and how long it can keep doing it. The pace this body sustains is its heart
## and its vessels against its own locomotor muscle and its own weight; what is
## left is a store, and spending that store is what a sprint is. Read off the
## physique and the functional state at the end of the tick with the rest of the
## derived description — see Stamina.
var stamina: Stamina = Stamina.new()
## Rest length the spine was last actually solved to — see `segment_rest`. Zero
## until the first tick has run, which is what makes the accessor fall back to the
## parameter for a body that has not moved yet.
var _segment_rest: float = 0.0

# --- motion state -----------------------------------------------------------
var head_pos: Vector2 = Vector2.ZERO
var heading: float = 0.0
var speed: float = 0.0
var ang_vel: float = 0.0
var move_dir: Vector2 = Vector2.RIGHT
## Speed as a 0..1 fraction of top speed. Drives stride, step timing and sway.
var speed_norm: float = 0.0

## Shared feel shaping rather than species traits. A species' weight is in the
## push its own muscle derives and its turn-rate parameter; these only decide
## how controls settle.
##
## Braking harder than driving is not a cheat: a body pulling up props on every
## leg it has where one getting going can only push with the pair underneath it.
## What made the old stop read as weightless was the *rate* it was doubling —
## acceleration was quoted as a raw figure that came to well over a gravity on
## the quicker builds, so twice that was a creature deleting its own momentum
## inside a twentieth of its own length. The rate is in gravities now and capped
## at what a foot can lean on; see Locomotion.PUSH_CEILING.
const BRAKE_MULTIPLIER: float = 2.0
const PIVOT_FADE_START: float = 0.08
const PIVOT_FADE_END: float = 0.45
## How much of a standing turn the legs carry the body through — see the swing
## block in `_integrate_motion`. Deliberately short of the whole: the remainder
## is what the head leads the turn by, and at 1.0 the body would rotate rigidly
## with it and nothing would bend.
const STANDING_TURN_ASSIST: float = 0.6
## Least radius a travelling body carves its turn on, in its own body lengths.
##
## A creature changing direction at speed is describing an arc across the ground,
## and an arc tighter than the animal is long is not a turn — it is a body being
## rotated on the spot while it happens to be moving, which is what reads as
## spinning. Every build in the file was carving between four tenths and eight
## tenths of its own length, on a steering rate that had already been faded for
## speed; the fade was a fraction of a number rather than a statement about the
## ground, so it could not know how tight was too tight.
##
## Just over one, because a real quadruped's tightest sustained turn is about its
## own length and anything less involves it slowing down first — which is exactly
## what this makes it do, since the arc is a bound on the rate at a given speed
## and the speed is the player's to give up.
##
## Divided by the stance's own agility, so it is a bound on this animal rather
## than a single circle every creature in the game carves. Carving is bracing: a
## limb out to the side has ground to push against sideways and a pillar stacked
## under the shoulder has almost none, which is what `agility` already says and
## the only honest reason one build should corner tighter than another. Flat, it
## put a Cat and an Elephant on the same arc measured in their own lengths — which
## is not a wide-turning elephant, it is a scaled one.
const MIN_TURN_ARC: float = 1.15
## How much of its steering and acceleration a body keeps with nothing under its
## feet. Small but not zero — a leaping animal can still twist — and it is the
## whole reason a leap is a commitment rather than a hop with full control.
const AIR_CONTROL: float = 0.14
## How much of it a wing gives back, per unit of lift. A flier steers with its
## wings, so at any real span it is manoeuvring rather than falling.
const WING_CONTROL: float = 0.55

## The cursor articulates the head around the solved neck. This angle is
## deliberately separate from `heading` — the body direction locomotion, gait and
## collision braking all read — and stays separate: the head is posed here and the
## body is never rewritten from it. What the two now have between them is one
## signed demand handed to the ordinary steering, `_head_lead`, so a walking
## animal comes round to where it is looking at the rate its own legs turn it and
## a standing one merely watches.
const HEAD_LOOK_MAX_ANGLE: float = deg_to_rad(82.0)
const HEAD_LOOK_RESPONSE: float = 14.0
const HEAD_LOOK_DEADZONE_SQ: float = 36.0
var head_look_angle: float = 0.0
var head_look_dir: Vector2 = Vector2.RIGHT

## How far off its own heading the head has to be carried before the body asks
## for the whole of its turn rate to follow it — see `_head_lead`.
##
## An animal walking forward goes where it is looking. The head reaches the
## direction first because a neck is quicker than four legs, and the body comes
## round after it; that lag is the entire mechanic and it is why this is a
## proportional band rather than a switch. Inside it the body eases round, past
## it the animal is turning as hard as it can — and because the head keeps
## tracking the cursor throughout, the two converge rather than the head snapping
## back when the heading arrives.
const HEAD_LEAD_BAND: float = deg_to_rad(30.0)

# ------------------------------------------------------------------- aim ----
# What this creature has been pointed at, and what its body is doing about it.
# Written from outside — the habitat resolves a cursor into a target and hands it
# over — because which of the several things under a pointer was meant is a
# question about the world rather than about any one animal in it. What the
# animal does with it is entirely its own business, and is the two lines below.

## The selected target: a place, a height, and the structure of whichever body is
## there. Null when nothing has been pointed at, which is the state every line
## downstream falls back to and behaves exactly as it did before aiming existed.
var aim: Reticle.Pick = null
## Whether the jaws can be got onto it, and what the body has to do to manage it.
## Re-solved every tick, because both halves of it move.
var aim_reach: Reach = null
## How much of its fold the animal is currently spending, 0..1. Eased rather than
## snapped: legs bend at a rate, and a body that arrived at a crouch instantly
## would read as a puppet being scaled.
var crouch: float = 0.0
## How quickly it gets there. Fast enough to feel like reaching for something,
## slow enough that the settle underneath it is not fighting a step function.
const CROUCH_RESPONSE: float = 6.0

## What is left of the animal's top speed while it is moving under close control
## — see `is_stalking`. A share rather than a speed, so a Lizard creeps and an
## Elephant creeps, each at its own pace.
##
## The crouch that goes with it is deliberately *not* a second number. Close
## control asks for the whole of the fold and gets whatever this particular
## skeleton has: a sprawled animal is already on the floor and barely moves, a
## semi-upright one drops most of its clearance, and a column whose knees do not
## close stays standing and merely slows down. Which is the honest answer — an
## elephant does not stalk — and it is the same `Stature.fold` a creature reaching
## for its own feet spends, so nothing here had to decide what is anatomically
## possible.
const STALK_SPEED: float = 0.40

## The world's terrain, found once and kept. Null in a habitat that has none, and
## every query against it is guarded, so a scene with no obstacles behaves as a
## flat plane exactly as it always did.
var _terrain_field: Terrain = null
var _terrain_looked: bool = false
## Which other bodies this creature currently has a foot on. One tick stale — it
## is written while the gait places the feet and read by the contact pass at the
## top of the following tick — and deliberately so, for the same reason the
## physique is: it is a fact about where the animal is standing, not about this
## instant.
var _standing_on: Dictionary = {}

var food_eaten: int = 0
## Uniform scale on the whole creature — body, limbs, stride, reach and bite all
## read off it. Growth has been taken out for now, so it is pinned at 1.0 and
## nothing writes to it; it is left in place as the single value a growth system
## will drive when one lands, rather than as a multiplier to be re-threaded
## through forty call sites later.
var size_scale: float = 1.0

# --- collision --------------------------------------------------------------
## Fraction of a contact each creature resolves on its own when the two weigh the
## same. Both parties run the same pass against each other, so together they
## provide one full correction without either creature writing into the other's
## simulation state. Mass then splits that correction unevenly — see
## `_contact_share` — but the two halves still sum to exactly one.
const CONTACT_SHARE: float = 0.5
## Floor and ceiling on a mass-weighted share. An extreme ratio would otherwise
## leave the heavy party contributing nothing at all to a separation, so a pair
## spawned inside each other could stay interlocked; and the light party would be
## teleported by the whole of it.
const MIN_CONTACT_SHARE: float = 0.08
## Ceiling on how far one tick may translate a complete creature. A deep overlap —
## two creatures spawned inside each other, or a segment count change that
## lengthens a body through its neighbour — then unwinds over a few ticks
## instead of teleporting it. Applied before the mass share, so the lighter body
## of a badly mismatched pair takes at most eleven pixels of it per tick and an
## evenly matched one six. The grip's tether is capped by the same number, for
## the same reason: neither correction may become a jump.
const MAX_CONTACT_PUSH: float = 12.0
const CONTACT_EPSILON: float = 0.0001

## Bounding circle around the whole body, refreshed with the pose. Only used to
## reject creature pairs before the capsule-pair contact walk.
var bounds_center: Vector2 = Vector2.ZERO
var bounds_radius: float = 0.0
## Spine coordinate of the most recent body contact returned by the narrow
## phase. A living body resolves that contact as a rigid correction; a free dead
## spine can accept it where it actually landed and bend around the impact.
var _contact_spine_t: float = 0.0

# --- bite state -------------------------------------------------------------
## The strike is an animation with a hit frame, not an instant event. A click
## starts a wind-up, the head is then thrown forward, and the bite resolves at
## full extension — so what gets bitten is whatever the jaws actually reached,
## and the lunge reads as the cause of the damage rather than as a flourish
## played after it.
const LUNGE_WINDUP: float = 0.07
const LUNGE_STRIKE: float = 0.08
const LUNGE_RECOVER: float = 0.18
const LUNGE_TOTAL: float = LUNGE_WINDUP + LUNGE_STRIKE + LUNGE_RECOVER
## How far the head rocks back during the wind-up, as a fraction of the throw.
const LUNGE_SETBACK: float = -0.22
## How much further ahead of the head than the skull is wide the mouth may
## reach — see `jaw_axes`.
const MAX_GAPE_RATIO: float = 2.6

# --- grip -------------------------------------------------------------------
## Play in the jaws, in pixels. The tether takes up nothing inside this, which is
## what stops the biter's own spine settling under a clamped head from quietly
## towing it into its victim, and what keeps a fresh grip from fighting the
## contact pass that is holding the two bodies apart at the same point.
const GRIP_SLACK: float = 3.0
## Separation speed, in px/s, at which one unit of purchase puts one unit of
## force on the jaws. This is what `jaw_power` is measured against.
##
## A currency rather than a fact, and it has to be re-anchored whenever the thing
## it prices changes scale. What loads a set of jaws is a victim thrashing, and
## thrashing is turning: a body held by the leg heaves against the hold at the
## rate it can swing itself, and that rate is now a third to a quarter of what it
## was — the feet have to walk a standing turn round and there are only so many
## steps a second in them, see Locomotion.walked_turn. Left at 150 the same
## struggle produced well under half the load it used to and no victim in the file
## could tear itself off anything, which is not a stronger bite; it is a currency
## quoted in a speed nothing reaches any more.
const GRIP_LOAD_REFERENCE: float = 65.0
## How quickly measured load follows the instantaneous pull. A grip has to be
## broken by a sustained heave rather than by one coarse tick.
const GRIP_LOAD_RESPONSE: float = 6.0
## What one unit of towed mass costs the hauler, against its own strength.
const HAUL_COST: float = 1.0
## However overmatched, a creature can still shuffle. Zero here would be a
## creature frozen by a grip, which is the static hold this replaced.
const HAUL_FLOOR: float = 0.05
## How much of the jaws' penetration is spent holding on, per unit of strain.
const CHEW_STRAIN_COST: float = 0.75
## Floor under that, so jaws at the edge of losing their grip still do damage.
const CHEW_MIN_DEPTH: float = 0.30
## How far a set of jaws can reach for a new hold, as a multiple of its own
## gape. Derived rather than chosen, because there is only one thing it has to
## be able to do: clear the crater it has just made. A mouthful comes away
## centred on the bind — MOUTHFUL_SPAN of a gape in radius — so the far rim of
## the hole is two of those past where the jaws were holding, and the jaws
## themselves reach a gape beyond wherever they are. Anything less and a set of
## jaws would lose its hold *because* it chewed well.
const GRIP_GAPE: float = 1.0 + 2.0 * MOUTHFUL_SPAN
## Resolution of the search for somewhere new to hold. Only ever runs on the tick
## a mouthful comes away, so it is priced like the bite it follows rather than
## like anything per-frame.
const REGRIP_STATIONS: int = 32
const REGRIP_LATERALS: Array[float] = [0.0, 0.5, -0.5, 0.9, -0.9]

# --- tearing ------------------------------------------------------------------
# The other way a hold ends, and the one the jaws win. Flesh has a tensile
# strength of its own — see `Grip.tissue_strength` — and a pull past its yield
# point draws it out of the body instead of moving the creature. Held long
# enough, it parts, and the mouthful comes away in the jaws.
#
# Both this and the jaws coming off are measured against the same `load`, so
# which of them happens is never chosen anywhere: it is whichever gives out
# first. Jaws weaker than the flesh they are on are pulled off a body that stayed
# in one piece; jaws stronger than it take a piece of it with them. That is the
# whole of why an Elephant strips meat off prey a Cat can only be shaken from,
# and no rule was written for either case.

## Fraction of its strength at which flesh starts to give rather than merely take
## up. Below this a pull is held indefinitely, however long it lasts.
const TEAR_YIELD: float = 0.5
## Seconds of pulling at one full strength over the yield point needed to part
## the fibres. Larger is tougher meat everywhere.
const TEAR_WORK: float = 1.1
## How fast stretched tissue recovers once the pull comes off it, per second. A
## victim that stops struggling before the tear stops being torn.
const TEAR_RELAX: float = 0.45
## How deep the mouthful a tear takes comes out, in the lattice's hit points.
## Enough to clear skin and muscle at the centre of the jaws, so what comes away
## is meat rather than a graze — bone still yields at its own reduced rate and
## stops the tear at the skeleton, which is why a limb can be stripped but a
## ribcage only bared. The margin over the flesh stack is what makes the cell it
## was bound to genuinely empty afterwards rather than left with a sliver, which
## the hold would otherwise go on pulling against at almost no strength at all.
const TEAR_DEPTH: float = (TissueGrid.SKIN_HP + TissueGrid.FAT_HP
	+ TissueGrid.MUSCLE_HP) * 1.15
## How much of the gape a torn-away mouthful measures. What parts is the meat
## the jaws enclosed, so unlike a bite it is one piece the width of the whole
## mouth rather than the pattern of the teeth in it.
const MOUTHFUL_SPAN: float = 0.7

# --- chewing ------------------------------------------------------------------
# --- carrying ------------------------------------------------------------------
## How far along the body a swallowed piece travels before it is inside the
## animal, as a fraction of the whole. A short way: what is being shown is a
## mouthful going down a throat, not something transiting an entire lizard.
const SWALLOW_TRAVEL: float = 0.26
## Most a mouthful going down may add to the width of the body it is passing
## through, as a fraction of that width. Bounded, because a throat is tissue and
## tissue stretches only so far.
const SWALLOW_SWELL: float = 0.55

## How long the jaws stay shut on their bind after the button comes up. A press
## inside this window is the same jaws closing again on the same flesh — a chew —
## rather than a fresh strike. Chewing is therefore a repeated action, as biting
## is, without costing a second control: holding still holds, and working the
## button works the jaws.
const GRIP_REGRASP_WINDOW: float = 0.25

# ------------------------------------------------------------------ dead ----
## Inertia a carcass keeps between ticks. Well under `spine_damping`, which is
## the give of a body holding itself together; this is ground friction under one
## that is not, and its whole job is to bring the body to rest and keep it there.
const DEAD_DAMPING: float = 0.42
## Share of a dead body's contact correction carried by its centre of mass. The
## rest lands at the actual spine station and bends it. A purely local correction
## can be absorbed as shape change, making a corpse fold in place instead of
## yielding to a shove; a purely rigid one is the plank-like response the
## ragdoll path exists to avoid.
const DEAD_CONTACT_TRANSLATION: float = 0.55
## How sharply a pull on a carcass falls off along the spine, per station away
## from where the pull acts. See `_drag_at`.
const DRAG_FALLOFF: float = 0.55

var bite_cooldown_remaining: float = 0.0
var bite_connected: bool = false
## True from a world-space left-button press until its matching release. A
## connected strike that reaches its hit frame during that interval clamps at
## full extension and takes hold of what it bit; holding a miss never creates a
## latch.
var bite_held: bool = false
var bite_latched: bool = false
## The jaws' hold on another creature, or null. Owned and written only here; the
## victim finds it by looking, so neither party touches the other's state.
var grip: Grip = null
## The grip currently holding *this* creature, refreshed once at the top of the
## tick so the three consumers below do not each walk the creature group.
var _held_by: Grip = null
## Set when a grip ends by itself — torn off, or the flesh under it eaten away.
## Cleared on button release, so jaws that lost their hold cannot silently take
## it again while the button is still down.
var _grip_lockout: bool = false
## Seconds the jaws will stay shut on their bind with the button already up. Non
## zero only between a release and the moment the hold actually ends, which is
## the window a chew is taken in.
var _regrasp_remaining: float = 0.0
## The meat in these jaws, or null. The other thing a set of jaws can be shut on,
## and kept apart from `grip` because holding a piece of meat is possession while
## holding an animal is an argument — see Mouthful.
var mouthful: Mouthful = null
## Seconds until jaws that are already holding something will close again.
var _chew_cooldown: float = 0.0
## A chew taken this tick, queued for the solved pose exactly as a strike is.
var _chew_requested: bool = false
## Seconds into the current strike, or -1 while not striking.
var bite_time: float = -1.0
## How far ahead of its resting position the lunge is currently holding the
## head, in world pixels. Applied to the spine, never to `head_pos`.
var lunge_offset: float = 0.0
var _bite_requested: bool = false
var _impact_done: bool = false

## Set by whoever is driving this creature, before the physics tick.
var command: MovementInput.Command = MovementInput.Command.new()

## Reused buffer for the spine's per-joint tone, so a damaged creature allocates
## nothing per tick and a healthy one never fills it at all.
var _tone: PackedFloat32Array = PackedFloat32Array()
## ...and for the cross-sections the spine reads its stiffness off. Filled once
## per rebuild rather than per tick, because how thick this animal is at each
## station is structure and not pose.
var _sections: PackedFloat32Array = PackedFloat32Array()


func _ready() -> void:
	if params == null:
		params = CreatureParams.new()
	head_pos = spawn_position
	heading = spawn_heading
	move_dir = Vector2.RIGHT.rotated(heading)
	head_look_angle = heading
	head_look_dir = move_dir
	add_to_group("creatures")
	rebuild()


## Rebuilds the structures that depend on segment count. Cheap enough to call
## from a slider callback.
func rebuild() -> void:
	# One generator across both halves of a carcass, so the slump of its spine and
	# the sprawl of its limbs are different draws describing one body rather than
	# the same few numbers used twice.
	var rng: RandomNumberGenerator = null if alive else _rest_rng()
	posture = Posture.new(params.posture)
	articulation = Articulation.new()
	articulation.configure(posture, params)
	# And what crosses those joints elastically. Structural in the same sense the
	# joints are — it is tissue rather than a setting — so it is laid down here
	# with the rest of the skeleton rather than refreshed per tick.
	spring = Spring.new()
	spring.configure(articulation, params, size_scale)
	# Where the girdles are is where the limbs hang from, and the skeleton has to
	# be told: a pectoral bar bolted across the third torso column is no use to a
	# forelimb whose socket has been moved to the sixth. Cheap and idempotent —
	# it does nothing at all unless the columns have actually changed.
	anatomy.set_girdles(params.front_limb_t, params.rear_limb_t)
	spine = Spine.new()
	var seg_len: float = params.segment_length * size_scale
	# How thick the animal is at each station, before the chain is laid out —
	# because how far a joint bends is decided by it, and a carcass's slump is
	# drawn against those limits. It is the same profile the silhouette is built
	# from, so the back a bite finds and the back the solver holds are one body:
	# see BodyShape.section_profile.
	_sections.resize(params.segment_count)
	BodyShape.section_profile(params, size_scale, _sections)
	spine.set_sections(_sections)
	if alive:
		spine.rebuild(params.segment_count, seg_len, head_pos, heading)
	else:
		spine.rebuild_slumped(params.segment_count, seg_len, head_pos, heading,
			deg_to_rad(params.max_bend_deg), rng)
	body = BodyShape.new()
	gait = Gait.new()
	gait.setup()
	gait.posture = posture
	# Every limb is told what its own girdle does before anything poses it. The
	# gait refreshes this each tick for a living body; a carcass is never walked,
	# and its legs still have to know how far they bend.
	for limb in gait.limbs:
		limb.read_joint(articulation.of(limb.pair))
	body.build(spine, params, size_scale, posture)
	# How much fat this species carries is part of what it is built out of, so it
	# is laid down here with the rest of the structure rather than per tick.
	anatomy.set_fat_reserve(params.fat_reserve)
	# Before the limbs, because how far the ground sits below the torso is what
	# the gait draws the legs down to — and on the very first tick there is no
	# previous stature to read it from. And before *that*, what this body can do
	# about walking: the stance the legs are solved to, and so the height the whole
	# picture is registered to, is one of its answers.
	_update_physique()
	# And before *that* again, where the weight the legs are about to be placed
	# under actually is. The stance is constrained by it — see Plumb, and see
	# Locomotion, which is what spends the constraint — so the census has to have
	# been counted before anything decides where a foot goes. Nothing is posed
	# here: the body has not been solved yet, and what the constraint reads is the
	# build's own centre, which does not need it to have been. Not invalidated
	# first, and deliberately: a rebuild that did not change the animal did not
	# change where its weight is either, and the census knows whether it did.
	plumb.measure(anatomy.tissue.lattice, anatomy.tissue)
	locomotion.update(posture, physique, params, size_scale, articulation, plumb)
	gait.loco = locomotion
	# ...and what all of that comes to about leaving the ground. After the
	# locomotion because it is built on it, and before anything that reads it:
	# the gait asks whether a girdle can throw the animal, the jump asks how far,
	# and the creation menu asks both.
	leap.update(posture, locomotion, physique, spring, params, size_scale,
		stature.stand_height())
	gait.leap = leap
	_update_stature()
	if alive:
		ragdoll = null
		gait.update(0.0, body, move_dir, 0.0, params, size_scale, Callable(), null,
			stature.reference, elevation.is_airborne())
	else:
		ragdoll = Ragdoll.new()
		ragdoll.settle(body, gait.limbs, params, size_scale, rng)
	# Existing damage is kept — it lives in body space precisely so a structural
	# rebuild cannot wash it off — but its world geometry is now stale.
	anatomy.update(self)
	_update_physique()
	_update_plumb()
	_update_stature()
	_update_bounds()


## Re-counts what the body is made of, and tells the limbs what they carry.
##
## One call, because the two halves are one fact: the physique's census says what
## mass each bearing limb is built to hold up, and the limb's thickness — which
## the renderer, the lattice and the hit test all read — is asked of exactly that
## load. Written back here rather than read live so a bare limb (a test's, a
## piece on the ground) keeps the honest default of being sized to its length.
func _update_physique() -> void:
	physique.update(body, spine, anatomy.tissue, params, anatomy.state,
		posture, size_scale)
	if gait == null:
		return
	for limb in gait.limbs:
		limb.load = physique.limb_load.x if limb.pair == Limb.FRONT \
			else physique.limb_load.y


## Re-reads where all that weight is, and whether it is over the feet.
##
## After the physique, because the census it counts through is the one the
## physique has just made sure of, and after the anatomy, because the columns it
## poses through are the ones the anatomy has just solved into the world. Before
## the balance, which is its first consumer.
##
## The measurement is skipped on any tick where neither the build nor the damage
## has changed, which is nearly all of them; what runs every tick is the posing,
## and that is seventy-odd weighted points. See Plumb.
func _update_plumb() -> void:
	plumb.measure(anatomy.tissue.lattice, anatomy.tissue)
	var legs: Array[Limb] = gait.limbs if gait != null else ([] as Array[Limb])
	plumb.pose(anatomy.tissue, legs)
	if gait == null:
		return
	# A tail the animal is genuinely standing on is a fifth contact, and it is
	# the reason a pentapedal crawl is a stance at all rather than a slow topple.
	# The tip, because that is the end that reaches the floor — and only while
	# the walk is actually leaning on it, which `crawl` is already the
	# measurement of.
	var prop: Vector2 = Vector2.INF
	if gait.footfall.crawl > 0.5 and body != null and spine != null \
			and body.last_index < spine.size():
		prop = spine.points[body.last_index]
	plumb.stand(gait.limbs, size_scale, prop)


## Re-reads how much of all that the animal can keep up.
##
## Last of the descriptions, because it is a ratio between two of the others: what
## the physique has just counted as locomotor muscle and weight, against what the
## anatomy has just read as circulation.
##
## How hard the body is working is what it is travelling at over what it could
## travel at flat out — see `flat_out`. Measured rather than commanded, so a
## creature holding sprint against a rock is standing still and standing still is
## not work; and the haul is the same load the walk itself was already narrowed by.
func _update_stamina(delta: float) -> void:
	stamina.update(physique, anatomy.state, params,
		absf(speed) / flat_out(), _haul_factor(), delta)


## Re-reads what heights this body occupies. Runs beside `physique` and for the
## same reason: both are descriptions of the pose that has just been solved, and
## both would be a tick stale anywhere else.
func _update_stature() -> void:
	# How high the feet have the body, rather than how high the stance would like
	# it: the gait has just measured it off four planted feet, and a body is only
	# ever as tall as the legs under it can hold it. Before the gait has run once
	# there is nothing to read, and the posture answers instead.
	# The two girdles rather than one number for the animal: they are held up by
	# different bones and a body's underside has to be below both of them.
	var held := Vector2(-1.0, -1.0)
	if gait != null and gait.measured:
		held = Vector2(gait.shoulder_height, gait.hip_height)
	stature.update(posture, body, params, size_scale, body_length(),
		elevation.height, gape_radius(), alive, held, locomotion)
	# ...and then what the back does past the last thing holding it up. After the
	# stature because it hangs from the height the stature just measured, and before
	# the lattice because the lattice stamps these heights onto the cells behind the
	# hips. See Droop, which is the only thing in the simulation that reads a height
	# off weight rather than off a support.
	droop.update(body, spine, params, anatomy.state,
		stature.reference + stature.elevation,
		_surface_under_foot(spine.points[0], 0.0).x,
		speed_norm, alive)


## The generator a carcass's resting shape is drawn from.
##
## Seeded off where the body actually is rather than off the clock, so it lies
## the same way every run — a body that rearranged itself on reload would not read
## as something that had come to rest at all — while two bodies lying anywhere
## apart lie differently without anyone having to author either pose.
##
## Where it *is*, not `spawn_position`, and the difference is not academic: the
## authored placement is a property of the scene file that `reset` never touches,
## so a body moved anywhere at runtime would go on wearing the pose it was built
## with at its old address.
func _rest_rng() -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = rest_seed if rest_seed != 0 \
		else hash(Vector3(head_pos.x, head_pos.y, heading))
	return rng


func reset(at: Vector2 = Vector2.ZERO, facing: float = 0.0) -> void:
	head_pos = at
	heading = facing
	speed = 0.0
	ang_vel = 0.0
	move_dir = Vector2.RIGHT.rotated(heading)
	head_look_angle = heading
	head_look_dir = move_dir
	food_eaten = 0
	command = MovementInput.Command.new()
	aim = null
	aim_reach = null
	crouch = 0.0
	_standing_on = {}
	elevation.reset()
	jump.reset()
	# A body put down somewhere is standing there, not part way through falling over
	# at wherever it used to be. The clock especially: carrying a stumble across a
	# reset would drop a creature that had just been placed.
	balance.reset()
	# ...and the same sentence about the weight. A body placed somewhere has its
	# centre of gravity where it now is rather than out past the feet it used to
	# have, and the census it is counted off is about to be put back whole.
	plumb.reset()
	anatomy.reset()
	# A body put back is a body that has got its breath back. Beside the anatomy
	# because it is read off the anatomy: leaving a spent store on a creature whose
	# tissue has just been restored is the same disagreement `AnatomyState.reset`
	# exists to prevent.
	stamina.reset()
	bite_cooldown_remaining = 0.0
	bite_connected = false
	bite_held = false
	bite_latched = false
	bite_time = -1.0
	lunge_offset = 0.0
	_bite_requested = false
	_impact_done = false
	_grip_lockout = false
	_regrasp_remaining = 0.0
	_chew_cooldown = 0.0
	_chew_requested = false
	grip = null
	_held_by = null
	_drop_mouthful()
	# Reset is an authority from outside the simulation, not a move inside it, so
	# it is the one place a creature reaches into another's state: a body teleported
	# back to its spawn is no longer the body anybody had hold of, and leaving the
	# tether attached would yank the biter across the world after it.
	if is_inside_tree():
		for node in get_tree().get_nodes_in_group("creatures"):
			var other := node as Creature
			if other != null and other != self and other.grip != null and other.grip.victim == self:
				other.grip = null
				other.bite_latched = false
				other._regrasp_remaining = 0.0
	rebuild()


func _physics_process(delta: float) -> void:
	# Segment count is the only structural parameter; everything else is read live
	# each tick, so tuning sliders take effect immediately. Checked before the
	# branch because it is the one thing both kinds of body need.
	if spine == null or spine.size() != params.segment_count:
		rebuild()
	# Teeth are structural in exactly the way the spine's segment count is, so
	# they are regrown on the same terms: only when the parameters they are a
	# function of have actually changed, and immediately when they have.
	if dentition == null or dentition.signature != Dentition.signature_of(params):
		dentition = Dentition.grow(params)
	# Fat is laid down, not adjusted: re-laying it re-lays the tissue it is part
	# of, exactly as changing the segment count rebuilds the spine. It belongs to
	# the same class of structural parameter and is checked on the same terms — and
	# like that one, the call is free when nothing has changed.
	anatomy.set_fat_reserve(params.fat_reserve)
	if not alive:
		_dead_process(delta)
		return

	# First, because everything below is downstream of it: what this body weighs
	# and what it can pull decide how hard it gets going, how sharply it comes
	# round and how its legs are placed under it. Read off the previous tick's
	# physique, and that lag is deliberate — mass and muscle are properties of a
	# body being eaten over seconds, not of this frame, and the alternative is
	# solving the whole tick before knowing how fast it was allowed to move.
	# Where the weight is comes in on the same terms and for the same reason: the
	# stance the legs are about to be solved to is constrained by it, and the
	# constraint is a statement about the build rather than about this frame.
	locomotion.update(posture, physique, params, size_scale, articulation, plumb)
	gait.loco = locomotion
	# ...and what all of that comes to about leaving the ground. After the
	# locomotion because it is built on it, and before anything that reads it:
	# the gait asks whether a girdle can throw the animal, the jump asks how far,
	# and the creation menu asks both.
	leap.update(posture, locomotion, physique, spring, params, size_scale,
		stature.stand_height())
	gait.leap = leap

	bite_cooldown_remaining = maxf(bite_cooldown_remaining - delta, 0.0)
	_chew_cooldown = maxf(_chew_cooldown - delta, 0.0)
	# Jaws let go by running out of the window they were given, not by the button
	# coming up — see GRIP_REGRASP_WINDOW. Held down, the window is never running.
	if _regrasp_remaining > 0.0 and not bite_held:
		_regrasp_remaining = maxf(_regrasp_remaining - delta, 0.0)
		if _regrasp_remaining <= 0.0:
			_release_grip()

	_held_by = _find_grip_on_self()

	if _bite_requested:
		_bite_requested = false
		bite_time = 0.0
		bite_connected = false
		bite_latched = false
		_impact_done = false
		bite_cooldown_remaining = params.bite_cooldown
	_advance_lunge(delta)

	_advance_elevation(delta)
	_integrate_motion(delta)
	# Between "where input put the head" and "where the body follows it to", so
	# the silhouette, the limbs and the tissue lattice are all built from the
	# corrected pose within this same tick rather than a tick behind it.
	_resolve_contacts()
	# Immediately after, because the two are the same kind of correction pointing
	# opposite ways: contacts push bodies out of each other, a grip pulls jaws back
	# onto flesh. Running them in one phase lets a pair that is both held and
	# overlapping settle within a tick instead of alternating.
	_resolve_grip()

	# The body is solved from `head_pos` alone, which stays the creature's honest
	# position: the strike must not accumulate into the motion integrator or a
	# bite would teleport the creature forward by its own reach.
	# How long the body is *this tick*. Not a constant any more, and the reason is
	# the other way a spine walks: a back folding and extending along its own
	# length. The gait has just measured how far the two ends of the animal have
	# converged — see Gait.gather — and this turns that into the body actually
	# being shorter, so the silhouette gathers and stretches, the tissue lattice
	# goes with it, and the limb sockets are genuinely carried forward and back by
	# the spine rather than by anything pretending to be one.
	#
	# It is nothing at all on an alternating gait, because the measurement it comes
	# from is nothing there: a trot's two hind feet are half a cycle apart and
	# cancel. So a walking animal's body is exactly as long as it always was, and
	# only one working its girdles as pairs bunches.
	_segment_rest = params.segment_length * size_scale \
		* (1.0 - locomotion.bunch(gait.gather, gait.footfall.aerial))
	var seg_len: float = _segment_rest
	# Undulation is a way of walking — a sprawled body lengthening its stride by
	# throwing itself side to side — so it is scaled by how much of the walking
	# this stance does with its spine, and switched off entirely when there is no
	# ground being pushed against at all.
	var wave_gain: float = 0.0 if elevation.is_airborne() else posture.wave_gain
	spine.step(delta, head_pos, params, speed_norm, seg_len, _axial_tone(), wave_gain)
	_update_head_look(delta)
	# Mouse look and the lunge are posed after the body solve, in the one layer
	# that can move point 0 without touching point 1 or anything downstream of it.
	#
	# The throw belongs here rather than in the pin above, and the difference is
	# the whole of what a strike does to the body. Fed to the solver as the head's
	# target, the reach is spent dragging the torso: the constraint pass follows
	# the displaced head, so a bite aimed across the body hauls the spine round
	# after the cursor — and because this line then re-seats the head one segment
	# off the neck, none of the reach survived as reach. The creature turned
	# around instead of lunging. Posed here it is what it says it is: the neck
	# extends and the head arrives out in front of where the body already stood,
	# so the jaws genuinely reach the flesh and the body is left alone to keep
	# walking, standing or turning through the strike.
	spine.pose_head(head_look_dir, seg_len, lunge_offset)
	# Before the body is built, because what a mouthful going down does is distend
	# the body it is going down: it is a term in the width profile and not a lump
	# drawn over the top of one.
	_read_swallow()
	# And beside it for exactly the same reason: flesh with a set of jaws in it is
	# flesh that has been pulled somewhere, so it is a term in the shape rather
	# than a mark laid over one.
	_read_hold()
	body.build(spine, params, size_scale, posture)
	# `move_dir` is the body's facing and intentionally never flips in reverse.
	# The gait only needs a signed fallback for the instant a socket is moving
	# too slowly to measure its own travel direction.
	var gait_dir: Vector2 = -move_dir if speed < -0.01 \
		or (absf(speed) <= 0.01 and command.throttle < 0.0) else move_dir
	# What the body is being asked to reach for, and how far it has to bend to
	# manage it. Before the gait, because the crouch is spent through the legs:
	# it is a shorter stance rather than a pose laid over a standing one, so the
	# feet, the height, the bands and the picture all follow it in the same solve.
	_update_aim(delta)
	gait.update(delta, body, gait_dir, speed_norm, params, size_scale,
		Callable(self, "_limb_contact_push"), anatomy.state,
		stature.reference, elevation.is_airborne(),
		Callable(self, "_surface_under_foot"), _limb_load(),
		jump.drive if jump.active() else 0.0)
	_carry_limp_limbs(delta)
	for contact in gait.landed:
		var footfall: float = (0.07 + minf(0.11, absf(speed) / 1600.0)) * size_scale
		foot_landed.emit(contact, footfall)
	# A whole body coming back down is a footfall too, and a much louder one — so
	# it is announced through the same channel the feet use rather than through a
	# second one. Sized off the speed it arrived at, because that is what makes
	# the noise.
	if elevation.landed:
		foot_landed.emit(spine.points[0],
			clampf(elevation.impact / 900.0, 0.06, 0.34) * size_scale)
	# Before the tissue rather than after it, and the order matters now that the
	# lattice is posed in three dimensions: every cell takes its height from this,
	# so reading a stature solved on the previous tick would put a leaping
	# animal's flesh where the animal no longer is. Everything the stature is read
	# off — the pose, the gait's measured support, the elevation — is already
	# final by this line, so there is nothing to wait for.
	_update_stature()
	anatomy.update(self, delta)
	_release_severed()
	_update_physique()
	# Where that weight is. Between the census and everything that argues about
	# balance, because it is the one reading both halves need: the physique has
	# just settled what the animal is made of, and nothing below this line may
	# guess where it is.
	_update_plumb()
	_update_bounds()
	_update_stamina(delta)
	# Whether any of that is standing up. After the physique because what a leg has
	# to hold is what the body weighs, and after the gait because where the support
	# is is where the feet have actually been put. What it measures is spent through
	# `_limb_load` on the next tick, alongside the crouch and the jump, because a
	# body losing its footing folds its legs and there is only one channel for that.
	balance.update(delta, gait.limbs, body, spine, plumb, anatomy.state, locomotion,
		locomotion.swing_time(maxf(params.leg_length, params.arm_length) * size_scale),
		elevation.is_airborne(), alive)
	# Last of the derived state, because it is a consequence of all of it. Two ways
	# to end up on the floor and they are genuinely different: a body whose brain has
	# gone out or whose circulation has stopped is no longer driving itself, and a
	# body that is perfectly conscious but has nothing left underneath it has run out
	# of legs. Both arrive here, because from this line on there is no difference —
	# nothing is holding it up, and the next tick belongs to the ragdoll.
	if anatomy.state.collapsed or balance.failed:
		collapse()
		return

	# Resolve at full extension, once the pose above is the lunged one, so the
	# bite is tested against where the jaws have genuinely arrived. The clock is
	# clamped to the end of the animation rather than run past it, so this can
	# never be stepped over — one click is always exactly one hit frame, however
	# coarse the tick that carries it.
	if bite_time >= 0.0 and not _impact_done and bite_time >= LUNGE_WINDUP + LUNGE_STRIKE:
		_impact_done = true
		_strike()
	if bite_time >= LUNGE_TOTAL:
		bite_time = -1.0
		lunge_offset = 0.0

	# Last, because everything they do is a consequence of the pose that has just
	# been solved: what the jaws are now pulling against, whether they can still
	# hold it, and whether they have come round to close again. The two are
	# mutually exclusive — a set of jaws is shut on an animal or on a piece of meat,
	# never both — so their order between themselves does not arise.
	_advance_grip(delta)
	_advance_mouthful(delta)


## The moment a creature stops driving itself.
##
## Not a rebuild, and that distinction is the whole of what makes it a collapse
## rather than a body swapped for a corpse. `rebuild` lays a carcass out in the
## slumped pose it would have *come to rest in*, which is right for one placed in
## the habitat and exactly wrong here: this animal is standing somewhere specific,
## in a pose it walked into, with a spine full of momentum and four legs out where
## the gait last put them. All of that is kept. What changes is only that nothing
## is holding it up any more — the head stops being placed, the limbs stop being
## solved to a stride, and the free solver and its friction take the body from
## exactly where the living one left off.
##
## So a creature killed on its feet folds up from its own last pose, at its own
## speed, and comes to rest wherever that carries it. This is the "real collapse"
## the ragdoll has been waiting for.
func collapse() -> void:
	if not alive:
		return
	alive = false
	# The heart is one of the things it has stopped driving, and the anatomy is
	# told in the same breath rather than on the next tick — so a drawer open on
	# this animal reads a stopped heart in the frame it stopped in.
	anatomy.state.arrest()
	_release_grip()
	# Whatever was holding it up has stopped. A body that dies in the air falls,
	# and it falls the whole way this tick rather than over a graceful arc — the
	# arc was the animal flying, and there is no animal now.
	elevation.ground()
	# ...and whatever it had wound is not going anywhere either. A store is held
	# closed by muscle, and a body that has stopped driving itself has stopped
	# holding anything.
	jump.reset()
	# A dead mouth drops what is in it. Nothing else would be true of a mouth.
	_drop_mouthful()
	bite_held = false
	bite_latched = false
	bite_time = -1.0
	lunge_offset = 0.0
	_bite_requested = false
	_chew_requested = false
	_regrasp_remaining = 0.0
	command = MovementInput.Command.new()
	speed = 0.0
	ang_vel = 0.0
	# The limbs keep the joints the gait left them in, and the ragdoll adopts them
	# as its Verlet history rather than settling them somewhere new.
	ragdoll = Ragdoll.new()
	ragdoll.adopt(gait.limbs)


## Lets go of whatever is no longer joined to this animal.
##
## Everything else about severance is already done by the time this runs — the
## lattice worked out which cells still have a run of tissue back to the body, and
## the functional state took the strength, control and load of anything that does
## not to nothing. What is left is the physical half: the piece that came away is
## no longer part of this creature, so its tissue is handed to the world as meat
## and the cells it stood in are emptied. Empty is invisible, unbiteable and
## uncollidable through the machinery that was already there, which is why nothing
## downstream needs a special case for a three-legged animal — or a tailless one.
##
## Which piece it was is not asked and cannot be: this is the same line whether a
## leg, a foot, a tail or a head came off, because the lattice was never told
## which of those a cell belonged to when it decided the cell had come away.
##
## What comes off is a *part*, not a spray of meat, and that distinction is the
## whole of what this now says. Nothing has been done to the tissue in it: every
## cell arrives with the hit points it was standing with, still stacked skin over
## fat over muscle over bone. A leg that has come off is a leg. It stops being one
## the same way a leg on a living animal stops being one, which is by something
## biting it — so the conversion into meat is not performed here, or anywhere, and
## nobody has to remember not to perform it.
func _release_severed() -> void:
	if anatomy.tissue.detached_count <= 0:
		return
	var pieces: Array = []
	anatomy.tissue.take_detached(pieces)
	if not pieces.is_empty():
		part_severed.emit(pieces)


## Moves any limb the animal is no longer holding out.
##
## The gait has already left these alone, because `BodyState` said their skeletons
## no longer reach the body — so something has to move a limb nobody is placing,
## and the solver for a chain with nothing posing it already exists. A living
## animal with a broken leg and a carcass with four of them run the identical code
## on the identical limbs; the only difference is how many of them are in it.
##
## The ragdoll is made on demand rather than carried by every creature, so an
## animal with its bones intact allocates nothing and steps nothing.
func _carry_limp_limbs(delta: float) -> void:
	if not anatomy.state.impaired or gait == null or body == null:
		return
	var any: bool = false
	for limb in gait.limbs:
		if limb.carried and not limb.severed:
			any = true
			break
	if not any:
		return
	if ragdoll == null:
		ragdoll = Ragdoll.new()
	ragdoll.step(delta, body, gait.limbs, params, size_scale,
		Callable(self, "_limb_contact_push"))


## Per-joint tone for the spine solve, or an empty array while the body is whole.
##
## This is where the anatomical skeleton and the animation rig stop being two
## things. Each joint of the chain is held up by the vertebra at that station and
## worked by the muscle around it, so what the solver is given at that joint is
## read from exactly those cells: a sound back solves as it always has, and a back
## broken at one station goes slack *there* and nowhere else.
##
## Empty while nothing is wrong, so an undamaged creature's spine runs the
## identical code path it did before there was an anatomy at all.
func _axial_tone() -> PackedFloat32Array:
	if spine == null or not anatomy.state.impaired:
		_tone.resize(0)
		return _tone
	var n: int = spine.size()
	if _tone.size() != n:
		_tone.resize(n)
	var span: float = float(maxi(n - 1, 1))
	for i in n:
		var region: BodyState.Region = anatomy.state.axial_at(float(i) / span)
		if region == null:
			_tone[i] = 1.0
			continue
		# Bone decides how much the joint can still be *held*; muscle and nerve
		# decide how much is holding it. A vertebra ground through is a hinge with
		# nothing left to limit it, which is what the solver reads this as.
		_tone[i] = clampf(minf(region.stability, region.muscle * region.control),
			0.0, 1.0)
	return _tone


## One tick of a body nobody is driving.
##
## The live chain runs input -> head -> contacts -> spine -> body -> limbs. A
## carcass has no input and no head to place, so the very same chain simply
## starts further down it: what moves this body is other bodies pushing it and
## whatever has hold of it, its spine is a free chain rather than one pinned to a
## driven head, and its limbs hang off the sockets instead of walking. Nothing is
## reordered and nothing is skipped that anything downstream depends on — the
## silhouette, the tissue lattice, the physique and the bounds are all rebuilt
## from this tick's pose exactly as they are for a living creature, which is why
## a carcass can still be collided with, bitten, held and eaten.
##
## Weight needs no code of its own here. `physique` is read off the drawn body and
## the surviving tissue whether or not anything is driving it, and the contact and
## grip passes below already split every correction by mass — so a heavy carcass
## is shouldered aside less and towed more slowly for exactly the reason a heavy
## creature is, through exactly the same line.
func _dead_process(delta: float) -> void:
	if spine == null or body == null or ragdoll == null:
		return
	_held_by = _find_grip_on_self()
	_resolve_contacts()
	_resolve_grip()

	spine.step_free(params, params.segment_length * size_scale, DEAD_DAMPING)
	# The head is no longer placed, so `head_pos` follows the body instead of
	# leading it. Everything that reads it — the first capsule of the contact
	# walk, the broad phase, the jaws — then describes where this body actually
	# is rather than where nothing is steering it to.
	head_pos = spine.points[0]
	head_look_dir = spine.forwards[0]
	head_look_angle = head_look_dir.angle()
	move_dir = head_look_dir

	body.build(spine, params, size_scale, posture)
	ragdoll.step(delta, body, gait.limbs, params, size_scale,
		Callable(self, "_limb_contact_push"))
	# Before the tissue, for the reason the living path gives: the lattice is
	# posed against these heights.
	_update_stature()
	anatomy.update(self, delta)
	_release_severed()
	_update_physique()
	# A carcass has a centre of gravity like anything else, and it moves as the
	# body is eaten. Nothing asks it whether it is over its feet — it is not
	# standing on them — but the drawer, the probes and the scavengers all read
	# where the weight of the thing on the floor actually is.
	_update_plumb()
	_update_bounds()
	# A carcass is described by the same line the living body is. Nothing is being
	# spent, and the store goes anyway: what holds a reserve up is the blood
	# reaching the muscle, and there is none. See Stamina.ceiling.
	_update_stamina(delta)


## Advances the strike clock and resolves it to a forward displacement.
##
## Three phases, shaped so the silhouette itself carries the timing: a soft
## rock backwards to load, a hard ease-out throw (all the distance covered in
## the first half of it, which is what makes it read as a snap rather than a
## lean), and a slow settle back. Nothing is fed back into the motion state, so
## a creature that never bites is bit-for-bit unaffected by any of this.
func _advance_lunge(delta: float) -> void:
	if bite_time < 0.0:
		lunge_offset = 0.0
		return
	# A held bite clamps only after the synchronous world resolver confirmed that
	# the jaws connected. Keeping the clock on the hit frame holds the visible
	# head at full extension without restarting the cooldown; what the jaws then
	# do to the flesh in them is the grip's business, not the animation's.
	if is_bite_latched():
		bite_time = LUNGE_WINDUP + LUNGE_STRIKE
		lunge_offset = params.bite_reach * size_scale
		return
	# The clock never advances past the hit frame in a single step. A tick large
	# enough to span the whole animation would otherwise leave the head already
	# recovered on the frame the bite resolves, and it would strike from resting
	# reach — so "the bite is tested at full extension" would hold only at a
	# well-behaved tick rate. Stopping on the apex makes it unconditional; the
	# strike then releases the clamp and recovery runs on the following tick.
	var limit: float = LUNGE_TOTAL if _impact_done else LUNGE_WINDUP + LUNGE_STRIKE
	bite_time = minf(bite_time + delta, limit)

	# The whole of `bite_reach`, because the mouth is now on the head: what the
	# throw covers is exactly what the creature gains by lunging rather than by
	# standing there, and nothing is added to it after the fact.
	var throw_distance: float = params.bite_reach * size_scale
	var e: float
	if bite_time < LUNGE_WINDUP:
		e = LUNGE_SETBACK * smoothstep(0.0, 1.0, bite_time / LUNGE_WINDUP)
	elif bite_time < LUNGE_WINDUP + LUNGE_STRIKE:
		var x: float = (bite_time - LUNGE_WINDUP) / LUNGE_STRIKE
		e = lerpf(LUNGE_SETBACK, 1.0, 1.0 - (1.0 - x) * (1.0 - x))
	else:
		var x2: float = (bite_time - LUNGE_WINDUP - LUNGE_STRIKE) / LUNGE_RECOVER
		e = 1.0 - smoothstep(0.0, 1.0, x2)
	lunge_offset = e * throw_distance


## True while a strike is playing, at any phase.
func is_lunging() -> bool:
	return bite_time >= 0.0


## How far the jaws are open, 0 shut to 1 at full gape.
##
## Read off the strike rather than tracked: the mouth opens through the wind-up,
## is carried open through the throw, and shuts on the hit frame — so the jaws
## closing and the damage resolving are the same event rather than two things
## timed to agree.
##
## Closing is keyed to the strike having *resolved*, not to the clock reaching
## the apex, and the difference is load-bearing rather than cosmetic. The bite
## resolves at the end of the tick, after contacts; a mouth that shut when the
## clock said so would therefore go solid one phase before it bit, and the lunge
## would shoulder its target out of reach with its own face and then close on
## the gap it had just made.
##
## Jaws already holding something are shut on it, however the animation reads —
## unless what they are holding will not fit in them, and then they are held open
## around it by exactly as much of it as will not go in. That is not an eating
## animation; it is a division, and it is why a mouth with a whole leg in it gapes
## and the same mouth with an ankle in it does not.
func mouth_gape() -> float:
	var propped: float = mouthful.props_open(gape_radius()) if mouthful != null else 0.0
	if bite_time < 0.0 or _impact_done or is_bite_latched():
		return propped
	if bite_time < LUNGE_WINDUP:
		return maxf(propped, smoothstep(0.0, 1.0, bite_time / LUNGE_WINDUP))
	return 1.0


## Smooth, anatomically bounded cursor look. This is still the only thing that
## reads `aim_world`, and it still writes nothing but the head: where the body
## goes is decided one place, in `_integrate_motion`, out of the turn keys and the
## angle this leaves between the head and the heading.
func _update_head_look(delta: float) -> void:
	# The solved neck is the truthful centre of the head's range. It can lag the
	# logical movement heading during a turn, and clamping against `heading`
	# instead would let the first joint exceed the spine's bend invariant.
	var neck_angle: float = spine.forwards[1].angle() if spine != null and spine.size() > 2 else heading
	var max_look: float = minf(HEAD_LOOK_MAX_ANGLE, deg_to_rad(params.max_bend_deg))
	var desired: float = neck_angle
	# A latched head is aimed by what it is holding, not by the cursor. The pose
	# is not frozen — the two bodies move relative to each other while the grip
	# lasts — so the head has to keep tracking the flesh in its jaws or the
	# drawn head would drift off the place the tether is anchored to.
	var aim_active: bool = command.aim_active
	var aim_world: Vector2 = command.aim_world
	# A selected target beats the raw cursor, and the difference is the vertical
	# layer showing up in the one place it is easiest to forget. A cursor is a
	# point in the *picture*; a limb is drawn well below the body it stands under,
	# so pointing the head at the pixel would aim it at the empty floor behind an
	# animal rather than at the leg the player picked out. `aim.at` is where that
	# leg actually stands, which is where a mouth has to go to reach it.
	if aim != null:
		aim_active = true
		aim_world = aim.at
	if is_bite_latched() and grip != null and grip.is_alive():
		aim_active = true
		aim_world = grip.anchor()
	if aim_active:
		var look_origin: Vector2 = head_pos
		if spine != null and spine.size() > 1:
			look_origin = spine.points[1]
		var to_aim: Vector2 = aim_world - look_origin
		if to_aim.length_squared() > HEAD_LOOK_DEADZONE_SQ:
			var local: float = clampf(
				wrapf(to_aim.angle() - neck_angle, -PI, PI),
				-max_look,
				max_look)
			desired = neck_angle + local

	var response: float = 1.0 - exp(-HEAD_LOOK_RESPONSE * delta)
	head_look_angle = lerp_angle(head_look_angle, desired, response)
	# Clamp again after interpolation because the neck may itself have swung
	# sharply this tick while the head angle was easing from its previous pose.
	var relative: float = clampf(
		wrapf(head_look_angle - neck_angle, -PI, PI),
		-max_look,
		max_look)
	head_look_angle = wrapf(neck_angle + relative, -PI, PI)
	head_look_dir = Vector2.RIGHT.rotated(head_look_angle)


## One tick of the vertical axis.
##
## Deliberately upstream of the horizontal one: everything else in this file
## solves the ground plane and then asks this scalar whether the answer applies.
## A leap is *commanded* here and nowhere else — because "throw yourself upward"
## is the one vertical action a terrestrial animal has, and it has to be a push
## against the ground rather than a mode the creature enters.
##
## What it is not any more is instantaneous. `command.climb` held on a body
## standing on something is the animal *preparing*: it shifts its weight onto
## whichever girdle is going to do the pushing, folds those joints, and winds
## whatever elastic tissue it carries — see Jump for the order and Spring for what
## there is to wind. The push happens when the command drops, and how far it goes
## is how much got wound, which is why a tap is a hop and a held key is a leap.
## Nothing accumulates past the top: the store fills in a time this animal's own
## legs set, and after that holding on is a creature standing in a crouch.
##
## The one thing decided here rather than in Jump is what a push is worth on this
## particular tick, and all three terms of it are things the rest of the body has
## already measured: how many of the driving feet were actually on the ground,
## what a grip is hanging off the animal, and how much of its nervous system still
## reaches its legs. So a creature caught mid-stride jumps short, one with an
## Elephant on its tail barely leaves the floor, and one with a dead leg clears
## less — none of which is written anywhere as a rule about jumping.
func _advance_elevation(delta: float) -> void:
	var effort: float = _haul_factor()
	if anatomy.state.impaired:
		effort *= anatomy.state.locomotion
	# ...and how much of itself the animal has left to throw. A fourth term of the
	# same kind as the other three — something the rest of the body has already
	# measured — and the one that is spent rather than damaged: a creature that has
	# just run itself into the ground jumps like one. Exactly 1.0 until it has.
	effort *= stamina.push
	jump.advance(delta, command.climb > 0.0, leap, elevation, locomotion,
		_footing(), command.throttle)
	if jump.took_off:
		# A push-off is the most anaerobic thing this body does, and the only one
		# that happens in an instant rather than over a chase — so it is charged as
		# one. See Stamina.spend.
		stamina.spend(Stamina.LEAP_COST)
		# Where the push is aimed. A jump is a push against the floor and the floor
		# is underneath, so most of it goes up whatever the animal intended; leaning
		# into it trades height for ground, and trades it exactly — the speed is
		# split between the two axes and the apex is what is left of it, so a
		# creature cannot lean its way into a longer jump than it had the legs for.
		var peak: float = jump.launch_peak * effort
		var lean: float = clampf(Leap.DIRECTION_SHARE * jump.launch_lean, 0.0, 0.95)
		elevation.leap(peak * (1.0 - lean * lean), 1.0)
		speed += Gravity.launch_rate(peak) * lean
	elevation.advance(delta, command.climb, params.wing_lift, body_length(), effort)


## How much of each girdle is actually standing on something, 0..1 per pair.
##
## A push needs a floor to push against, and which feet are on one is not a
## decision — it is where the gait last put them. Measured rather than assumed, so
## a creature that lets go of the key with a hind foot halfway through a swing
## pushes with the one that is down and gets a correspondingly shorter jump, and
## one standing squarely gets all of it.
##
## One tick stale, and deliberately: the vertical axis is solved ahead of the
## horizontal one and the gait runs at the end of the tick, so this is where the
## feet were when the animal last stood on them. Sixteen milliseconds, and the same
## lag the physique and the stature are read with.
##
## Limbs that are not there and limbs that are being carried are not counted on
## either side of the fraction: a three-legged animal is judged on the legs it
## has, which is the same thing every other share in this file does with a severed
## limb.
func _footing() -> Vector2:
	var down := Vector2.ZERO
	var counted := Vector2.ZERO
	for limb in gait.limbs:
		if limb.severed or limb.carried or not limb.bearing:
			continue
		var pair: int = 0 if limb.pair == Limb.FRONT else 1
		counted[pair] += 1.0
		if not limb.stepping:
			down[pair] += 1.0
	return Vector2(
		down.x / counted.x if counted.x > 0.0 else 0.0,
		down.y / counted.y if counted.y > 0.0 else 0.0)


## What each girdle's joints are being asked for this tick, taken together.
##
## Two demands land on the same joint and there is only one joint, so they are
## resolved here rather than each being applied to a pose the other has already
## moved. The crouch is a reach — an animal lowering itself toward something it is
## pointed at, or creeping — and it only ever folds; the jump both folds and
## extends, and while it is doing either it is the one driving the legs. So the
## jump has the last word whenever it is asking for anything, and the reach is
## what the body does with its legs the rest of the time.
##
## Which is not a priority table so much as an observation: an animal in the
## middle of a push-off is not also crouching toward the floor, and one that is
## crouching toward the floor has not started a jump. The only place the two meet
## is the instant a stalking creature decides to leap, and there the crouch it is
## already in is the gather it would have made anyway.
func _limb_load() -> Vector2:
	var reach := Vector2(crouch, crouch)
	# ...and whatever the legs are failing to hold. A third demand on the same
	# joint, and the one that is not a decision: the crouch and the jump are things
	# the animal is doing, and this is a thing being done to it. It only ever folds,
	# so it is taken as the deeper of the two rather than replacing anything — a
	# creature crouching on legs that are giving way is doing both, and what its
	# knees end up at is whichever is further down.
	var give: Vector2 = balance.give()
	reach = Vector2(maxf(reach.x, give.x), maxf(reach.y, give.y))
	if not jump.active():
		return reach
	return Vector2(
		jump.load.x if absf(jump.load.x) > reach.x else reach.x,
		jump.load.y if absf(jump.load.y) > reach.y else reach.y)


func _integrate_motion(delta: float) -> void:
	var p: CreatureParams = params
	# A grip is a load on whichever end of it this creature is, and the only thing
	# it changes about locomotion is how much of it survives that load. Turning is
	# deliberately left alone, for the same reason a body contact never touches
	# heading: however overmatched a creature is, thrashing has to remain
	# available — and thrashing is exactly what loads a set of jaws.
	var haul: float = _haul_factor()
	# What the body can still produce, and how well it can still be aimed. Both
	# are read rather than decided: `locomotion` is what the four legs and the back
	# between them add up to, and `coordination` is how much of the nervous system
	# still reaches them. A creature with a dead leg is slower because the leg is
	# dead, not because anything checked for a limp.
	var state: BodyState = anatomy.state
	var drive: float = state.locomotion if state.impaired else 1.0
	var steering: float = state.coordination if state.impaired else 1.0
	# What the legs have to push against. On the ground, all of it. Off it,
	# whatever the animal can do with its own body instead — a good deal with
	# wings out and almost nothing without them, which is why a leap is a
	# committed arc and a glide is still flying. One number for both axes,
	# because it is one fact: nothing is bearing on the ground.
	var purchase: float = 1.0
	if elevation.is_airborne():
		purchase = clampf(AIR_CONTROL + p.wing_lift * WING_CONTROL, AIR_CONTROL, 1.0)

	# The rate itself is torque over rotational inertia, worked out in Locomotion
	# off this animal's weight, its muscle and its own length — so a long heavy
	# build comes round slowly and a short light one snaps about, and neither of
	# them needed a per-species number saying so. The stance is in there too: a
	# semi-upright animal turns flat and a columnar one carves.
	#
	# What is left here is what this *tick* does to it. Turn rate falls off with
	# speed so the arc stays wider than the body; at a standstill the full rate is
	# available, which is what lets the creature pivot on the spot (together with
	# the swing block below); and what is left of that is how much of its nervous
	# system still reaches the legs, and whether they are on anything.
	#
	# ...and then held to what the feet can actually do about it, which is the
	# ceiling that was missing. A standing turn is walked — see
	# Locomotion.walked_turn — so how fast a body comes round is how fast a foot can
	# be put down, over how far out the socket with furthest to travel sits. A
	# travelling one is bounded instead by the arc: past a certain rate the creature
	# is no longer following a curve across the ground, it is pirouetting along one.
	# The two are taken as whichever allows more, because they are alternatives
	# rather than a pair of costs — an animal at a standstill is not carving an arc,
	# and one at speed is not stepping its feet round in a circle.
	var backing: float = _reverse_fraction()
	var turn_rate: float = locomotion.turn_rate \
		* (1.0 - p.turn_speed_falloff * speed_norm)
	var walked: float = _walked_turn_rate(backing)
	if walked > 0.0:
		turn_rate = minf(turn_rate, maxf(walked * (1.0 - speed_norm),
			absf(speed) / maxf(body_length() * MIN_TURN_ARC
				/ maxf(posture.agility, 0.1), 1.0)))
	turn_rate *= steering * purchase
	# Steering backwards is compromised by exactly what makes backing up slow:
	# legs built to push a body forward are pushing it the other way, and they
	# are steering it from the wrong end while they do. So a reversing creature
	# gives up the same fraction of its turn rate that it gives up of its speed —
	# one species trait covering both halves of the same handicap, rather than a
	# second number saying the same thing. Without it a body backs into a circle
	# tighter than it is long, which is the coil this replaced.
	turn_rate *= lerpf(1.0, p.reverse_speed_factor, backing)
	# Angular velocity eases toward the commanded rate rather than snapping, so
	# the body has something to lag behind during a turn. Shedding the old swing —
	# A switched to D, or both keys released — takes the same brake the linear
	# axis uses: eased only at the spin-up rate, the head kept carrying the old
	# turn for a beat after the command reversed.
	# What the two steering inputs add up to. The hand has the last word — the head
	# is asked for only as much of the turn as the player is not already taking by
	# hand — so A and D still mean exactly what they meant, and a creature walking
	# forward with nothing held goes where it is looking.
	var demand: float = clampf(command.turn
		+ _head_lead() * (1.0 - absf(command.turn)), -1.0, 1.0)
	var desired_ang_vel: float = demand * turn_rate
	var turn_response: float = p.turn_responsiveness
	if not is_zero_approx(ang_vel) and signf(desired_ang_vel) != signf(ang_vel):
		turn_response *= BRAKE_MULTIPLIER
	ang_vel = lerpf(ang_vel, desired_ang_vel, 1.0 - exp(-turn_response * delta))

	# Turning swings the head around a station on the body, so the spine and the
	# feet visibly participate rather than the heading simply being rewritten.
	# Which station that is, and why, is `_turn_station`; `swing` is how much of
	# it applies, fading out as travel takes over the arc.
	var turn_delta: float = ang_vel * delta
	var swing: float = maxf(
		1.0 - smoothstep(PIVOT_FADE_START, PIVOT_FADE_END, speed_norm), backing)
	var pivot: Vector2 = _turn_station(backing, swing)
	heading = wrapf(heading + turn_delta, -PI, PI)
	head_pos = pivot + (head_pos - pivot).rotated(turn_delta)
	# How much of that swing the body is carried through rather than towed into.
	# Walking forward it is none of it: the body is following its own track and
	# the head leading is the whole mechanism. Backing up it is all of it — the
	# body is being pushed, not pulled, so it turns as one piece. Turning on the
	# spot it is most of it, because the legs are what walk a standing body
	# around; short of all of it, because what the head leads by is exactly the
	# part it is not carried through, and with none of it left over a chain that
	# can only be towed drags itself sideways instead of turning.
	var carried: float = maxf(backing, STANDING_TURN_ASSIST * swing)
	if carried > 0.0 and spine != null:
		spine.rotate_followers(pivot, turn_delta * carried)

	# Forward speed: accelerate toward the commanded speed, coast down faster
	# than we spin up so releasing the key feels responsive. Reverse is a
	# deliberate, gaited retreat rather than a mirrored walk — legs are built to
	# push a body forward — so it tops out at a fraction of forward speed and
	# sprint does not apply to it.
	var sprint: float = p.sprint_multiplier \
		if command.sprint and command.throttle > 0.0 and not is_stalking() else 1.0
	# What the species asks for, and then what the legs will honour. `move_speed`
	# is a request rather than a promise now, and sprint is a request too: an
	# animal already cycling its legs as fast as they can be thrown has nothing
	# left to spend on going quicker, and the honest thing for it to do is not go
	# quicker. Everything else in the file follows from that one clamp — the feet
	# stop being dragged, the swing stops being clipped, and the body stops
	# arriving somewhere its legs never took it. See Locomotion.leg_speed.
	var asked: float = p.move_speed * sprint * size_scale
	# ...and then what the animal has the breath to hold. The same kind of clamp as
	# the leg ceiling below and it sits beside it for that reason: `move_speed` is
	# what the species asks for, the legs are what it can deliver, and this is the
	# share of flat out it can deliver *for any length of time*. A body with a
	# reserve left asks for whatever it likes; a blown one is held to what its own
	# blood supplies, which is above its walk by construction. See Stamina.hold.
	asked = stamina.hold(asked, flat_out())
	var legs: float = _leg_ceiling()
	var top_speed: float = (minf(asked, legs) if legs > 0.0 else asked) * haul * drive
	if command.throttle < 0.0:
		top_speed *= p.reverse_speed_factor
	# Close control is a ceiling on the speed rather than a brake applied to it:
	# the animal is placing its feet deliberately, not being held back, so it
	# still accelerates and stops with all the force it has — it simply has
	# nowhere fast to get to. Both directions, because creeping backwards away
	# from something is the same care taken in reverse.
	if is_stalking():
		top_speed *= STALK_SPEED
	var desired_speed: float = command.throttle * top_speed
	# Force over mass, and it is the physique's force and the physique's mass — so
	# a heavy animal labours into its speed, a fat one is duller than a lean one of
	# the same build, and a creature with a leg that has stopped answering pushes
	# with three. None of that is written anywhere; it is one division. `drive` is
	# deliberately absent, and only here: `physique.strength` already has it, and
	# applying it twice would make an injured creature slow to accelerate *and*
	# slow to accelerate again.
	#
	# What the push is *not* multiplied by is the feet the gait happens to have
	# down this tick, and the omission is a contract rather than an oversight.
	# The head takes part in the gait solve — every socket is tracked against it,
	# see Limb.track_socket — so the solved feet know where the animal is looking,
	# and a thrust gated on them would let a glance perturb a straight run by a
	# fraction of a pixel, which is precisely the leak ControlsTest exists to
	# refuse. The feet's share of the cycle is priced instead where it is already
	# a law of the body: the duty factor inside `leg_speed`, which is the ceiling
	# the fade below spends the push against.
	var rate: float = locomotion.accel * haul * purchase
	var reversing: bool = not is_zero_approx(speed) and not is_zero_approx(desired_speed) \
		and signf(speed) != signf(desired_speed)
	if reversing:
		# Brake to a readable beat before applying thrust in the other direction.
		# This answers a reversal promptly without erasing the body's weight by
		# jumping directly between equal and opposite top speeds.
		speed = move_toward(speed, 0.0, rate * BRAKE_MULTIPLIER * delta)
	elif absf(desired_speed) < absf(speed):
		# Pulling up. Stronger than getting going and exempt from the fade below,
		# because both are what braking is: muscle resisting stretch holds more
		# than muscle shortening ever delivers, and props dig in harder the faster
		# the body leans onto them.
		speed = move_toward(speed, desired_speed, rate * BRAKE_MULTIPLIER * delta)
	else:
		# Getting going. The push fades as the speed spends the muscle — the
		# force–velocity law, see Locomotion.push_left, and it is what makes the
		# top speed an arrival rather than an assignment: steep off the mark,
		# flattening through the middle, earning the last tenth over seconds.
		# Quoted against `flat_out` — everything this animal will ever ask of
		# itself, the same denominator its exertion is quoted against — so the
		# force fades exactly as the effort rises and the two are one statement.
		# What a spent animal has left of the push is `stamina.push` — exactly
		# 1.0 until the store has actually been run down, and the second half of
		# what being blown means: the target comes down with `hold` above, and
		# the force that was chasing it sags with the same breath.
		rate *= locomotion.push_left(speed, flat_out()) * stamina.push
		speed = move_toward(speed, desired_speed, rate * delta)

	move_dir = Vector2.RIGHT.rotated(heading)
	var displacement: Vector2 = move_dir * (speed * delta)
	head_pos += displacement
	# A head-driven chain cannot be pushed backward through itself. Carry the
	# followers with reverse travel, while leaving heading, head articulation,
	# contacts and the downstream gait in their existing ownership layers.
	if speed < 0.0 and spine != null:
		spine.translate_followers(displacement)
	speed_norm = clampf(absf(speed) / cruise_speed(), 0.0, 1.0)


## How much of the turn the head is asking for, -1..1 alongside the turn keys.
##
## An animal moving forward goes where it is looking, and this is the whole of
## that: the angle the head is carried off the body, priced as a share of the
## turn the body could make. Nothing snaps and nothing is teleported — the demand
## is handed to the same eased angular velocity A and D drive, so the body swings
## round into the heading its head already has and the neck straightens out
## underneath it as the two meet.
##
## Three gates, and each of them is a claim about what the animal is doing:
##
##   * only going forward. A creature backing away from something keeps looking
##     at it, and steering by that would drive it in a circle round the thing it
##     is retreating from; a standing one is watching rather than walking, which
##     is the pose `ControlsTest` pins down.
##   * only while it is actually being pointed. With no cursor the head settles
##     onto the neck, the lead is nothing, and every existing caller — the tests,
##     the ragdoll, whatever drives a creature next — behaves exactly as before.
##   * scaled by the throttle, because it is a property of the walking. Half a
##     throttle is half a commitment and turns half as hard for it.
##
## Read off last tick's head, because the head is posed after the body has moved
## and there is no ordering that avoids it — the neck this angle is measured
## against is itself part of the pose being solved. Sixteen milliseconds of an
## eased turn, and it is the same deliberate one-tick lag the physique is read
## with; the body still arrives on the bearing it was walking toward.
func _head_lead() -> float:
	if not command.aim_active or command.throttle <= 0.0:
		return 0.0
	var off: float = wrapf(head_look_angle - heading, -PI, PI)
	return clampf(off / HEAD_LEAD_BAND, -1.0, 1.0) * clampf(command.throttle, 0.0, 1.0)


## Whether this creature is moving under close control: slowed right down and
## folded as low as its own legs will take it.
##
## Grounded, because both halves of it are things done with legs. In the air the
## same key still means come down — see `MovementInput.Command.stalk` — and a
## body with nothing under its feet has neither a stance to lower nor traction to
## give up.
func is_stalking() -> bool:
	return command.stalk and alive and elevation.is_grounded()


## The fastest these legs will carry this body, before the species has asked for
## anything. Zero — meaning "not known, do not bind" — until the first gait solve
## has placed four feet and measured it, which is what leaves a body with no legs
## yet behaving exactly as it always did. A zero rather than an infinity because
## an infinity has to survive being multiplied by the speed fade below, and
## `INF * 0.0` is a quiet NaN that spreads through the heading into the whole
## body. See Locomotion.leg_speed and Gait.leg_speed.
func _leg_ceiling() -> float:
	return gait.leg_speed if gait != null and gait.leg_speed > 0.0 else 0.0


## The speed this creature walks at flat out without sprinting — the lower of what
## it asks for and what its legs will give.
##
## The denominator every pace in the game is quoted against, and it has to be this
## one rather than the parameter alone: a creature whose legs hold it below its own
## `move_speed` would otherwise never read as going full tilt, and the stride, the
## step timing, the sway and the turn fade all hang off that reading. Sprint is
## deliberately left out, so holding sprint still takes the animal past pace 1 and
## is still what the gait sees as running rather than walking.
func cruise_speed() -> float:
	var asked: float = params.move_speed * size_scale
	var legs: float = _leg_ceiling()
	return maxf(minf(asked, legs) if legs > 0.0 else asked, 1.0)


## The speed this creature would travel at with everything open — its walk times
## its own sprint, and the denominator exertion is quoted against.
##
## Deliberately the species' figure alone, where `cruise_speed` above takes the
## lower of the request and what the legs deliver. Effort has to mean the same
## thing from one tick to the next or it is not a measurement of how hard the
## animal is trying, and the leg ceiling moves with the footfall pattern: a body
## that commits to a gallop lifts more feet at once and is handed a higher ceiling
## for it, which would read as the animal easing off at the moment it stopped
## easing off.
func flat_out() -> float:
	return maxf(params.move_speed * params.sprint_multiplier * size_scale, 1.0)


## How much of what this creature is doing is backing up, 0..1 of its own reverse
## top speed. Measured off travel rather than off the key, so a body that has
## been commanded backward but is still coasting forward is still steering the
## way it is actually moving.
func _reverse_fraction() -> float:
	return clampf(-speed / maxf(cruise_speed() * params.reverse_speed_factor, 1.0),
		0.0, 1.0)


## How fast the feet can walk this standing body around, in radians per second.
##
## The arithmetic is Locomotion's; what belongs here is the body it is asked
## about, because both terms of it are measurements of this creature's own shape
## this tick. `backing` picks the station, exactly as `_turn_station` does — a
## reversing animal turns about its hips and a forward one about its shoulders, so
## it is genuinely a different amount of animal being swung either way.
func _walked_turn_rate(backing: float) -> float:
	if gait == null or gait.pivot_speed <= 0.0 or spine == null or spine.size() < 2:
		return 0.0
	return locomotion.walked_turn(gait.pivot_speed, _socket_radius(backing))


## How far the furthest weight-bearing socket sits from the point the body turns
## about, along the animal.
##
## The lever the turn is walked on, and the girdle with the longer one is the one
## that runs out of foot speed first — which is why this is the further of the two
## rather than the mean of them. A forelimb that does not reach the ground is left
## out, because a leg nothing is standing on is not a leg that has to keep up.
##
## Measured along the spine rather than through it. A body bent into a turn has
## its hips somewhere off the centreline and the straight-line distance would
## shorten as it curled, which would quietly *raise* the ceiling exactly when the
## animal is already turning hard.
func _socket_radius(backing: float) -> float:
	var arc: float = maxf(spine.arc_length(), 1.0)
	var station: float = clampf(_turn_station_distance(backing), 0.0, arc)
	var reach: float = absf(arc * params.rear_limb_t - station)
	if locomotion.forelimbs_bear:
		reach = maxf(reach, absf(arc * params.front_limb_t - station))
	return maxf(reach, 1.0)


## How far behind the head the turn station sits, along the spine. The one
## expression `_turn_station` and `_gyration` have to agree about, so it is
## written once — see `_turn_station` for why a reversing body turns about its
## hips.
func _turn_station_distance(backing: float) -> float:
	return lerpf(params.turn_pivot * size_scale,
		spine.arc_length() * params.rear_limb_t, backing)


## The point on the body a turn swings the head around.
##
## A station on the flesh, not a distance measured back from the nose, and that
## is the whole difference between turning and shuffling. A point pinned to the
## head travels with the head, so every tick of turn re-places the head sideways
## and the constraint solve tows the body after it: hold A and then D from a
## standstill and the creature translates bodily across the ground while barely
## changing which way it faces. Anchored to a spine point, that point stays where
## it is. The head and neck swing about it, the joints take up the bend, and only
## once they are at their anatomical limit does the rest of the body come round —
## so a direction change starts at the front of the body, from where the body
## already stands, and reversing the command simply swings that front end back
## the other way.
##
## Which station it is, is the one thing that differs between walking forward and
## backing up, and it is not a special case so much as the same rule reading the
## direction of travel. Forward, it is `turn_pivot` behind the head: the
## shoulders, more or less, which is what a standing quadruped pushes its front
## end around. Backing up, the hind legs are doing the pushing and the hips are
## what holds still, so it slides back to them — a reversing body turns about its
## rear axle for the same reason a reversing car does. Left at the shoulders it
## sweeps its whole length around its own nose, which is the tight spin this
## replaced: the head's arc came out several times tighter than the body is long,
## so nothing about the motion could read as walking a curve.
##
## Fades to the head itself as the creature gets going forward, because travel
## already gives a moving turn its arc and a second swing centre there is felt as
## a sideways reposition. Reverse keeps its station regardless of speed: there
## the head is the trailing end, and travel arcs it the wrong way round.
func _turn_station(backing: float, blend: float) -> Vector2:
	if spine == null or spine.size() < 2 or blend <= 0.0:
		return head_pos
	return head_pos.lerp(
		spine.station_behind_head(_turn_station_distance(backing)), blend)


# ------------------------------------------------------------- collision ----

## Pushes this creature out of any other creature it is standing inside.
##
## Each creature resolves its own half of every contact and never touches
## another's state. A contact translates the complete creature: pushing the
## penetrated spine particles separately makes the distance/angle solver pull
## them back on the very next line, creating a slow separation and feeding the
## disagreement into the flexible body as exaggerated flailing.
##
## Detection compares every pair of variable-radius spine capsules rather than
## probing only their endpoints. Endpoint probes miss a thin body crossing the
## middle of a long segment, which is exactly how creatures can become deeply
## interlocked before the old solver notices them.
##
## This pass is body-vs-body only. Limb contacts run later inside the gait solve:
## they bend or slide the limb around the obstacle without pushing either body
## apart at arm's length.
func _resolve_contacts() -> void:
	if spine == null or body == null or not is_inside_tree():
		return
	# The single deepest contact anywhere on the body, kept unclamped so the
	# brake below can read how squarely it opposes travel, along with the share of
	# it this creature's mass makes it responsible for.
	var deepest: Vector2 = Vector2.ZERO
	var deepest_share: float = CONTACT_SHARE
	# The world's own solids first, and this creature does all of the moving for
	# them: a rock is not negotiating. It goes through the same brake as everything
	# else, so walking into one stops the animal rather than grinding it along.
	var wall: Vector2 = _push_out_of_terrain()
	if wall != Vector2.ZERO:
		_translate_contact(wall.limit_length(MAX_CONTACT_PUSH))
		deepest = wall
		deepest_share = 1.0
	# Which bodies this creature had a foot on is re-decided as the feet are
	# placed, so the record is cleared here — at the top of the tick that will
	# read last tick's answer and then write this one's.
	var mounted: Dictionary = _standing_on
	_standing_on = {}
	for node in get_tree().get_nodes_in_group("creatures"):
		var other := node as Creature
		if other == null or other == self or other.body == null or other.spine == null:
			continue
		# Two creatures joined at the jaws are governed by the tether, not by
		# separation. A grip holds the biter's mouth *on* — meaning inside —
		# flesh the contact pass would spend every tick pushing it back out of,
		# and the two constraints act on the same pair at the same point in
		# opposite directions: the pair buzzes, and the stretch the grip's load is
		# measured from runs away with it. So while a hold is in force this pair
		# has exactly one rule between them, and it is the one the jaws impose.
		# Both parties reach the same conclusion from the same grip, so neither
		# collides with the other while the other does not. Everything else in the
		# world still collides with both, and the limbs still route around both.
		if _is_joined_to(other):
			continue
		# The body's bound is from its last solved pose, while the authoritative
		# head has already integrated this tick. Inflate by that small sweep so a
		# fast nose cannot cross the broad-phase boundary unnoticed.
		var head_sweep: float = head_pos.distance_to(spine.points[0])
		if bounds_center.distance_to(other.bounds_center) \
				> bounds_radius + other.bounds_radius + head_sweep:
			continue
		# Two things that are not at the same height are not in each other's way —
		# and that is now asked of each pair of *parts* rather than of the two
		# animals. This walk compares trunks, so what it wants to know is whether
		# the two trunks are at the same height; the legs are a second question
		# with a second answer, because a leg spans the whole gap underneath an
		# animal and the trunk it hangs off does not.
		#
		# That split is the entire mechanic. A lizard fails the trunk test against
		# an elephant and walks under its belly, and passes the leg test against
		# the foot that is on the floor — so it goes underneath the body, into the
		# planted foot, and under the one that has been picked up. Nothing in it is
		# about elephants: it is two bands per part, asked in the order the parts
		# are met. Both parties reach the same answer from the same bands, so
		# neither ever collides with something that is not colliding with it.
		#
		# The trunk test here is only the broad phase — a trunk band is the union
		# of everything from the belly to the crown, so it rejects the pairs that
		# are nowhere near each other and admits the rest. Which piece of which
		# body is actually in the way is settled interval by interval inside, off
		# the lattice's own cell heights, because a trunk is not level: a raised
		# head passes over a tail that the same animal's chest would have hit.
		var push: Vector2 = Vector2.ZERO
		# ...unless this creature is standing on that one. A body being climbed is a
		# surface rather than an obstruction, and the two claims point in opposite
		# directions: the feet are holding the climber up on top of the flank while a
		# correction whose whole job is separating two bodies shoves it back off. It
		# is the same exemption a grip already gets, for the same reason, and it is
		# decided by the feet rather than declared — nothing anywhere sets "climbing",
		# there is simply a foot on a back.
		if not mounted.has(other.get_instance_id()) \
				and Stature.overlaps(stature.trunk, other.stature.trunk):
			push = _push_out_of_creature(other)
		var underfoot: Vector2 = _push_out_of_limbs(other)
		if underfoot.length_squared() > push.length_squared():
			push = underfoot
		if push == Vector2.ZERO:
			continue
		var share: float = _contact_share(other)
		if push.length_squared() > deepest.length_squared():
			deepest = push
			deepest_share = share
		var correction: Vector2 = push.limit_length(MAX_CONTACT_PUSH) * share
		if alive:
			_translate_contact(correction)
		else:
			var local: Vector2 = correction * (1.0 - DEAD_CONTACT_TRANSLATION)
			_translate_contact(correction * DEAD_CONTACT_TRANSLATION)
			_drag_at(spine.sample(_contact_spine_t).pos, local)
	_brake_into(deepest, deepest_share)


## How much of a contact with `other` this creature does the moving for.
##
## Mass, and nothing else. The share is the *other* body's fraction of the pair's
## total, so a light creature does nearly all of the moving and a heavy one barely
## notices. Both parties compute it from the same two numbers, so the two shares
## sum to exactly one and the separation is still complete without either creature
## writing into the other's state. Equal masses give 0.5 each — the constant this
## replaced — so two creatures of the same build behave exactly as they did.
##
## This is the whole of what weight does to a contact. There is still no shove
## force and no momentum transfer: what changed is only *who yields*, which is
## what the pass was already deciding and previously always split down the middle.
func _contact_share(other: Creature) -> float:
	if other == null or other.physique == null:
		return CONTACT_SHARE
	var total: float = physique.mass + other.physique.mass
	if total <= 0.0:
		return CONTACT_SHARE
	return clampf(other.physique.mass / total, MIN_CONTACT_SHARE, 1.0 - MIN_CONTACT_SHARE)


## Deepest capsule-pair penetration from `other` into this creature. The return
## vector points in the direction this whole creature must move to get clear.
func _push_out_of_creature(other: Creature) -> Vector2:
	var self_last: int = mini(body.last_index, spine.size() - 1)
	var other_last: int = mini(other.body.last_index, other.spine.size() - 1)
	if self_last < 1 or other_last < 1:
		return Vector2.ZERO

	var deepest: float = 0.0
	var out: Vector2 = Vector2.ZERO
	# The widest either interval can be before anything narrows it, so a pair can
	# be dismissed on its geometry alone — see the skip in the inner loop.
	var self_reach: PackedFloat32Array = _interval_reach(body, self_last)
	var other_reach: PackedFloat32Array = _interval_reach(other.body, other_last)
	var other_points: PackedVector2Array = other.spine.points
	var other_widths: PackedFloat32Array = other.body.widths
	for i in range(self_last):
		var a0: Vector2 = head_pos if i == 0 else spine.points[i]
		var a1: Vector2 = spine.points[i + 1]
		for j in range(other_last):
			var b0: Vector2 = other_points[j]
			var b1: Vector2 = other_points[j + 1]
			var uv: Vector2 = _closest_segment_parameters(a0, a1, b0, b1)
			var axis_a: Vector2 = a0.lerp(a1, uv.x)
			var axis_b: Vector2 = b0.lerp(b1, uv.y)
			var delta: Vector2 = axis_a - axis_b
			var distance: float = delta.length()
			# The most this pair could possibly be overlapping by, if both pieces of
			# trunk turned out to be at the same height and completely intact. When
			# even that is not deeper than the deepest contact already found, nothing
			# below can change the answer — so the four lattice queries that would
			# have narrowed it are never asked. Most of the pairs on two bodies the
			# length of these are metres apart, and every one of them was costing two
			# solidity lookups and two band lookups to establish it.
			if self_reach[i] + other_reach[j] - distance <= deepest:
				continue
			var normal: Vector2 = delta / distance if distance > CONTACT_EPSILON \
				else _coincident_contact_normal(other, a0, a1, b0, b1)

			# Each radius is narrowed on the side actually facing the contact, so
			# a bitten-open flank remains a real opening in both halves of the test.
			var self_side: float = (-normal).dot(spine.perps[i])
			var other_side: float = normal.dot(other.spine.perps[j])
			var self_solid: float = _contact_solid(i, uv.x, self_side, self_last)
			var other_solid: float = other._contact_solid(j, uv.y, other_side, other_last)
			if self_solid <= 0.0 or other_solid <= 0.0:
				continue
			# The third axis, asked of the two pieces of trunk that are actually
			# meeting rather than of the two animals. Both bodies rise from the
			# back to the head over the neck, so this is what lets a tall animal
			# put its muzzle down over a small one's back without shouldering it
			# aside, and what stops a body that is genuinely underneath another
			# from being pushed out sideways by it.
			if not Volume.overlaps(_trunk_band_at(i, uv.x, self_last),
					other._trunk_band_at(j, uv.y, other_last)):
				continue
			var self_radius: float = lerpf(body.widths[i], body.widths[i + 1], uv.x) * self_solid
			var other_radius: float = lerpf(
				other_widths[j], other_widths[j + 1], uv.y) * other_solid
			var overlap: float = self_radius + other_radius - distance
			if overlap <= deepest:
				continue
			deepest = overlap
			out = normal * overlap
			_contact_spine_t = (float(i) + uv.x) / float(maxi(spine.size() - 1, 1))
	return out


## The furthest each interval of a trunk can possibly reach from its own axis:
## the wider of the two widths bracketing it.
##
## An upper bound and only ever used as one. Every contact radius taken along an
## interval is a blend of the same two widths, narrowed by however much tissue is
## missing there, and neither the blend nor the narrowing can come out above the
## larger of the pair — so a pair of intervals further apart than the sum of their
## reaches cannot be touching, whatever the lattice would have said about them.
static func _interval_reach(shape: BodyShape, last: int) -> PackedFloat32Array:
	var reach: PackedFloat32Array = PackedFloat32Array()
	reach.resize(last)
	for i in range(last):
		reach[i] = maxf(shape.widths[i], shape.widths[i + 1])
	return reach


## Deepest penetration of this creature's trunk into any of `other`'s legs, as
## the vector this whole creature must move to get clear.
##
## The counterpart of the limb contact pass, and it has to exist separately for
## the same reason the trunk band does: a leg is the one structure that spans the
## gap under an animal, so it is the only part of a tall one a low one can walk
## into. Without this a lizard passing beneath an elephant meets nothing at all
## on the way through — the belly is out of its reach and the legs were never
## asked about — and the animal reads as a hologram on four sticks.
##
## Height decides it part by part rather than animal by animal. A foot on the
## floor occupies the band a small body is in and stops it; the same foot at the
## top of a step occupies a band above it and does not. Neither is a rule about
## feet: it is one band test, asked once per drawn piece of leg.
##
## On the ground plane, like the rest of the contact pass and for the reason given
## at length in Gait._solve_limb: a body passes underneath a leg by being in the
## same place at a different height, and the picture is not a frame in which that
## sentence can be written.
##
## Only a leg that is standing on something. A limb in mid-swing is already free
## to go round whatever is in the way — that is what the gait's own contact pass
## does with it, and a foot that steps over an obstacle has not collided with it.
## A planted one has no such option: it is carrying the animal, so it is the
## obstacle, and what moves is whatever walked into it. The distinction costs one
## line and it is the difference between legs that read as legs and legs that
## read as a cowcatcher.
##
## Only this creature is moved, as everywhere else in the contact pass. The limbs
## stay kinematic — being walked into does not push the leg aside, and the animal
## whose leg it is feels nothing.
func _push_out_of_limbs(other: Creature) -> Vector2:
	if other.gait == null or spine == null or body == null:
		return Vector2.ZERO
	var deepest: Vector2 = Vector2.ZERO
	var toward: Vector2 = other.bounds_center - bounds_center
	for limb in other.gait.limbs:
		if limb.severed or limb.stepping:
			continue
		# A leg with this creature's teeth in it is held rather than resolved, for
		# the same reason a gripped body is: jaws hold flesh by being inside it, so
		# a correction whose whole job is getting one out of the other points
		# against the tether and the pair buzzes. It matters most exactly here —
		# a leg is the only part of a tall animal a low one can reach, so without
		# it the vertical layer's own mechanic would shove every attacker off the
		# only target it has.
		if grip != null and grip.is_alive() and grip.victim == other \
				and grip.holds_limb() and grip.limb_key == limb.key:
			continue
		for segment in 3:
			# Off the other animal's own lattice, so the leg's heights come from
			# the same cells a bite on it would find — and with that animal's
			# elevation already in them, which is what stops a leaping creature's
			# legs colliding with things at the height it took off from.
			var leg: Vector2 = other.anatomy.tissue.limb_band(limb.key, segment)
			if not Stature.overlaps(stature.trunk, leg):
				continue
			var solid: float = other.anatomy.tissue.limb_solid(limb.key, segment)
			if solid <= 0.0:
				continue
			var radius: float = limb.foot_radius(other.size_scale) if segment == 2 \
				else limb.segment_girth(segment, other.size_scale) * 0.5
			# `push_capsule_out_of_body` answers for the capsule; this body is the
			# one that yields, so it goes the other way. The leg's band goes with
			# it: which of *this* creature's own intervals the leg is standing in
			# is the question, and the answer is not the same all down the back.
			var clear: Vector2 = push_capsule_out_of_body(
				limb.plan[segment], limb.plan[mini(segment + 1, 2)], radius * solid,
				toward, leg)
			if clear.length_squared() > deepest.length_squared():
				deepest = -clear
	return deepest


# ------------------------------------------------------------- underfoot ----
# Where the floor is, which used to be a constant.
#
# Everything in this file already worked in three axes: a leg spans from a socket
# at one height to a foot at another, a band is compared against a band, and the
# picture is a projection of both. The one thing that was still flat was the
# assumption underneath all of it — that the bottom of the world is zero
# everywhere. These four functions replace that assumption with a query, and
# nothing else about the solver had to change: a foot put down on a ledge is a
# foot at a height, and every line that reads a foot's height was already reading
# one.

## The habitat's terrain, or null in one that has none.
func terrain() -> Terrain:
	if not _terrain_looked and is_inside_tree():
		_terrain_looked = true
		_terrain_field = get_tree().get_first_node_in_group("terrain") as Terrain
	return _terrain_field


## What one of this creature's feet would be standing on at `at`.
##
## Handed to the gait as a callable and asked once per foot per tick. `ceiling` is
## how high that particular foot can be put down — the gait works it out off the
## socket carrying it, and it is the first of `Traversal`'s three conditions
## arriving here as a number rather than as a rule. Anything above it is not a
## surface for this leg, so the query walks past it and answers with whatever is
## underneath, which is the difference between stepping onto a ledge and walking
## into a wall.
##
## Returns `(height, foothold)`: how far off the world's floor the surface is, and
## how much room the foot has on it.
##
## Other animals are surfaces too, and they are here rather than in the terrain
## for the obvious reason — they move. A body part is a footprint and a band like
## anything else, so a creature low enough to get its foot above one climbs onto
## it and one that is not, does not; the cat that will not rise over another cat
## and the lizard that will go over a tail are the same comparison with different
## numbers in it. Only the trunk, because that is the part with a top: a leg is a
## round bone held at an angle and nothing stands on one.
func _surface_under_foot(at: Vector2, foot_radius: float,
		ceiling: float = INF) -> Vector2:
	var height: float = 0.0
	var room: float = INF
	var field: Terrain = terrain()
	if field != null:
		var ground: Vector2 = field.surface(at, foot_radius, ceiling)
		height = ground.x
		room = ground.y
	if not is_inside_tree():
		return Vector2(height, room)

	for node in get_tree().get_nodes_in_group("creatures"):
		var other := node as Creature
		if other == null or other == self or other.body == null or other.spine == null:
			continue
		if at.distance_to(other.bounds_center) > other.bounds_radius + foot_radius:
			continue
		var last: int = mini(other.body.last_index, other.spine.size() - 1)
		var tissue: TissueGrid = other.anatomy.tissue
		for i in range(last):
			var a: Vector2 = other.spine.points[i]
			var b: Vector2 = other.spine.points[i + 1]
			var u: float = AnatomyState.segment_u(at, a, b)
			var axis: Vector2 = a.lerp(b, u)
			var t: float = (float(i) + u) / float(maxi(last, 1))
			# Narrowed to the tissue still standing, exactly as every other contact
			# with this body is. A flank eaten open is not a step.
			var solid: float = tissue.body_solid(t, (at - axis).dot(other.spine.perps[i]))
			if solid <= 0.0:
				continue
			var band: Vector2 = tissue.body_band(t)
			# Too high for this leg, already below the foot, or with its underside
			# above where the foot is — the same three rejections the terrain makes,
			# and for the same reasons.
			if band.y > ceiling or band.y <= height or band.x > height:
				continue
			var width: float = lerpf(other.body.widths[i], other.body.widths[i + 1], u) * solid
			var margin: float = width - at.distance_to(axis) - foot_radius
			if margin <= -foot_radius:
				continue
			height = band.y
			room = margin
			_standing_on[other.get_instance_id()] = true
	return Vector2(height, room)


## The height this creature is currently standing at: the lowest of the surfaces
## under its planted feet. Zero on the open floor, and whatever it has climbed
## onto otherwise — which is what makes a second ledge on top of the first an
## ordinary crossing rather than a special case.
func ground_height() -> float:
	if gait == null or gait.limbs.is_empty():
		return 0.0
	var lowest: float = INF
	for limb in gait.limbs:
		if limb.severed or limb.carried or limb.stepping:
			continue
		lowest = minf(lowest, limb.surface)
	return 0.0 if is_inf(lowest) else lowest


## What this body could do about the obstacle in front of it, if anything. The
## whole of `Traversal` reached through one line, so callers — the contact pass
## below, the debug overlay, the tests — never assemble the measurements
## themselves and cannot disagree about them.
func traversal(obstacle: Obstacle) -> int:
	if obstacle == null:
		return Traversal.CLEAR
	return Traversal.assess(Traversal.of(self), obstacle.base(), obstacle.top(),
		obstacle.girth(), ground_height())


## Deepest penetration of this creature's trunk into the terrain, as the vector it
## must move to get clear.
##
## Only into what it cannot get past. That gate is the whole of "adapt locomotion
## only when traversal is physically possible", stated from the other side: an
## obstacle this animal can walk over, climb onto or duck under is not a wall, so
## the contact pass leaves it alone and the legs deal with it — the feet find the
## top through `_surface_under_foot`, the body rises onto whatever they found, and
## the bands go up with it. One that it cannot get past is a wall, and is resolved
## exactly as another animal's flank is.
##
## Per interval, like every other contact in this file, because a trunk is not
## level: a browsing animal's raised head clears a rock its own chest walks into.
func _push_out_of_terrain() -> Vector2:
	var field: Terrain = terrain()
	if field == null or spine == null or body == null:
		return Vector2.ZERO
	var last: int = mini(body.last_index, spine.size() - 1)
	var deepest: Vector2 = Vector2.ZERO
	# The whole trunk as one circle, which is all it takes to say "nowhere near
	# it" — the same broad phase, off the same two numbers, that the
	# creature-to-creature pass below runs before it walks anybody's spine. It is
	# the difference between asking about the rock the animal is standing against
	# and asking about all of them in the habitat: without it a boulder on the far
	# side of the map costs a full walk of the trunk, interval by interval, tissue
	# query by tissue query, every tick, forever.
	#
	# Deliberately generous, because a bound that rejects something it should have
	# kept is a body walking through a rock. Every point tested below lies on the
	# spine polyline, which is inside the bounds; every radius tested is at most
	# the widest the body gets; and the nose has already integrated this tick
	# while the bounds are still from the last solved pose, so its own sweep goes
	# on as well. Nothing that could touch can be outside that.
	var bound: float = bounds_radius + _widest_trunk(last) \
		+ head_pos.distance_to(spine.points[0])
	# Measured on the first obstacle that survives the broad phase and not before.
	# In a habitat whose rocks are all somewhere else — which is most ticks of most
	# walks — the body is never measured at all.
	var dimensions: Traversal.Body = null
	var here: float = 0.0
	for obstacle in field.obstacles:
		if obstacle.gone():
			continue
		if bounds_center.distance_to(obstacle.at) > bound + obstacle.girth():
			continue
		if dimensions == null:
			dimensions = Traversal.of(self)
			here = ground_height()
		if Traversal.passable(Traversal.assess(dimensions, obstacle.base(),
				obstacle.top(), obstacle.girth(), here)):
			continue
		for i in range(last):
			var a: Vector2 = head_pos if i == 0 else spine.points[i]
			var b: Vector2 = spine.points[i + 1]
			var solid: float = _solid_at(i, last)
			if solid <= 0.0:
				continue
			var radius: float = (body.widths[i] + body.widths[i + 1]) * 0.5 * solid
			var push: Vector2 = obstacle.push_capsule(a, b, radius,
				_trunk_band_at(i, 0.5, last))
			if push.length_squared() > deepest.length_squared():
				deepest = push
	return deepest


## The widest the trunk gets, which is the most any one interval's contact radius
## can be: that radius is the mean of two widths, narrowed by tissue that is
## missing, and neither operation can exceed the larger of the pair.
func _widest_trunk(last: int) -> float:
	var widest: float = 0.0
	for i in range(last + 1):
		widest = maxf(widest, body.widths[i])
	return widest


## Translates the pose as one piece and cancels the same shift out of the gait's
## socket-velocity history. Feet may remain planted and naturally take a step,
## but collision correction must not masquerade as a huge burst of locomotion.
func _translate_contact(offset: Vector2) -> void:
	if offset == Vector2.ZERO:
		return
	head_pos += offset
	spine.translate(offset)
	bounds_center += offset
	if gait != null:
		for limb in gait.limbs:
			if limb.socket_tracked:
				limb.prev_anchor += offset
	# A carcass's limbs are particles rather than IK targets, so they have to be
	# carried by the same shift. Left behind by one, the length constraints would
	# snap them back into place on the following tick.
	if ragdoll != null and gait != null:
		ragdoll.translate(gait.limbs, offset)


## Tissue reach for one point along a contact capsule. The explicit head cap
## owns the front half of the first interval; the remaining chain uses the
## side-specific torso lattice.
func _contact_solid(segment: int, u: float, side: float, last: int) -> float:
	if segment == 0 and u <= 0.5:
		# An open mouth is not a solid. Jaws part *around* what they close on,
		# so now that a bite lands where the mouth is, the head has to be able to
		# arrive over the flesh — and the contact pass, whose whole job is
		# pushing bodies out of each other, is precisely what would stop it. A
		# lunging creature would shove its prey away with its own face and then
		# bite the gap it had just opened.
		#
		# This is the rule a grip already imposes on a joined pair, applied to
		# the moment before there is a grip, and through the same channel every
		# other hole in a body uses: the gape simply reads as tissue that is not
		# there. It lasts exactly as long as the jaws are open — the head is
		# solid again on the frame they shut, which is the frame the bite
		# resolves — so a strike that misses is shouldered apart immediately and
		# one that connects is held by the tether instead.
		return anatomy.tissue.head_solid() * (1.0 - mouth_gape())
	var t: float = (float(segment) + u) / float(maxi(last, 1))
	# At an end cap the contact direction can be parallel to the spine, with no
	# meaningful flank sign. The circular cap reaches as far as its wider side.
	if absf(side) <= CONTACT_EPSILON:
		return maxf(anatomy.tissue.body_solid(t, -1.0),
			anatomy.tissue.body_solid(t, 1.0))
	return anatomy.tissue.body_solid(t, side)


## The heights one point along a contact capsule occupies. The vertical
## counterpart of `_contact_solid`, addressed identically, so the two halves of
## every contact test are always talking about the same piece of animal.
##
## The head cap owns the front half of the first interval here for exactly the
## reason it does above: it is a separate structure standing at a separate height
## — up on the end of the neck — and a contact that read it as the front of the
## trunk would have a browsing animal's chin colliding with things its chest is a
## body's depth above.
func _trunk_band_at(segment: int, u: float, last: int) -> Vector2:
	if segment == 0 and u <= 0.5:
		return anatomy.tissue.head_band()
	return anatomy.tissue.body_band((float(segment) + u) / float(maxi(last, 1)))


## Closest parameters on two finite line segments, returned as (u, v). This is
## the narrow-phase axis query for the two capsules.
static func _closest_segment_parameters(a0: Vector2, a1: Vector2,
		b0: Vector2, b1: Vector2) -> Vector2:
	var da: Vector2 = a1 - a0
	var db: Vector2 = b1 - b0
	var r: Vector2 = a0 - b0
	var aa: float = da.dot(da)
	var bb: float = db.dot(db)
	var ab: float = da.dot(db)
	var ar: float = da.dot(r)
	var br: float = db.dot(r)
	var u: float = 0.0
	var v: float = 0.0

	if aa <= CONTACT_EPSILON and bb <= CONTACT_EPSILON:
		return Vector2.ZERO
	if aa <= CONTACT_EPSILON:
		return Vector2(0.0, clampf(br / bb, 0.0, 1.0))
	if bb <= CONTACT_EPSILON:
		return Vector2(clampf(-ar / aa, 0.0, 1.0), 0.0)

	var denominator: float = aa * bb - ab * ab
	if denominator > CONTACT_EPSILON:
		u = clampf((ab * br - ar * bb) / denominator, 0.0, 1.0)
	v = (ab * u + br) / bb
	if v < 0.0:
		v = 0.0
		u = clampf(-ar / aa, 0.0, 1.0)
	elif v > 1.0:
		v = 1.0
		u = clampf((ab - ar) / aa, 0.0, 1.0)
	return Vector2(u, v)


## Intersecting/collinear axes have no geometric separation direction. Pick a
## stable normal from the lower-instance-id participant, then orient it away
## from the other centre (or by id when the centres also coincide). Both sides
## consequently choose exact opposites even when their headings are reversed.
func _coincident_contact_normal(other: Creature, a0: Vector2, a1: Vector2,
		b0: Vector2, b1: Vector2) -> Vector2:
	var self_first: bool = get_instance_id() < other.get_instance_id()
	var tangent: Vector2 = (a1 - a0) if self_first else (b1 - b0)
	if tangent.length_squared() <= CONTACT_EPSILON:
		tangent = Vector2.RIGHT
	tangent = tangent.normalized()
	var normal := Vector2(-tangent.y, tangent.x)
	# Canonicalise an unoriented axis so reversed creature headings agree.
	if normal.x < -CONTACT_EPSILON \
			or (absf(normal.x) <= CONTACT_EPSILON and normal.y < 0.0):
		normal = -normal
	var centre_delta: Vector2 = bounds_center - other.bounds_center
	var side: float = centre_delta.dot(normal)
	if absf(side) > CONTACT_EPSILON:
		return normal * signf(side)
	return normal if self_first else -normal


## Collision callback consumed by Gait while it solves a limb. Limbs only react
## to other creatures' bodies: their own torso is already excluded by the gait's
## anatomical stance envelope, and limb-vs-limb contacts would make four light,
## kinematic chains snag one another without a useful notion of mass.
##
## `a` and `b` are on the ground plane, where the limb actually is, and `band` is
## the heights this piece of it occupies. Both matter and the second is the new
## one: a leg reaching down past a tall animal's belly passes through the band a
## short one is standing in, so it has to be routed around that body — while the
## same animal's own trunk, held a leg's length overhead, is not in its way at
## all. Without the band a tall creature's legs would shoulder aside things its
## body is nowhere near.
func _limb_contact_push(limb_key: String, limb_segment: int,
		a: Vector2, b: Vector2, radius: float,
		band: Vector2 = Stature.UNBOUNDED) -> Vector2:
	if not is_inside_tree() or radius <= 0.0:
		return Vector2.ZERO
	var solid: float = anatomy.tissue.limb_solid(limb_key, limb_segment)
	if solid <= 0.0:
		return Vector2.ZERO
	# The gait and the ragdoll both solve a limb in the creature's own frame, so
	# the band arrives measured from this animal's ground rather than the world's.
	# This is the boundary where it becomes a world band, and it has to be crossed
	# here rather than at either caller: a leaping creature's legs are as far off
	# the floor as the rest of it, and a band that forgot to say so would have
	# them barging through bodies the animal is sailing over.
	band = Volume.lift(band, stature.elevation)
	var collision_radius: float = radius * solid
	var midpoint: Vector2 = (a + b) * 0.5
	var capsule_bound: float = a.distance_to(b) * 0.5 + collision_radius
	var deepest: Vector2 = Vector2.ZERO

	# The world's solids, on the same terms and with the same gate the trunk pass
	# uses: a leg routes around what the animal cannot get past, and around
	# nothing else. Anything it *can* get past is something the foot is about to
	# be put on top of or swung over, and a router that pushed the bone off it
	# would be undoing the placement as fast as the gait made it — the leg would
	# stand beside every ledge it was trying to climb.
	#
	# Distance first, and it is not a micro-optimisation. This is the innermost
	# loop in the whole solve — three bones, six contact iterations, four legs,
	# every creature, every tick — so anything asked here that is not about the
	# one obstacle this bone might actually be touching is asked some hundreds of
	# times a frame for nothing. The gate and the verdict both need the whole body
	# measured; the broad phase needs one distance, and it rejects every rock in
	# the habitat but the one the leg is standing beside. Which is why the body is
	# measured inside the loop rather than above it: a leg nowhere near anything
	# never measures at all.
	var field: Terrain = terrain()
	if field != null:
		var dimensions: Traversal.Body = null
		var here: float = 0.0
		for obstacle in field.obstacles:
			if obstacle.gone() \
					or midpoint.distance_to(obstacle.at) > capsule_bound + obstacle.girth():
				continue
			if dimensions == null:
				dimensions = Traversal.of(self)
				here = ground_height()
			if Traversal.passable(Traversal.assess(dimensions, obstacle.base(),
					obstacle.top(), obstacle.girth(), here)):
				continue
			var wall: Vector2 = obstacle.push_capsule(a, b, collision_radius, band)
			if wall.length_squared() > deepest.length_squared():
				deepest = wall
	for node in get_tree().get_nodes_in_group("creatures"):
		var other := node as Creature
		if other == null or other == self or other.body == null or other.spine == null:
			continue
		# The one limb somebody has their teeth in is exempt from being pushed out
		# of them, and it is the same rule the body pass already applies to a
		# joined pair: jaws hold flesh by being *inside* it, so a correction whose
		# whole job is getting a body out of another one is pointing the opposite
		# way to the tether and the two fight every tick. Only this limb and only
		# against this creature — every other leg still routes around both bodies,
		# because nothing is holding those.
		#
		# It matters most exactly where the vertical layer sends a small predator:
		# a leg is the only thing on a tall animal a low one can reach, so without
		# this a hold down there is shaken off by the victim's own gait solver
		# within a couple of ticks and legs are effectively unbiteable.
		if _held_by != null and _held_by.is_alive() and _held_by.biter == other \
				and _held_by.holds_limb() and _held_by.limb_key == limb_key:
			continue
		if midpoint.distance_to(other.bounds_center) \
				> capsule_bound + other.bounds_radius:
			continue
		# The same one rule the body pass uses, asked of this piece of leg against
		# that animal's trunk. A foot swinging through the air over something small
		# is not touching it, and a leg reaching down past a tall animal's belly to
		# the floor is touching everything down there.
		#
		# Broad phase only: the trunk band is the union of everything from that
		# animal's belly to its crown, so passing it means "somewhere on that body
		# is at my height" rather than "that body is". Which part is settled inside
		# `push_capsule_out_of_body`, interval by interval, off the band this same
		# piece of leg carries.
		if not Stature.overlaps(band, other.stature.trunk):
			continue
		var push: Vector2 = other.push_capsule_out_of_body(
			a, b, collision_radius, bounds_center - other.bounds_center, band)
		if push.length_squared() > deepest.length_squared():
			deepest = push
	return deepest


## Pushes an arbitrary capsule out of this creature's tissue-aware body. Used
## for limb bones and feet, including the mid-segment crossings that a point
## query cannot see. `preferred` resolves the otherwise ambiguous direction
## when the two capsule axes intersect exactly.
##
## `band` is the heights the capsule occupies, and it is tested against the
## heights of each interval of *this* body rather than against the body as a
## whole. That is what makes the gap between a tall animal's belly and the floor
## a real gap: a low creature's back passes under the chest and is stopped by the
## neck sloping down in front of it, from one rule asked twenty times instead of
## one rule asked once. Left unbounded, every interval is fair game — the flat
## behaviour, for a caller with no height to declare.
func push_capsule_out_of_body(a: Vector2, b: Vector2, radius: float,
		preferred: Vector2 = Vector2.ZERO,
		band: Vector2 = Stature.UNBOUNDED) -> Vector2:
	if body == null or spine == null or radius <= 0.0:
		return Vector2.ZERO
	var last: int = mini(body.last_index, spine.size() - 1)
	var deepest: float = 0.0
	var out: Vector2 = Vector2.ZERO
	var reach: PackedFloat32Array = _interval_reach(body, last)
	for i in range(last):
		var body_a: Vector2 = spine.points[i]
		var body_b: Vector2 = spine.points[i + 1]
		var uv: Vector2 = _closest_segment_parameters(a, b, body_a, body_b)
		var limb_axis: Vector2 = a.lerp(b, uv.x)
		var body_axis: Vector2 = body_a.lerp(body_b, uv.y)
		var delta: Vector2 = limb_axis - body_axis
		var distance: float = delta.length()
		# As in the trunk-to-trunk pass: the deepest this interval could be, with
		# the flesh entirely intact and both bands ignored. Anything that cannot
		# beat the contact already in hand is not worth two lattice queries.
		if radius + reach[i] - distance <= deepest:
			continue
		var normal: Vector2
		if distance > CONTACT_EPSILON:
			normal = delta / distance
		else:
			# Prefer the side containing the limb root/owning creature. Projecting
			# onto the body's normal chooses the shortest route out rather than
			# sliding an intersecting bone all the way along the torso.
			var body_normal: Vector2 = spine.perps[i]
			var root_side: float = (a - body_axis).dot(body_normal)
			if absf(root_side) <= CONTACT_EPSILON:
				root_side = preferred.dot(body_normal)
			normal = body_normal * (-1.0 if root_side < 0.0 else 1.0)
		var side: float = normal.dot(spine.perps[i])
		var solid: float = _contact_solid(i, uv.y, side, last)
		if solid <= 0.0:
			continue
		if not Volume.overlaps(band, _trunk_band_at(i, uv.y, last)):
			continue
		var body_radius: float = lerpf(body.widths[i], body.widths[i + 1], uv.y) * solid
		var overlap: float = radius + body_radius - distance
		if overlap <= deepest:
			continue
		deepest = overlap
		out = normal * overlap
	return out


## How much tissue is still standing around one spine point, as a fraction of
## the width the silhouette would have there. The probe is a circle about the
## axis, so it takes the wider of the two flanks — a body eaten open on one side
## is still as wide as the side that survived.
func _solid_at(i: int, last: int) -> float:
	var tissue: TissueGrid = anatomy.tissue
	if i == 0:
		return tissue.head_solid()
	var t: float = float(i) / float(maxi(last, 1))
	return maxf(tissue.body_solid(t, 1.0), tissue.body_solid(t, -1.0))


## Sheds the part of the forward speed that is driving into a contact.
##
## Position alone is not enough, and the difference is not subtle. Corrected
## only positionally, a creature walking into another keeps walking: it either
## grinds through, or — measured — shoves a stationary creature across the world
## ahead of it at its own full speed, with no resistance at all. Scaling `speed`
## by how squarely the contact opposes travel stops it dead head-on and leaves
## it entirely free to slide along a flank, which is the difference between
## another creature reading as solid and reading as sticky.
##
## Heading is deliberately untouched, so a creature pressed against another can
## always turn away and walk off.
##
## `share` is the fraction of the contact this creature's mass made it responsible
## for, and scaling the brake by it is what gives weight a consequence in motion
## rather than only in position. A heavy creature walking into a light one is
## barely slowed by it and pushes it along ahead of itself; a light one walking
## into a heavy one stops as dead as it always did. At equal masses this is half
## the old rate, which still collapses the speed within a few ticks.
func _brake_into(push: Vector2, share: float) -> void:
	if push == Vector2.ZERO or is_zero_approx(speed):
		return
	var into: float = -(move_dir * speed).normalized().dot(push.normalized())
	if into > 0.0:
		speed = move_toward(speed, 0.0, absf(speed) * into * clampf(share, 0.0, 1.0))


## The displacement that would just lift a circle of `radius` at `at` clear of
## this creature's body, or ZERO if it is already clear.
## Tested against the same chain of variable-radius capsules the view fills, so
## creatures collide with exactly the silhouette that is drawn. Only the deepest
## overlap is returned: consecutive capsules share their end caps, so summing
## them would push out by several times the actual penetration.
##
## Each capsule is narrowed to the tissue that is actually still there, per
## side, so a body eaten open is open: a flank chewed halfway in stops pushing
## at the new surface, and a station eaten clean through stops colliding at all
## and can be walked straight into. Without this the hole would be a hole you
## could see through and not one you could reach through, which is the same
## illusion as painting the ground colour over it.
func push_out_of_body(at: Vector2, radius: float) -> Vector2:
	if body == null or spine == null:
		return Vector2.ZERO
	var last: int = mini(body.last_index, spine.size() - 1)
	var tissue: TissueGrid = anatomy.tissue
	var deepest: float = 0.0
	var out: Vector2 = Vector2.ZERO
	for i in range(last):
		var a: Vector2 = spine.points[i]
		var b: Vector2 = spine.points[i + 1]
		var u: float = AnatomyState.segment_u(at, a, b)
		var axis: Vector2 = a.lerp(b, u)
		var delta: Vector2 = at - axis
		var distance: float = delta.length()
		var side: float = delta.dot(spine.perps[i])
		var solid: float = tissue.body_solid((float(i) + u) / float(maxi(last, 1)), side)
		if solid <= 0.0:
			continue
		var overlap: float = radius + lerpf(body.widths[i], body.widths[i + 1], u) * solid - distance
		if overlap <= deepest:
			continue
		deepest = overlap
		# Dead centre on the axis there is no direction to leave by, so fall back
		# to the flank normal — sideways is the shortest way out of a body that
		# is far longer than it is wide.
		out = (delta / distance if distance > 0.0001 else spine.perps[i]) * overlap
	return out


## Refreshes the broad-phase bounding circle from the pose just solved. Built
## from the body's own cross-sections rather than from arc length, so a coiled
## creature gets a tight bound instead of one sized for a straight one.
func _update_bounds() -> void:
	if spine == null or body == null:
		return
	var last: int = mini(body.last_index, spine.size() - 1)
	var lo: Vector2 = spine.points[0]
	var hi: Vector2 = lo
	for i in range(last + 1):
		var w: float = body.widths[i]
		var at: Vector2 = spine.points[i]
		lo = Vector2(minf(lo.x, at.x - w), minf(lo.y, at.y - w))
		hi = Vector2(maxf(hi.x, at.x + w), maxf(hi.y, at.y + w))
	bounds_center = (lo + hi) * 0.5
	bounds_radius = lo.distance_to(hi) * 0.5


# ------------------------------------------------------------ body space ----
# A grip has to survive the pose being rebuilt from scratch every tick, and a
# structural rebuild on top of that, so it is stored the same way tissue damage
# is: in body space. These three convert between that and the world.

## World position of a point bound into this creature's body space. `bind` is
## (spine_t, lateral), lateral running -1..1 across the local half-width.
##
## Read off the live spine rather than the cached BodyShape frame, so it stays
## truthful inside the contact phase — where the creature may already have been
## translated this tick but the silhouette has not yet been rebuilt around it.
func body_point(bind: Vector2) -> Vector2:
	if spine == null or body == null or body.widths.is_empty():
		return head_pos
	var frame: Spine.Frame = spine.sample(clampf(bind.x, 0.0, 1.0))
	return frame.pos + frame.perp * (bind.y * _width_at(bind.x))


## The inverse: the body-space coordinates of a world point, clamped onto the
## silhouette so jaws closing just outside a flank still bind to the flesh rather
## than to the air beside it.
func body_bind(at: Vector2) -> Vector2:
	if spine == null or body == null or spine.size() < 2:
		return Vector2.ZERO
	var last: int = maxi(mini(body.last_index, spine.size() - 1), 1)
	var span: float = float(maxi(spine.size() - 1, 1))
	var best := Vector2.ZERO
	var best_distance: float = INF
	for i in range(last):
		var a: Vector2 = spine.points[i]
		var b: Vector2 = spine.points[i + 1]
		var u: float = AnatomyState.segment_u(at, a, b)
		var axis: Vector2 = a.lerp(b, u)
		var d: float = at.distance_squared_to(axis)
		if d >= best_distance:
			continue
		best_distance = d
		var half: float = lerpf(body.widths[i], body.widths[i + 1], u)
		best = Vector2((float(i) + u) / span,
			clampf((at - axis).dot(spine.perps[i]) / maxf(half, 0.001), -1.0, 1.0))
	return best


## How much tissue is still standing where a bind sits, 0 if it has been eaten
## clean through. The lattice indexes the torso over the *clipped* spine while a
## bind runs over the whole chain, so the conversion lives here rather than being
## left loose in two coordinate systems at the call sites.
func bind_solid(bind: Vector2) -> float:
	if spine == null or body == null:
		return 0.0
	var span: float = float(maxi(spine.size() - 1, 1))
	# The same split the contact query uses: the explicit head cap owns the front
	# half of the first interval and the torso lattice owns everything behind it.
	# Without it a hold on the snout is judged by the first *torso* column, which
	# is a different piece of the creature entirely.
	if bind.x * span < 0.5:
		return anatomy.tissue.head_solid()
	var last: float = float(maxi(mini(body.last_index, spine.size() - 1), 1))
	return anatomy.tissue.body_solid(clampf(bind.x * span / last, 0.0, 1.0), bind.y)


## The hit points still standing in the single lattice cell a bind sits in — what
## the flesh in a set of jaws is actually made of, and so what a pull has to part
## to take it away. Split at the snout exactly the way `bind_solid` is, and for
## the same reason.
func bind_hp(bind: Vector2) -> float:
	if spine == null or body == null:
		return 0.0
	var span: float = float(maxi(spine.size() - 1, 1))
	if bind.x * span < 0.5:
		return anatomy.tissue.head_hp(bind.y)
	var last: float = float(maxi(mini(body.last_index, spine.size() - 1), 1))
	return anatomy.tissue.body_hp(clampf(bind.x * span / last, 0.0, 1.0), bind.y)


## World-space reconstruction of a point bound to one of the articulated limb
## primitives reported by AnatomyState. Segment 0 is socket->joint, segment 1 is
## joint->foot, and segment 2 is the foot itself.
func limb_point(key: String, segment: int, u: float) -> Vector2:
	var limb: Limb = _limb_by_key(key)
	if limb == null:
		return head_pos
	match segment:
		0:
			return limb.joints[0].lerp(limb.joints[1], clampf(u, 0.0, 1.0))
		1:
			return limb.joints[1].lerp(limb.joints[2], clampf(u, 0.0, 1.0))
		_:
			return limb.joints[2]


func limb_bind_solid(key: String, segment: int) -> float:
	return anatomy.tissue.limb_solid(key, clampi(segment, 0, 2))


func _limb_by_key(key: String) -> Limb:
	if gait == null:
		return null
	for limb in gait.limbs:
		if limb.key == key:
			return limb
	return null


func _width_at(t: float) -> float:
	var n: int = body.widths.size()
	if n < 2:
		return body.widths[0] if n == 1 else 1.0
	var s: float = clampf(t, 0.0, 1.0) * float(n - 1)
	var i: int = clampi(int(floor(s)), 0, n - 2)
	return lerpf(body.widths[i], body.widths[i + 1], s - float(i))


## The two semi-axes of the arc the teeth are set in: how far the mouth reaches
## ahead of the head, and how wide it is across it.
##
## They differ because a mouth is a snout, not a hole: it projects forward past
## the skull while its corners stay inside the head they are cut into. The
## forward reach is `bite_radius`, capped against the skull — a mouth may be
## considerably longer than the animal is wide, but past that it stops being a
## mouth and becomes a bite volume floating in front of a face, which is exactly
## what this replaced.
func jaw_axes() -> Vector2:
	var skull: float = body.head_radius if body != null else 10.0
	return Vector2(minf(params.bite_radius * size_scale, skull * MAX_GAPE_RATIO), skull)


## One representative size for the mouth, where a single radius is wanted — how
## much flesh the jaws have hold of, how far they can reach for a new hold.
func gape_radius() -> float:
	var axes: Vector2 = jaw_axes()
	return Dentition.arc_scale(axes.x, axes.y)


## Where these jaws hold flesh: how far from the centre of its own mouthful this
## mouth's teeth actually close on something. The rest length of any grip it
## takes — see Dentition.hold_radius, which reads it off the arch and the crowns
## rather than off whatever gap a strike happened to land at.
func jaw_hold() -> float:
	if dentition == null:
		dentition = Dentition.grow(params)
	var axes: Vector2 = jaw_axes()
	return dentition.hold_radius(axes.x, axes.y)


## The mouth, in world space — where a bite lands, and where a grip holds from.
##
## This is the centre of the mouthful the teeth take, not a point projected
## ahead of the snout: the head is *on* what it bites. That is the whole reason
## a strike now reads as the head arriving over the flesh it opens, and the
## reason `bite_reach` is the distance the head is thrown rather than a distance
## the damage is thrown for it.
##
## Built from the live spine rather than the cached head frame for the same
## reason `body_point` is: a contact or a grip may already have translated the
## creature this tick, and jaws a translation behind the body would drag their
## own hold along with them.
func jaw_point() -> Vector2:
	if spine == null or body == null or body.widths.is_empty():
		return head_pos
	var bias: float = dentition.centroid if dentition != null else 0.6
	return spine.points[0] + spine.forwards[0] * (jaw_axes().x * bias)


## Head-first collision test used by the food field.
func mouth_radius() -> float:
	return (body.head_radius if body != null else 10.0) + 6.0


func body_length() -> float:
	return spine.arc_length() if spine != null else 100.0


## How long one segment of this body is being held at *right now*.
##
## `segment_length` is the animal's own rest length and is still the whole of what
## it is built from — but a back that folds and extends is a back whose rest
## length is not the same on every tick, and the spine is solved to this rather
## than to the parameter. Exposed because it is an invariant several things check
## against: the chain's segments must be exactly this long after a solve, and a
## check against the parameter instead would be measuring the gallop and calling
## it a stretched body.
##
## Identical to the parameter on anything not working its girdles as pairs, which
## is every animal at a walk and every gait a stiff-backed one has — see
## Gait.gather, which is nothing at all under an alternating footfall.
##
## Stored rather than recomputed on demand, and that is the difference between an
## invariant and a near miss. The gait re-measures the fold *after* the spine has
## been solved, so a body asked what its rest length is at the end of a tick would
## answer with the length it is about to be held at next tick — and on a galloping
## animal the two differ by several percent, which reads as a chain that stretches
## and is nothing of the kind.
func segment_rest() -> float:
	return _segment_rest if _segment_rest > 0.0 else params.segment_length * size_scale


func feed(amount: int = 1) -> void:
	food_eaten += amount
	ate_food.emit(food_eaten)


# ------------------------------------------------------------------- aim ----

## Points this creature at something. The habitat resolves a cursor into one
## target — a place, a height, and the exact structure of whichever body is there
## — and hands it over; what the animal makes of it is everything below.
##
## Null clears it, which is what happens when the pointer is over nothing and
## what every line downstream treats as "no target", behaving exactly as this file
## did before it could be aimed.
func aim_at(target: Reticle.Pick) -> void:
	aim = target
	aim_reach = null if target == null else Reach.solve(self, target.at, target.band, terrain())


## Whether the jaws could be got onto whatever this creature is pointed at.
## True with nothing selected, because an animal with no target has not been
## refused anything — a bite thrown at nothing in particular is still a bite.
func can_reach_aim() -> bool:
	return aim_reach == null or aim_reach.possible


## One tick of reaching for it.
##
## Two things happen and only the second is visible. The reach is re-solved,
## because both the animal and its target are moving and an answer from last tick
## is an answer about somewhere neither of them is. And the crouch is eased toward
## whatever that answer asks for — which is the whole of the body adjustment, and
## is deliberately one number: the legs fold by this much, and the stance, the
## height, the bands and the drawn picture are all consequences of a shorter leg
## rather than four separate things being animated to agree.
##
## Nothing here is an animation and nothing here is keyed to biting. An animal
## pointed at something on the floor lowers itself toward it and stays lowered
## while it is pointed there, exactly as one browsing does; the bite, if it comes,
## is thrown from wherever that left it.
func _update_aim(delta: float) -> void:
	var wanted: float = 0.0
	if aim != null:
		aim_reach = Reach.solve(self, aim.at, aim.band, terrain())
		# Only for a target it can actually get to. Folding up under something out
		# of reach is a body straining at nothing, and a creature that crouched
		# toward the sky would be the same mistake upside down.
		if aim_reach.possible:
			wanted = aim_reach.crouch
	else:
		aim_reach = null
	# Close control asks for the whole of the fold, and the deeper of the two
	# demands wins rather than the later one: an animal creeping toward something
	# on the floor is already down at the height it would have crouched to reach
	# it, and one creeping toward something at chest height does not stand back up
	# to look at it. Nothing is added — the same single number is being spent,
	# which is why the stance, the height and the bands stay in agreement.
	if is_stalking():
		wanted = maxf(wanted, 1.0)
	# A body with nothing under it has nothing to fold against, and one whose legs
	# are already carrying it as low as they go has nothing left to give.
	if elevation.is_airborne() or not alive:
		wanted = 0.0
	crouch = lerpf(crouch, wanted, 1.0 - exp(-CROUCH_RESPONSE * delta))


## Queues one bite for the next solved physics pose. Clicks during an active
## strike or recovery are deliberately discarded rather than buffered, so one
## click always means at most one attack even when cooldown is tuned shorter
## than the lunge animation.
##
## Never refused for being out of reach, and that is a deliberate reversal. The
## body used to decline the strike outright when `Reach` said the target was
## above it, below it or behind a rock — which is the correct *fact* delivered as
## the wrong *behaviour*: a click that does nothing at all is indistinguishable
## from a click the game did not receive, and an animal that has misjudged a
## lunge is a thing that happens. So the strike is always thrown, and what it
## then meets is decided where it has always been decided — in the world, by the
## jaws arriving somewhere and there being nothing in them. A ground-level lizard
## told to bite the top of an elephant snaps at the air under its belly.
##
## The reach is not wasted for that. It is what the reticle draws hollow, what
## the body crouches toward and what the marker is brought in to — see
## `Reticle.resolve` — so "you cannot get to that" is said before the button
## rather than by swallowing it.
func request_bite(_aim_world: Vector2) -> bool:
	if not alive:
		return false
	if bite_cooldown_remaining > 0.0 or _bite_requested or bite_time >= 0.0:
		return false
	_bite_requested = true
	return true


func can_bite() -> bool:
	return bite_cooldown_remaining <= 0.0 and not _bite_requested and bite_time < 0.0


## Tracks the physical button independently from the one-shot bite request.
## Releasing a connected clamp does not cancel the bite; it simply lets the
## existing animation continue through recovery from the apex.
##
## With a hold in force the button means something else, and this is where the
## difference lives. Jaws already on flesh do not spring open the instant the
## button rises — they part, and a press taken while they are parting closes them
## again on the same bind. So a held button is a grip, working the button is
## chewing, and letting go is letting go.
func set_bite_held(held: bool) -> void:
	# A carcass's jaws are as limp as the rest of it. It can be bitten and held;
	# it cannot bite or hold.
	if not alive:
		return
	if held:
		bite_held = true
		if _jaws_shut() and _regrasp_remaining > 0.0:
			_regrasp_remaining = 0.0
			_chew_requested = true
		return
	bite_held = false
	if _jaws_shut():
		_regrasp_remaining = GRIP_REGRASP_WINDOW
		return
	_regrasp_remaining = 0.0
	bite_latched = false
	_chew_requested = false
	grip = null
	_grip_lockout = false


## Whether these jaws are currently shut on anything at all — an animal or a piece
## of meat. The button means the same thing in both cases, which is why they are
## asked as one question: held is holding on, working it is working the jaws, and
## letting go is letting go.
func _jaws_shut() -> bool:
	return (grip != null and grip.is_alive()) or mouthful != null


## Whether these jaws are shut on something. True through the parting window as
## well as while the button is down: the hold has not ended until the jaws have
## actually opened, and everything downstream — the clamped head, the suspended
## contact pass, the tether — has to agree about when that is.
func is_bite_latched() -> bool:
	return bite_latched and _jaws_shut() and (bite_held or _regrasp_remaining > 0.0)


## Whether something else has hold of this creature. Refreshed once per tick, so
## a reader outside the simulation sees the same answer the tick did.
func is_being_gripped() -> bool:
	return _held_by != null and _held_by.is_alive()


# ------------------------------------------------------------------ grip ----

## Takes up this creature's own share of the slack in whatever jaws are involved
## with it — its own, or somebody else's closed on it.
##
## Deliberately the same shape as the contact pass beside it: measure the current
## error, correct this creature by the fraction of it its mass makes it
## responsible for, and never write anything to the other party. Living bodies
## translate as a whole; carcasses accept the correction at the held anatomical
## point. Both sides run this against the same grip, so between them the slack is
## taken up once.
##
## Dragging is not implemented anywhere. It is what this does when the masses are
## uneven: the light body gets nearly the whole correction and is towed along
## behind jaws that barely move.
func _resolve_grip() -> void:
	if spine == null or body == null:
		return
	if grip != null:
		if not grip.is_alive():
			_release_grip()
		else:
			# Measured before either party moves, and only by the owner, so the load
			# the jaws are carrying is one number from one source rather than two
			# halves of a correction added up out of order.
			grip.tension = grip.slack().length()
			_take_up_slack(grip, grip.victim, 1.0)
			_take_up_height(grip.victim)
	if _held_by != null and _held_by.is_alive():
		_take_up_slack(_held_by, _held_by.biter, -1.0)
		_take_up_height(_held_by.biter)


## The vertical half of the same tether.
##
## A set of jaws is the only thing in this world that physically joins two bodies,
## so it is the only thing that can hold one at a height it did not choose. That
## makes it the answer to the obvious hole in a leap: a creature already in
## something's mouth cannot jump away from it, and a flier that gets hold of
## something on the ground has to carry it rather than leave it behind.
##
## Split by mass through exactly the same share the horizontal correction uses,
## so the light party does nearly all of the moving and neither writes into the
## other. Two bodies at the same height are joined by a slack tether and nothing
## happens at all.
func _take_up_height(other: Creature) -> void:
	if other == null:
		return
	elevation.tether(other.elevation.height, _contact_share(other))


## Whether a set of jaws — either creature's — currently joins this pair.
func _is_joined_to(other: Creature) -> bool:
	if grip != null and grip.victim == other:
		return true
	return _held_by != null and _held_by.biter == other


## `direction` is +1 for the biter, whose jaws move onto the flesh, and -1 for the
## victim, whose flesh is pulled back into the jaws.
func _take_up_slack(held: Grip, other: Creature, direction: float) -> void:
	var slack: Vector2 = held.slack()
	if slack == Vector2.ZERO:
		return
	var offset: Vector2 = slack.limit_length(MAX_CONTACT_PUSH) \
		* _contact_share(other) * direction
	if alive:
		_translate_contact(offset)
	else:
		_drag_grip(held, offset)


## Applies a tether correction to the anatomical structure in the jaws. Torso
## holds enter the free spine directly. Limb holds first articulate the particles
## on that bone; only the socket's share and any pull beyond the chain's maximum
## reach pass into the spine, so a foot folds and straightens before it tows the
## whole carcass.
func _drag_grip(held: Grip, offset: Vector2) -> void:
	if not held.holds_limb() or ragdoll == null or gait == null:
		_drag_at(held.anchor(), offset)
		return
	# Only a limb that is being carried has particles to articulate. One the gait
	# is still walking is placed from scratch every tick, so a pull applied to its
	# joints would be overwritten before it was ever drawn — the tether has to act
	# on the body it is really pulling.
	var limb: Limb = _limb_by_key(held.limb_key)
	if limb == null or not limb.carried:
		_drag_at(held.anchor(), offset)
		return

	var socket_share: Vector2 = ragdoll.haul(
		gait.limbs, held.limb_key, held.limb_segment, held.limb_u, offset)
	if socket_share != Vector2.ZERO:
		_drag_at(limb.joints[0], socket_share)

	var max_reach: float
	match held.limb_segment:
		0:
			max_reach = limb.lengths[0] * held.limb_u
		1:
			max_reach = limb.lengths[0] + limb.lengths[1] * held.limb_u
		_:
			# Bone units, like the two above it: the chain the hold is measured
			# along is the real limb, not the shortened one the picture shows.
			max_reach = limb.anatomical_length
	var reach: Vector2 = held.anchor() - limb.joints[0]
	var distance: float = reach.length()
	if distance > max_reach and distance > 0.0001:
		_drag_at(limb.joints[0], reach * ((distance - max_reach) / distance))


## Takes up a pull on a carcass where the pull actually acts, and lets the free
## chain carry it the rest of the way.
##
## A living creature answers the same correction with `_translate_contact`, which
## moves the whole body as one rigid piece. That is not a stylistic choice there:
## its head is placed by input and re-pinned every tick, so a correction applied
## halfway down the spine is unpicked by the very next solve and the disagreement
## comes back out as flailing. Nothing re-pins this one — every point of it is
## simulated — so the honest thing is also the available one, and a body dragged
## by the jaws trails behind them instead of sliding after them in formation.
##
## Feathered over the neighbouring stations rather than applied to the single
## nearest particle, so it enters the chain as a haul on a region of flesh; a tug
## on one point is something the distance constraint then spends the next several
## ticks undoing. It is deliberately *not* normalised — the station the jaws are
## on takes the whole correction, because that is the one the tether measures its
## slack from, and the rest of the body is brought along by the constraint solve
## over the ticks that follow. That lag is the trailing.
func _drag_at(at: Vector2, offset: Vector2) -> void:
	if offset == Vector2.ZERO or spine == null:
		return
	var n: int = spine.size()
	var nearest: int = 0
	var best: float = INF
	for i in n:
		var d: float = spine.points[i].distance_squared_to(at)
		if d < best:
			best = d
			nearest = i
	for i in n:
		var weight: float = pow(DRAG_FALLOFF, absf(float(i - nearest)))
		if weight < 0.02:
			continue
		spine.haul(i, offset * weight)
	head_pos = spine.points[0]


## The consequences of the hold, resolved against the pose that has just been
## solved: what the jaws are carrying, whether they can still carry it, and
## whether they have come round to close again.
func _advance_grip(delta: float) -> void:
	if grip == null:
		return
	if not grip.is_alive() or not (bite_held or _regrasp_remaining > 0.0):
		_release_grip()
		return

	# Load, in the same currency as bite force. Two terms, and only two.
	#
	# Reduced mass is what a tether between two free bodies actually has to
	# restrain. It is dominated by the *lighter* of the pair, which is why holding
	# something small is easy however hard it fights, why being the small one and
	# holding something large is where jaws come off, and why a real contest only
	# happens between near-equals. Its root rather than itself, because the jaws
	# get a proportionally bigger hold of a bigger body at the same time as the
	# body becomes harder to hold: purchase grows with the flesh in them.
	#
	# Separation speed is how fast the two are actually coming apart — measured,
	# not intended, so a creature towed along quietly loads the jaws with nothing
	# and one thrashing on the spot loads them with everything. This is why a
	# grip is escaped by turning: heading is the one thing a load never slows.
	var mine: float = physique.mass
	var theirs: float = grip.victim.physique.mass
	var purchase: float = sqrt(mine * theirs / maxf(mine + theirs, 0.0001))
	var separation_speed: float = grip.tension / maxf(delta, 0.0001)
	var instant: float = purchase * separation_speed / GRIP_LOAD_REFERENCE
	grip.load = lerpf(grip.load, instant, 1.0 - exp(-GRIP_LOAD_RESPONSE * delta))

	# The mouthful the jaws were holding has come away. They take hold of the
	# surface it left behind rather than opening, and only let go when there is
	# nothing within them to hold at all.
	if grip.bind_is_hollow() and not _regrip():
		_release_grip(true)
		return

	# Contact, asked every tick and by exactly the line that decided there was a
	# hold in the first place. The tether keeps the flesh in the mouth, but it
	# takes up slack at a bounded rate and splits what it takes by mass, so a
	# heave sharp enough — or a victim heavy enough to drag the biter rather than
	# be drawn in — outruns it. When the flesh gets out of the jaws the latch is
	# over: nothing was overpowered and nothing tore, the teeth simply came off,
	# and it is the third way a hold ends because it is the third thing that can
	# physically happen to one.
	if not grip.is_holding():
		_release_grip(true)
		return

	if grip.load > physique.bite_force:
		_tear_free()
		return

	# A chew: the jaws opening and shutting once on what they are already holding.
	# It is an action taken, never a clock — holding on is holding on, and the only
	# thing that turns a hold into a wound by itself is the pull below. Routed
	# through the ordinary world resolver, so a chew sheds meat, picks its target
	# and reports a miss exactly the way the opening bite does.
	if _chew_requested:
		_chew_requested = false
		if _chew_cooldown <= 0.0:
			_chew_cooldown = maxf(params.chew_interval, 0.05)
			bite_started.emit(bite_mark(jaw_point(), bite_depth()))

	# The flesh's own half of the contest — see the tearing constants above. The
	# pull either sits inside what the tissue will take, in which case it holds
	# indefinitely, or it works it: drawing the meat out of the body, and given
	# long enough parting it. Stress is spent as fast as it is earned once the
	# struggling stops, so this is a consequence of force over time and never of
	# the button being down.
	var overload: float = grip.load / maxf(grip.tissue_strength(), 0.0001)
	if overload > TEAR_YIELD:
		grip.stress = minf(grip.stress + (overload - TEAR_YIELD) * delta / TEAR_WORK, 1.0)
	else:
		grip.stress = maxf(grip.stress - TEAR_RELAX * delta, 0.0)
	if grip.stress >= 1.0:
		_tear_out()


# ------------------------------------------------------------------ eating ----

## Carries, chews and swallows whatever piece of meat is in the jaws.
##
## The three are not three things here. Carrying is placing a piece the jaws have
## hold of; chewing is closing them on it, which goes down the ordinary world bite
## path and therefore erodes it and sheds meat exactly as closing on anything does;
## and swallowing is what a chew *is* once what is left will fit. Which of the two
## a chew turns out to be is one comparison, made below, and it is the only place
## in the whole feature where eating decides anything.
func _advance_mouthful(delta: float) -> void:
	if mouthful == null:
		return
	mouthful.advance(delta)
	var part: CarrionField.Part = mouthful.part
	# Meat is possession, so it is lost by being taken rather than by being pulled
	# away: whoever has it in their jaws has it, and these jaws no longer do.
	if part == null or part.is_spent() or part.carrier != self:
		_drop_mouthful()
		return
	if mouthful.is_down():
		mouthful = null
		bite_latched = false
		_regrasp_remaining = 0.0
		part.release()
		swallowed.emit(part)
		return
	# A swallow finishes whatever the button does. Opening your mouth halfway
	# through is not a way to un-eat something.
	if mouthful.going_down < 0.0 and not (bite_held or _regrasp_remaining > 0.0):
		_drop_mouthful()
		return

	_place_mouthful(delta)
	if mouthful.going_down >= 0.0:
		return
	if not _chew_requested:
		return
	_chew_requested = false
	if _chew_cooldown > 0.0:
		return
	_chew_cooldown = maxf(params.chew_interval, 0.05)
	_work_mouthful()


## Puts the piece where the jaws have it.
##
## Nothing here is an animation. The target is the jaw point, drawn back along the
## mouth's own axis by however far the mouthful has been worked in — a jolt while
## it is being chewed, the length of a throat while it is going down — and the
## piece is moved toward it by as much of the pull as its weight lets through. A
## creature that can lift what it is holding is carrying it; one that cannot is
## dragging it; and the difference between those is the mass in the divisor.
func _place_mouthful(delta: float) -> void:
	if body == null or spine == null or spine.size() == 0:
		return
	var fwd: Vector2 = spine.forwards[0]
	var jaw: Vector2 = jaw_point() + fwd * mouthful.draw_in(body.head_radius)
	var load: float = mouthful.part.mass() * HAUL_COST
	var grasp: float = physique.strength / maxf(physique.strength + load, 0.0001)
	# Where those jaws are in the vertical, so a piece light enough to be lifted is
	# carried at mouth height and a piece that is not stays on the floor being
	# dragged over it. Both come out of the same `grasp` the horizontal haul uses —
	# see CarrionField.Part.carry — so nothing here chooses between them.
	mouthful.part.carry(mouthful.hold, jaw, grasp,
		gape_radius() + CarrionField.TETHER_SLACK, delta,
		stature.head_height + stature.elevation,
		_surface_under_foot(mouthful.part.pos, 0.0).x)


## One closing of the jaws on what they are already holding.
##
## Either the piece goes down or it is worked on, and the test is the only thing
## separating an Elephant taking a Cat's leg whole from a Cat gnawing at an
## Elephant's for a minute: how far the meat reaches from the hold, against how
## much mouth there is. Food size, food shape, mouth size and bite position all
## arrive in that one comparison, and none of them is named in it.
##
## A chew that does not swallow goes out through the same signal a strike does, so
## the world resolves it, erodes the piece and scatters what came off with no idea
## that it was chewing rather than biting.
func _work_mouthful() -> void:
	var gape: float = gape_radius()
	if mouthful.fits(gape):
		mouthful.begin_swallow()
		return
	bite_started.emit(bite_mark(mouthful.part.to_world(mouthful.hold), bite_depth()))
	# The world has resolved that closing by the time the emit returns, so what
	# follows is the jaws finding their new hold in the crater they just made:
	# onto tissue that is still there, and a step further into the piece. Working a
	# mouthful in is what makes a long piece eaten end-first rather than nibbled
	# forever at the place it was first grabbed.
	if mouthful == null:
		return
	mouthful.chew()
	mouthful.reseat()
	mouthful.work_in(gape)


func _drop_mouthful() -> void:
	if mouthful == null:
		return
	if mouthful.part != null and mouthful.part.carrier == self:
		mouthful.part.release()
	mouthful = null
	bite_latched = false
	_regrasp_remaining = 0.0
	_chew_requested = false


## Closes the jaws on a piece of meat and records where on it they closed.
##
## The hold is re-seated onto real tissue immediately, because jaws that shut over
## the hole a previous mouthful left would be holding a point in the air — and
## every reading below is measured from the hold.
func _take_mouthful(meat: CarrionField.Part) -> void:
	var taken := Mouthful.new()
	taken.part = meat
	taken.hold = meat.to_local(jaw_point())
	taken.reseat()
	meat.hold_by(self)
	mouthful = taken
	bite_latched = true
	# The strike that took hold was itself one closing of these jaws, so the next
	# one waits out the same interval a chew does.
	_chew_cooldown = maxf(params.chew_interval, 0.05)


## Hands the body the mouthful currently going down it, as a place and a size.
##
## Read off the swallow rather than tracked alongside it: where the piece has got
## to is how far through the swallow it is, and how much it distends the throat is
## how much bigger than that throat it is. A piece that fits comfortably makes no
## bulge at all, which is correct and needed no exception.
func _read_swallow() -> void:
	if body == null:
		return
	body.swallow_at = 0.0
	body.swallow_size = 0.0
	if mouthful == null:
		return
	var down: float = mouthful.gullet()
	if down <= 0.0:
		return
	body.swallow_at = SWALLOW_TRAVEL * down
	var girth: float = mouthful.reach() / maxf(body.head_radius, 0.001)
	# Rises and subsides as the piece passes, because that is what is happening:
	# the tissue is stretched around it and closes again behind it.
	body.swallow_size = clampf(girth, 0.0, 1.0) * SWALLOW_SWELL * sin(PI * down)


## Hands the body whatever has hold of it, as a place, a direction and a distance.
##
## The victim's side of a grip, and it is read here for the same reason the grip
## itself is read here rather than written by the biter: nothing in this file ever
## writes into another creature's state. The biter measures the pull, this animal
## looks up who has hold of it and asks how far its own flesh will come.
##
## What is handed over is the mouth's position rather than the bind's, because
## flesh is drawn *toward the jaws* — the bind is where the jaws have hold, which
## is the flesh that is doing the moving, not the place it is moving to.
func _read_hold() -> void:
	if body == null:
		return
	body.held_by = 0.0
	if _held_by == null or not _held_by.is_alive():
		return
	# A hold on a limb pulls the limb, and a limb is placed by the gait and the
	# ragdoll rather than by the silhouette — see `_drag_grip`, which articulates
	# it there. Only a hold on the trunk deforms the trunk.
	if _held_by.holds_limb():
		return
	body.held_at = clampf(_held_by.bind.x, 0.0, 1.0)
	body.held_side = clampf(_held_by.bind.y, -1.0, 1.0)
	body.held_to = _held_by.biter.jaw_point()
	body.held_by = _held_by.drawn()


## How hard one closing of these jaws drives, in the tissue lattice's hit points.
##
## Full `bite_damage` for a free strike, which is what every bite in the game was
## until now. A latched one spends part of its force simply staying shut, so what
## is left to cut with falls away as the load rises.
##
## This is force at the jaws, not depth in the flesh. What it becomes once it
## reaches tissue is the dentition's business: the same number spread over a
## crowded mouth of blunt cusps barely breaks skin, and concentrated into a few
## keen points goes to the bone.
func bite_depth() -> float:
	var strain: float = grip.strain() if grip != null and grip.is_alive() else 0.0
	return params.bite_damage \
		* clampf(1.0 - strain * CHEW_STRAIN_COST, CHEW_MIN_DEPTH, 1.0)


## The mark these jaws leave closing on a place, with the mouthful landing on
## `at`. The arc of teeth is placed *around* that point rather than starting
## from it, which is what puts the head over the damage instead of behind it.
func bite_mark(at: Vector2, depth: float) -> BiteMark:
	if dentition == null:
		dentition = Dentition.grow(params)
	var fwd: Vector2 = spine.forwards[0] if spine != null and spine.size() > 0 \
		else head_look_dir
	var perp := Vector2(-fwd.y, fwd.x)
	var axes: Vector2 = jaw_axes()
	var mark: BiteMark = dentition.stamp(
		at - fwd * (dentition.centroid * axes.x), fwd, perp, axes.x, axes.y, depth)
	# How high these jaws are being brought to bear, carried with the footprint
	# they leave. Everything downstream — which creature the world picks, which of
	# its structures the query can even see, which cells the lattice lets go —
	# reads it off the mark rather than coming back to ask the animal.
	mark.reach = stature.bite
	return mark


## Re-seats jaws whose mouthful has come away, on the surviving flesh inside
## them. Returns false when there is none, which is the one way chewing ends by
## succeeding.
##
## Without this a strong bite would *lose* its grip faster than a weak one: the
## better it chews, the sooner the cell it was bound to is gone. Re-seating is
## what turns a latch into chewing in — the wound deepens under jaws that stay
## shut, rather than the hold ending the moment it works. It is routed through
## the same anatomy query the world bites with, so what the jaws can find hold of
## is exactly what they could find to bite.
##
## The nearest sound flesh, and nearest is the operative word: the new hold
## becomes the tether's rest length, so jaws that reached for the *best* flesh
## within their gape rather than the closest would leave themselves holding
## something an entire gape away — a leash rather than a bite, which the next
## mouthful would then be taken at the far end of.
func _regrip() -> bool:
	if grip == null or not grip.is_alive():
		return false
	var jaw: Vector2 = jaw_point()
	# The crater the last mouthful left, plus however far the flesh had drawn out
	# of the body before it parted — the jaws finished that tear at the far end of
	# their own stretch, so that is where they are searching from.
	var reach: float = gape_radius() * GRIP_GAPE + Grip.MAX_STRETCH
	var victim: Creature = grip.victim
	var best := Vector2.ZERO
	var best_distance: float = INF
	var best_hold: float = 0.0
	for k in REGRIP_STATIONS + 1:
		var t: float = float(k) / float(REGRIP_STATIONS)
		for lateral in REGRIP_LATERALS:
			var candidate := Vector2(t, lateral)
			# The same two questions the hold itself asks — does the body still
			# reach here, and is there anything in the cell — so jaws can never
			# re-seat onto a place they would immediately report as empty.
			if victim.bind_solid(candidate) <= 0.0:
				continue
			var hold: float = victim.bind_hp(candidate)
			if hold <= 0.0:
				continue
			var d: float = jaw.distance_to(victim.body_point(candidate))
			if d < best_distance:
				best_hold = hold
				best_distance = d
				best = candidate
	if best_hold <= 0.0 or best_distance > reach:
		return false
	grip.bind_body(best)
	# The tether's rest length is the jaws, not the search — the same number a
	# fresh grip takes, because it is the same mouth closing on the same kind of
	# flesh. Anything the search had to reach for is hauled in rather than
	# accepted where it lies; recording the distance instead would leave the hold
	# a leash, one the next mouthful would be taken at the far end of and the one
	# after that further out again.
	grip.rest_length = jaw_hold() + GRIP_SLACK
	return true


## Jaws pulled off the flesh they were holding. They do not simply open — they
## take a mouthful with them, resolved through the same world path as any other
## bite so a tear sheds meat and opens tissue like one.
func _tear_free() -> void:
	var at: Vector2 = grip.anchor()
	# Released first, so what these jaws close on the way off is priced as the
	# free strike it now is rather than as a chew still spending force on a hold
	# that no longer exists.
	_release_grip(true)
	bite_started.emit(bite_mark(at, bite_depth()))


## The flesh gave before the jaws did: the piece they were holding parts from the
## body and comes away in them.
##
## Centred on the anchor rather than on the jaws, because what is being removed is
## the meat that tore and not the volume the teeth occupy — under load the two
## have visibly drawn apart, which is the whole point of the stretch. Resolved
## through the same world path as every other closing of these jaws so a tear
## sheds, damages and reports identically.
##
## Its mark is the one that is not a set of teeth. Nothing is being cut here —
## meat the jaws already had hold of is parting from the body — so it comes away
## as one piece the width of the mouth, at a depth measured in flesh rather than
## in bite force, and the dentition has no say in either.
##
## The jaws stay shut afterwards. They are re-seated on whatever is left inside
## them, exactly as they are when a mouthful is chewed away, so tearing deepens a
## wound instead of ending the hold that made it.
func _tear_out() -> void:
	grip.stress = 0.0
	var fwd: Vector2 = spine.forwards[0] if spine != null and spine.size() > 0 \
		else head_look_dir
	var at: Vector2 = grip.anchor()
	bite_started.emit(BiteMark.mouthful(
		at, fwd, gape_radius() * MOUTHFUL_SPAN, TEAR_DEPTH))
	if grip != null and grip.bind_is_hollow() and not _regrip():
		_release_grip(true)


## `lost` marks a grip that ended by itself rather than by the button coming up.
## Jaws that were pulled off cannot silently take hold again while the button is
## still down: a bite is one press, and that has to stay true of the hold as well
## as of the strike.
func _release_grip(lost: bool = false) -> void:
	grip = null
	bite_latched = false
	_regrasp_remaining = 0.0
	_chew_requested = false
	_grip_lockout = lost


## The grip somebody else has on this creature, or null. Walks the creature group
## the same way the contact pass does, because the alternative — the biter
## registering itself on its victim — is precisely the cross-creature write the
## whole tick order is built to avoid.
func _find_grip_on_self() -> Grip:
	if not is_inside_tree():
		return null
	for node in get_tree().get_nodes_in_group("creatures"):
		var other := node as Creature
		if other == null or other == self or other.grip == null:
			continue
		if other.grip.victim == self and other.grip.is_alive():
			return other.grip
	return null


## How much of its own locomotion this creature keeps with something on the other
## end of a set of jaws — its own jaws, or the ones holding it.
##
## Force over load, in the currency the physique already works in: a creature can
## pull with `strength`, and a grip adds the whole of another body to what that
## strength has to move. Because strength goes as mass^(2/3) while the load goes
## as mass, this is the square-cube law arriving exactly where it matters — a
## Elephant tows a Cat without noticing, a Cat latched onto an Elephant can barely
## walk, and neither case needed a rule written for it.
##
## `speed_norm` is deliberately still measured against the *unhauled* top speed,
## so a creature straining against a load takes short shuffling strides and its
## undulation dies down. Effort reads off the gait for free.
func _haul_factor() -> float:
	var towed: float = 0.0
	if grip != null and grip.is_alive():
		towed += grip.victim.physique.mass
	if _held_by != null and _held_by.is_alive():
		towed += _held_by.biter.physique.mass
	# Meat weighs what it weighs. A severed thigh off something large is a real
	# load, and the same rule that makes towing an Elephant hard makes dragging one's
	# leg away hard — because it is the same rule and the same currency.
	if mouthful != null and mouthful.part != null:
		towed += mouthful.part.mass()
	if towed <= 0.0:
		return 1.0
	return clampf(physique.strength / (physique.strength + towed * HAUL_COST),
		HAUL_FLOOR, 1.0)


## Pure query used by the world combat resolver so only the closest creature is
## damaged when several procedural bodies overlap the same bite volume.
func query_bite(center: Vector2, radius: float,
		reach: Vector2 = Stature.UNBOUNDED) -> AnatomyState.Hit:
	return anatomy.hit_test(self, center, radius, reach)


## Erodes this creature's tissue lattice wherever the bite mark covers it, and
## hands whatever came loose to the world.
func apply_bite(mark: BiteMark) -> float:
	var shed: Array = []
	var removed: float = anatomy.apply_bite(mark, shed)
	if removed <= 0.0:
		return 0.0
	tissue_damaged.emit(anatomy.tissue.integrity())
	if not shed.is_empty():
		tissue_shed.emit(shed, mark.center)
	return removed


## Called by the world after it has selected and damaged (or failed to find) a
## target, so the jaws know what they closed on.
##
## Also where a hold begins and ends, because a hold is exactly "the jaws found
## flesh and the button is still down". A chew routes through here too: the grip
## already knows its victim, so what the resolver adds is the one thing it cannot
## know for itself — whether there was still anything there to bite.
## `meat` is set when what the jaws reached furthest into was a severed part rather
## than an animal. Meat is taken rather than gripped: there is nothing to wrestle,
## so the whole of closing on it is holding it.
func resolve_bite(connected: bool, target: Creature = null, hit: AnatomyState.Hit = null,
		meat: CarrionField.Part = null) -> void:
	bite_connected = connected
	if grip != null or mouthful != null:
		# A chew that closes on nothing is a chew that closes on nothing, and the
		# same goes for a tear. Neither ends the hold: what the jaws have hold of is
		# the bind, and the only things that end that are the flesh under it being
		# gone with nothing left to re-seat on, the load pulling them off, and the
		# jaws being given long enough to open.
		return
	if meat != null:
		if bite_held and not _grip_lockout:
			_take_mouthful(meat)
		else:
			bite_latched = false
		return
	if not (connected and bite_held) or target == null or _grip_lockout:
		bite_latched = false
		return
	_form_grip(target, hit)
	# ...and then whether that is a hold at all, which is the two anatomies'
	# business rather than the resolver's — see Grip.is_holding, and note that it
	# is the same line asked of the same grip every tick afterwards. Jaws that
	# closed on a place they cannot get teeth into have still done their damage on
	# the way through; what they do not get is a latch.
	#
	# Asked here rather than inside `_form_grip` because the two are different
	# jobs: forming is recording which structure the jaws shut on, and that is
	# also what a carcass's limb needs done to it from outside. Whether the mouth
	# has anything is a question about this strike.
	if grip != null and not grip.is_holding():
		_release_grip()


## Closes the jaws on a specific creature and records where.
##
## The bind comes off the hit's own surface point when there is one, because the
## hit test is the world's answer to *what did these jaws close on* — it already
## knows which structure was reached and has already discounted tissue that is no
## longer there. The jaw centre is only the fallback.
func _form_grip(target: Creature, hit: AnatomyState.Hit) -> void:
	if target == null or target.spine == null or target.body == null:
		return
	var jaw: Vector2 = jaw_point()
	var held := Grip.new()
	held.biter = self
	held.victim = target
	if hit != null and hit.kind == AnatomyState.LIMB:
		held.bind_limb(hit.limb_key, hit.limb_segment, hit.limb_u)
	else:
		held.bind_body(target.body_bind(hit.world_point if hit != null else jaw))
	# Rest length is where these jaws hold flesh, and that is a fact about the
	# mouth rather than about the moment — see Dentition.hold_radius. It used to
	# be the gap the strike happened to close at, which is the whole of the hole
	# it left: the bite query reaches a full gape, so a hit found at arm's length
	# froze that arm's length in as the distance the tether would then defend, and
	# the teeth hung off the wound by most of a mouth for as long as the hold
	# lasted. Set to the mouth's own hold radius the tether does the opposite —
	# it draws the flesh into the jaws over the next tick or two and keeps it
	# there, which is what closing on something means.
	#
	# It cannot tow the biter into its victim, because a tether is a rope: it
	# takes up slack and never pushes. Two bodies already closer than this are
	# left exactly where they are.
	held.rest_length = jaw_hold() + GRIP_SLACK
	grip = held
	bite_latched = true
	# The strike that took hold was itself one closing of these jaws, so the next
	# one waits out the same interval a chew does.
	_chew_cooldown = maxf(params.chew_interval, 0.05)


## The hit frame. Announces the jaw volume at full extension and lets the world
## resolve it against every creature in it.
func _strike() -> void:
	if body == null:
		return
	# The body is head-driven, so the truthful jaw direction is the solved head
	# frame; allowing the click vector to bypass it would make the creature bite
	# sideways before its visible head has reached the cursor.
	bite_started.emit(bite_mark(jaw_point(), bite_depth()))
