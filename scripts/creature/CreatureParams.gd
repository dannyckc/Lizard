## All tunable numbers for the creature, in one place.
##
## This is a Resource so it can be edited in the Inspector, saved as a .tres
## preset, and swapped at runtime. SCHEMA below mirrors the exported properties
## and is what the in-game creation menu builds its sliders from — add a property
## here plus one SCHEMA row and it shows up in the UI automatically.
class_name CreatureParams
extends Resource

# ---------------------------------------------------------------- spine ----
@export_group("Spine")
## Number of particles in the spine chain. Point 0 is the head (the driver).
@export_range(6, 28, 1) var segment_count: int = 14
## Rest distance held between neighbouring spine points.
@export_range(4.0, 40.0, 0.5) var segment_length: float = 15.0
## Constraint relaxation passes per physics tick. More = stiffer / more exact.
@export_range(1, 16, 1) var constraint_iterations: int = 6
## Fraction of the distance error corrected per pass. 1.0 = rigid, low = soft.
@export_range(0.05, 1.0, 0.01) var spine_stiffness: float = 0.85
## Verlet inertia retained per tick. Higher = more trailing / whip on turns.
@export_range(0.0, 0.95, 0.01) var spine_damping: float = 0.70
## Hard limit on the bend between two adjacent spine segments.
@export_range(2.0, 60.0, 0.5) var max_bend_deg: float = 22.0
## Peak sideways undulation, in pixels of sway at mid-body. 0 disables it.
## Keep this well under stride_distance — sway wider than a stride makes the
## feet chase the wobble instead of the direction of travel.
@export_range(0.0, 30.0, 0.5) var body_wave: float = 6.0
## How many wave periods fit along the body.
@export_range(0.2, 3.0, 0.05) var wave_frequency: float = 0.8
## How fast the wave travels (scaled by movement speed).
@export_range(0.0, 6.0, 0.05) var wave_speed: float = 1.6

# ----------------------------------------------------------------- body ----
@export_group("Body")
## Global multiplier on the whole width profile.
@export_range(0.3, 2.5, 0.01) var body_width: float = 1.0
## Width profile knots, sampled head -> tail tip with a Catmull-Rom spline.
@export_range(2.0, 40.0, 0.5) var head_width: float = 13.0
@export_range(2.0, 40.0, 0.5) var chest_width: float = 15.0
@export_range(1.0, 40.0, 0.5) var waist_width: float = 10.5
@export_range(1.0, 40.0, 0.5) var hip_width: float = 12.5
@export_range(0.5, 20.0, 0.5) var tail_tip_width: float = 1.5
## Tail is optional — off clips the silhouette just behind the hips.
@export var tail_enabled: bool = true
## How much of the spine behind the pelvic block the tail actually uses, 0..1.
## The whole of it by default, which is the legacy body — every build used to
## taper away over everything aft of its hips, so an elephant wore a tail the
## size of its own trunk. Short is a stump on rounded hindquarters; the clipped
## stations still exist in the chain, they are simply not flesh.
@export_range(0.05, 1.0, 0.01) var tail_length: float = 1.0
## Half-width of the tail where it leaves the buttocks. Zero keeps the legacy
## profile — the tail as a smooth continuation of the hip taper, which is right
## for a lizard and wrong for almost everything else. Set, it pinches the
## profile just behind the pelvic block, so the hindquarters round off as a rump
## and the tail reads as its own structure hung from it.
@export_range(0.0, 20.0, 0.5) var tail_base_width: float = 0.0
## Optional half-width of the neck, measured between the skull and the shoulder.
## Zero keeps the legacy profile, where the head blends into the chest along one
## smooth spline. Set below the head width it waists the silhouette behind the
## skull, which is what makes a head read as a head from above.
@export_range(0.0, 30.0, 0.5) var neck_width: float = 0.0
## Where along the spine (0 = head, 1 = tail tip) the limbs attach.
@export_range(0.02, 0.5, 0.01) var front_limb_t: float = 0.16
@export_range(0.2, 0.9, 0.01) var rear_limb_t: float = 0.46

# -------------------------------------------------------------- posture ----
@export_group("Posture")
## How this animal holds its legs under it: 0 sprawled, 1 semi-upright, 2
## columnar, 3 erect. See Posture — one trait, and the stance width, the body
## clearance, how much of the upper limb the torso stands over, how much the
## spine undulates, how many feet stay down and how readily the animal turns all
## come out of it. It is an anatomical category, not a tuning group: two creatures
## with the same numbers and different postures are different animals.
##
## Note that it does not say how many legs the animal walks on. Whether the
## forelimbs reach the ground is a question about how long they are, and it is
## answered in Locomotion off `arm_length` against `leg_length` — so an erect
## build with long arms is a fast quadruped and a semi-upright one with vestigial
## arms is bipedal, and neither needed a category of its own.
@export_range(0, 3, 1) var posture: int = Posture.SPRAWLED

# --------------------------------------------------------------- height ----
@export_group("Height")
## How far above the shoulder the head is carried, as a fraction of the animal's
## own length. Zero is a head held in the plane of the body — a lizard. Large is
## a browser, and the whole of what makes one: a long neck raises what the jaws
## can reach without touching anything else about the creature.
@export_range(0.0, 0.6, 0.01) var neck_lift: float = 0.0
## Lift the wings generate, zero on anything without them. It is the only thing
## separating a creature that can glide and fly from one that can only leap:
## with none, the two airborne states are simply unreachable — see Elevation.
@export_range(0.0, 2.0, 0.05) var wing_lift: float = 0.0
## How steeply a trunk with nothing standing under its shoulders is carried off
## the level, in degrees. Read only when the forelimbs bear no weight — a
## quadruped's shoulders are held by its legs and this says nothing to it — so
## it is the biped's carried angle, the same kind of trait a flexed elbow is: a
## kangaroo rears its trunk over its hips, a tyrannosaur levels its own out over
## a heavier tail, and the difference is this number rather than a pose. See
## Gait._carry_body, which holds the fore girdle to it.
@export_range(0.0, 60.0, 1.0) var trunk_lift_deg: float = 0.0

# ---------------------------------------------------------------- limbs ----
@export_group("Limbs")
## Total length of a two-bone chain. How it divides between the two bones, how
## far it is extended standing, and how far it may extend or fold at all are
## articulation rather than length — see the group below.
@export_range(8.0, 120.0, 1.0) var arm_length: float = 34.0
@export_range(8.0, 120.0, 1.0) var leg_length: float = 40.0
## How far out to the side the rest stance sits (relative to fore/aft bias).
@export_range(0.2, 2.0, 0.01) var stance_width: float = 1.0
## FABRIK relaxation passes per limb per tick.
@export_range(1, 12, 1) var fabrik_iterations: int = 6

# --------------------------------------------------------- articulation ----
# What each girdle does with the limbs hanging off it — see Articulation. Three
# numbers used to live in the group above and none of them could be one: how
# extended a leg stands, how far it may extend, and how tightly it folds are all
# readings of one angle at the elbow or the knee, and quoting them as lengths is
# what made every animal in the game stand in the same three-quarters-extended
# crouch. A columnar build could not be given a straight leg, because the reach
# cap was a long way below straight; a cat could not be given a straight foreleg
# and a folded hind one, because there was one number for the whole animal.
#
# So the trait is the angle, the stance owns the base of it — see Posture — and
# what a species carries is per *girdle*, because a girdle is the unit a real
# skeleton varies at.
@export_group("Articulation")
## How much more flexed than its stance this girdle carries its joint, in
## degrees. Negative is straighter. Zero is an animal that articulates exactly
## the way its posture does, which is the honest default for a build that has
## said nothing about it.
@export_range(-70.0, 70.0, 1.0) var fore_flex_deg: float = 0.0
@export_range(-70.0, 70.0, 1.0) var hind_flex_deg: float = 0.0
## How far the joint folds, against how far its stance folds. Under one is a
## joint that cannot be drawn up — a graviportal leg, which is why a heavy
## columnar animal can neither crouch to the floor nor gather itself to jump, and
## why nothing had to forbid either. Over one is a limb that folds tighter than
## its stance normally would, which is where a spring comes from.
@export_range(0.1, 1.6, 0.01) var fore_fold_range: float = 1.0
@export_range(0.1, 1.6, 0.01) var hind_fold_range: float = 1.0
## Share of the limb in the upper bone. Over a half is weight carried high and
## close to the body — a heavy animal's proportions; under it is a long light
## segment left out at the bottom to swing, which is a runner's.
@export_range(0.34, 0.66, 0.01) var fore_upper_share: float = 0.52
@export_range(0.34, 0.66, 0.01) var hind_upper_share: float = 0.52
## Half-angle of the fan the socket swings the whole limb through, measured from
## its rest stance. Stops a limb the body has walked past from folding forward
## under the chin or trailing back alongside the tail. Per girdle because a hip
## and a shoulder are different joints on the same animal.
@export_range(20.0, 110.0, 1.0) var fore_swing_deg: float = 62.0
@export_range(20.0, 110.0, 1.0) var hind_swing_deg: float = 62.0
## How much of the foot is a toe to push off from.
##
## The only propulsion a straight-legged animal has, and the reason it is a
## parameter at all: a limb held near vertical cannot lengthen its stride by
## bending, so what carries the body over a planted foot at the end of its stance
## is the foot rolling forward onto its toe. Zero is a flat-footed animal that
## simply swings its legs.
@export_range(0.0, 1.0, 0.01) var toe_push: float = 0.15
## Where this girdle's muscle inserts past the joint it works, as a share of the
## bone it pulls on — the effort arm of the lever every limb is.
##
## Muscle pulls tendon, tendon pulls bone, bone turns about the joint: the last
## of the four is geometry and this is the number that sets it. Close in is a
## limb geared for speed — the same contraction sweeps the foot further and
## faster and presses more lightly, which is a runner's shank; further out is
## the same limb geared for force, which is a digger's forearm and a heavy
## leg's hold on the ground. 0.30 is the reference build's insertion, at which
## the lever changes nothing at all. See Articulation, which derives the
## advantage and the gear, and note what it deliberately cannot change: a
## lever trades force for speed and never work, so a jump — force times
## distance — is untouched by it.
@export_range(0.15, 0.5, 0.01) var fore_insertion: float = 0.30
@export_range(0.15, 0.5, 0.01) var hind_insertion: float = 0.30

# ---------------------------------------------------------------- elastic ----
# What in this animal stores work and gives it back — see Spring. There used to
# be a `leap_height` in the Height group instead, a per-species multiple of the
# animal's own height, and a parameter of that shape can only ever be a promise:
# it said an Elephant could not jump because somebody wrote a zero, and it would
# have said a creature with no legs could clear three of itself if somebody had
# written a three. Nothing about the body was consulted and nothing about the
# body could contradict it.
#
# What is here instead is tissue. How high anything jumps is worked out in Leap,
# off the mass, the muscle, the joint travel and the store below — which is why
# lengthening a leg or loosening a knee changes it, and why the two builds that
# cannot leave the ground are no longer told that they cannot.
@export_group("Elastic")
## How much of this girdle's drive passes through something elastic on its way to
## the ground, rather than being produced by the muscle at the moment it is
## needed. Zero is an animal that jumps on muscle alone; high is a leg that is
## mostly rope below the knee. Per girdle, because a hind limb built to store and
## a foreleg built to prop are the ordinary arrangement rather than the exception.
@export_range(0.0, 1.0, 0.01) var fore_spring: float = 0.15
@export_range(0.0, 1.0, 0.01) var hind_spring: float = 0.20
## How much of the store is held by a catch rather than by the muscle winding it.
##
## Zero — an ordinary tendon — means the spring can only be paid out as fast as
## the joint it crosses opens, so a limb with little travel returns little of what
## it holds however much that is. One is a catch that lets go independently, which
## removes the limit entirely and is the only way a body with very short legs
## throws itself any distance at all. It is what separates the insects that jump
## from the insects that do not, and it is deliberately not called a tendon
## anywhere: a resilin pad, a bent cuticle and a latched femur are all this
## number.
@export_range(0.0, 1.0, 0.01) var spring_latch: float = 0.0

# ----------------------------------------------------------------- gait ----
@export_group("Gait")
# Three numbers used to live here — how far a foot travels between steps, how
# long it takes to get there, and how high it comes up — and none of them can be
# a number. A stride is the travel a limb of that length, at that angle, over a
# body willing to sink that far actually has; a step time is a pendulum of that
# length swung by that much muscle; a lift is a share of the animal doing the
# lifting. All three are worked out in Locomotion now, off the same mass, bones
# and posture everything else about the creature is read from. What is left in
# this group is the two that really are species traits, because they are choices
# about coordination rather than consequences of anatomy: how far ahead of itself
# an animal places its feet, and how tightly it keeps its diagonals together.
## How far ahead of the body feet aim while moving (fraction of stride).
@export_range(0.0, 1.5, 0.01) var foot_lead: float = 0.45
## How eagerly a limb joins a beat one of its partners has just started. Which
## limbs share a beat is not a setting — see Footfall, where it falls out of the
## body's proportions and how fast it is going — so this is only how tightly they
## keep to it. 1 is a pair that lands as one; 0 is four independent legs.
@export_range(0.0, 1.0, 0.01) var beat_coupling: float = 0.55
## Fore/aft placement of the rest stance (+ forward, - backward).
@export_range(-1.0, 1.0, 0.01) var front_foot_bias: float = 0.30
@export_range(-1.0, 1.0, 0.01) var rear_foot_bias: float = -0.25

# -------------------------------------------------------------- physique ----
@export_group("Physique")
## How heavy the creature is for its size. Mass itself is not a parameter — it is
## the drawn silhouette's volume times this times how much tissue is left, so a
## broader body is a heavier body and a chewed-open one is a lighter one. 1.0 is
## the default Lizard's build at mass 1.0.
@export_range(0.2, 4.0, 0.01) var density: float = 1.0
## Force per unit of cross-section the creature can put into locomotion. Strength
## is this times mass^(2/3), so raising it makes a creature strong *for its size*
## rather than simply large.
@export_range(0.2, 4.0, 0.01) var muscle_power: float = 1.0
## What the muscle is made of: the share of its fibre that is fast-twitch. It is
## composition, not amount — `muscle_power` and the census say how much force
## there is; this says how quickly it can be applied. Fast fibre turns the limbs
## over sooner when the animal is throwing them — sprinting, leaping — and slow
## fibre gives that quickness up. 0.5 is the mixed default every preset stands
## on; the specimen quotes it on every muscle cell.
@export_range(0.0, 1.0, 0.01) var fast_twitch: float = 0.5
## What the heart and the plumbing behind it are worth, against the reference
## build's. The one cardiovascular trait, and the only new number stamina needed:
## how much of it there is is not a setting — `Stamina` reads the heart organ, the
## blood left to move it and the vessel tree that carries it off the anatomy every
## tick — so this is what a species' circulation is *built* like, quoted the same
## way `muscle_power` quotes its muscle.
##
## It is the primary term in what an animal can sustain and the whole of how fast
## it gets its breath back, and it does nothing else: a stronger heart never made
## anything quicker off the mark. 1.0 is the default Lizard, which is where every
## stamina constant in the file is measured.
@export_range(0.2, 3.0, 0.01) var heart_power: float = 1.0
## How much fat the species lays down, as a multiple of the body plan's profile —
## thickest over the trunk, thinning toward the head, tail and limbs. It is not a
## damage-resistance number: fat is a real layer in the depth stack, so a padded
## creature is heavier, and the same jaws reach its muscle shallower because the
## fat spent part of the bite getting there. 0 is an animal with none.
@export_range(0.0, 3.0, 0.05) var fat_reserve: float = 1.0

# ------------------------------------------------------------- movement ----
@export_group("Movement")
## The speed this species asks to travel at, and no longer the speed it gets.
##
## What it actually gets is the lower of this and what its legs will carry it at,
## which is a stride divided by a step and is worked out in Locomotion.leg_speed.
## That is the only honest arrangement: a number here cannot know how far the
## animal's legs reach or how long they take to come through, so left in charge it
## simply drove the body faster than the gait could keep up with and the feet were
## cycled to suit — eleven and twelve steps a second on the two quickest builds in
## the file, with each swing clipped to a floor to fit.
##
## So a value under what the legs give is a species choosing not to hurry, and a
## value over it says nothing at all. They are quoted a little above what each
## build's legs deliver, which leaves the anatomy in charge while keeping the
## number in the creation menu from being a fiction.
##
## How hard the species gets up to it stopped being a parameter altogether: the
## push is the girdle muscle read through its own tendons and stance, spent
## through whichever feet are on the ground, and fading as the speed uses the
## muscle up — see Locomotion.PUSH_REFERENCE and Locomotion.push_left. A species
## cannot be quick off the mark by assertion any more; it has to be built out of
## the legs that would make it so.
@export_range(20.0, 600.0, 5.0) var move_speed: float = 90.0
## The turn a body's own muscle can put into it, before the feet are asked.
##
## Torque over rotational inertia — Locomotion works the rest out from the mass,
## the muscle and the animal's own length — and it is now one of two ceilings
## rather than the only one. The other is what the legs can walk the body around
## at, which is what a standing turn actually is, and on every light quick build
## in the file it is much the lower of the two. See Locomotion.walked_turn.
@export_range(20.0, 720.0, 5.0) var turn_speed_deg: float = 190.0
## How much of the turn rate is given up at top speed. Turn radius is
## speed / turn_rate, so without a falloff a fast creature carves a circle
## tighter than its own body and coils into a hook. Keep the radius at speed
## comfortably above segment_count * segment_length.
@export_range(0.0, 0.9, 0.01) var turn_speed_falloff: float = 0.55
## How quickly angular velocity reaches the commanded turn rate.
@export_range(1.0, 20.0, 0.1) var turn_responsiveness: float = 12.0
## How far back along the body the station a standing turn swings about sits, so
## the creature can pivot on the spot instead of needing forward speed to change
## direction. Measured along the spine from the head, which puts it on the flesh
## rather than at a point in the air behind the nose: the front end swings about
## it and the rest of the body follows, instead of the whole creature being towed
## sideways. Backing up it slides to the hips by itself — see `_turn_station`.
@export_range(0.0, 160.0, 1.0) var turn_pivot: float = 46.0
@export_range(1.0, 3.0, 0.05) var sprint_multiplier: float = 1.55
## Reverse top speed as a fraction of forward. Legs are built to push a body
## forward, so backing up is a deliberate retreat rather than a mirrored walk;
## sprint never applies to it. It handicaps steering by the same fraction, for
## the same reason: those legs are pushing the body around from the wrong end.
@export_range(0.2, 1.0, 0.01) var reverse_speed_factor: float = 0.55

# --------------------------------------------------------------- combat ----
@export_group("Combat")
## How far the head itself is thrown forward by a lunge. The mouth is on the
## head and a bite lands where the mouth is, so this is the whole of a
## creature's reach beyond standing still: the jaws have to genuinely arrive.
@export_range(2.0, 60.0, 1.0) var bite_reach: float = 28.0
## The gape: radius of the arc the teeth are set in, around the head. It is both
## the span the jaws can close on and the footprint they cover, and it is capped
## against the head — jaws are set in a skull, so a mouth cannot be much wider
## than the animal wearing it.
@export_range(2.0, 50.0, 1.0) var bite_radius: float = 18.0
## Minimum time between accepted bite clicks.
@export_range(0.05, 2.0, 0.01) var bite_cooldown: float = 0.45
## How deep one bite drives into the tissue lattice, at the centre of the jaws,
## in hit points — so it is read against TissueGrid's layer costs rather than as
## a fraction of anything. Skin is 0.4, so the default strips it across nearly
## the full width of the jaws in one go; muscle is 5.5, so tearing through it
## takes three bites on the same spot or a deeper one. Bone is 6.0 and yields at
## half rate, so it takes several more again.
@export_range(0.2, 8.0, 0.05) var bite_damage: float = 2.6
## How hard the jaws clamp, for a head of the reference size — the other half of
## "bite strength", and the one that decides whether a hold survives the victim.
## Measured against the load a grip hangs off it, which is the two masses and how
## hard they are pulling apart, so this is directly "how much thrashing can these
## jaws sit through". `bite_damage` is what one closing of them cuts; this is
## whether they stay shut. Actual bite force also scales with the square of the
## head's radius, so a broad-skulled creature bites harder at the same setting.
@export_range(0.1, 12.0, 0.05) var jaw_power: float = 1.0
## The soonest jaws already holding something can close on it again. Chewing is
## an action rather than a clock — a hold never bites by itself — so this is not
## a rate but a floor under one: how fast this species can work its jaws while
## they stay shut on their bind. `bite_cooldown` governs fresh strikes, which
## have to be thrown as well as closed and are correspondingly slower.
@export_range(0.1, 2.0, 0.01) var chew_interval: float = 0.55

# ------------------------------------------------------------- dentition ----
# What the jaws are actually armed with — see Dentition. These four decide the
# shape of every wound this creature makes, and none of them is a damage number:
# `bite_damage` says how hard the jaws close, and the teeth decide what that is
# spent on. Fewer, keener teeth concentrate one bite into deep punctures; a
# crowded mouth of blunt cusps spreads the same bite into a shallow crush over
# twice the area. Tooth *type* is not listed at all — it is read off where a
# tooth sits and how keen the mouth is.
@export_group("Dentition")
## Teeth per arch. There are two arches, upper and lower, so a mouth carries
## twice this — and the lower row meshes into the gaps of the upper.
@export_range(1, 24, 1) var tooth_count: int = 9
## Length of a canine, as a fraction of the gape radius. Every other type is
## sized against it, so this is "how toothy", not "how big is one tooth".
@export_range(0.04, 0.6, 0.01) var tooth_size: float = 0.22
## 0 is blunt crushing cusps, 1 is needles. Keenness shrinks the patch a tooth
## meets flesh over, which is what drives it deeper for the same jaw force, and
## it is also what decides how far back the mouth carries fangs and blades.
@export_range(0.0, 1.0, 0.01) var tooth_sharpness: float = 0.72
## Half-angle of the arc the teeth are set in, measured from the snout's
## midline. A wide gape is a mouthful that reaches around a flank; a narrow one
## is a snapping bird's beak of a bite.
@export_range(15.0, 120.0, 1.0) var jaw_gape_deg: float = 70.0
## Per-tooth spread in length and width. Zero is a machined comb; the default is
## a mouth that has been used.
@export_range(0.0, 0.6, 0.01) var tooth_variation: float = 0.18


## Drives the runtime creation menu. Rows with "group" are section headers.
const SCHEMA: Array = [
	{"group": "Spine"},
	{"prop": "segment_count", "label": "Segment count", "min": 6.0, "max": 28.0, "step": 1.0},
	{"prop": "segment_length", "label": "Segment length", "min": 4.0, "max": 40.0, "step": 0.5},
	{"prop": "constraint_iterations", "label": "Constraint iters", "min": 1.0, "max": 16.0, "step": 1.0},
	{"prop": "spine_stiffness", "label": "Stiffness", "min": 0.05, "max": 1.0, "step": 0.01},
	{"prop": "spine_damping", "label": "Damping (softness)", "min": 0.0, "max": 0.95, "step": 0.01},
	{"prop": "max_bend_deg", "label": "Max bend (deg)", "min": 2.0, "max": 60.0, "step": 0.5},
	{"prop": "body_wave", "label": "Undulation (px)", "min": 0.0, "max": 30.0, "step": 0.5},
	{"prop": "wave_frequency", "label": "Wave frequency", "min": 0.2, "max": 3.0, "step": 0.05},
	{"prop": "wave_speed", "label": "Wave speed", "min": 0.0, "max": 6.0, "step": 0.05},

	{"group": "Body"},
	{"prop": "body_width", "label": "Width scale", "min": 0.3, "max": 2.5, "step": 0.01},
	{"prop": "head_width", "label": "Head", "min": 2.0, "max": 40.0, "step": 0.5},
	{"prop": "neck_width", "label": "Neck (0 = smooth)", "min": 0.0, "max": 30.0, "step": 0.5},
	{"prop": "chest_width", "label": "Chest", "min": 2.0, "max": 40.0, "step": 0.5},
	{"prop": "waist_width", "label": "Waist", "min": 1.0, "max": 40.0, "step": 0.5},
	{"prop": "hip_width", "label": "Hip", "min": 1.0, "max": 40.0, "step": 0.5},
	{"prop": "tail_base_width", "label": "Tail base (0 = smooth)", "min": 0.0, "max": 20.0, "step": 0.5},
	{"prop": "tail_tip_width", "label": "Tail tip", "min": 0.5, "max": 20.0, "step": 0.5},
	{"prop": "tail_length", "label": "Tail length", "min": 0.05, "max": 1.0, "step": 0.01},
	{"prop": "tail_enabled", "label": "Tail", "bool": true},
	{"prop": "front_limb_t", "label": "Shoulder pos", "min": 0.02, "max": 0.5, "step": 0.01},
	{"prop": "rear_limb_t", "label": "Hip pos", "min": 0.2, "max": 0.9, "step": 0.01},

	{"group": "Posture"},
	{"prop": "posture", "label": "Stance (0-3)", "min": 0.0, "max": 3.0, "step": 1.0},

	{"group": "Height"},
	{"prop": "neck_lift", "label": "Neck lift", "min": 0.0, "max": 0.6, "step": 0.01},
	{"prop": "trunk_lift_deg", "label": "Trunk lift (deg)", "min": 0.0, "max": 60.0, "step": 1.0},
	{"prop": "wing_lift", "label": "Wing lift", "min": 0.0, "max": 2.0, "step": 0.05},

	{"group": "Limbs"},
	{"prop": "arm_length", "label": "Arm length", "min": 8.0, "max": 120.0, "step": 1.0},
	{"prop": "leg_length", "label": "Leg length", "min": 8.0, "max": 120.0, "step": 1.0},
	{"prop": "stance_width", "label": "Stance width", "min": 0.2, "max": 2.0, "step": 0.01},
	{"prop": "fabrik_iterations", "label": "FABRIK iters", "min": 1.0, "max": 12.0, "step": 1.0},

	{"group": "Articulation"},
	{"prop": "fore_flex_deg", "label": "Fore flex (deg)", "min": -70.0, "max": 70.0, "step": 1.0},
	{"prop": "hind_flex_deg", "label": "Hind flex (deg)", "min": -70.0, "max": 70.0, "step": 1.0},
	{"prop": "fore_fold_range", "label": "Fore fold range", "min": 0.1, "max": 1.6, "step": 0.01},
	{"prop": "hind_fold_range", "label": "Hind fold range", "min": 0.1, "max": 1.6, "step": 0.01},
	{"prop": "fore_upper_share", "label": "Fore upper bone", "min": 0.34, "max": 0.66, "step": 0.01},
	{"prop": "hind_upper_share", "label": "Hind upper bone", "min": 0.34, "max": 0.66, "step": 0.01},
	{"prop": "fore_swing_deg", "label": "Fore swing (deg)", "min": 20.0, "max": 110.0, "step": 1.0},
	{"prop": "hind_swing_deg", "label": "Hind swing (deg)", "min": 20.0, "max": 110.0, "step": 1.0},
	{"prop": "toe_push", "label": "Toe push-off", "min": 0.0, "max": 1.0, "step": 0.01},
	{"prop": "fore_insertion", "label": "Fore tendon lever", "min": 0.15, "max": 0.5, "step": 0.01},
	{"prop": "hind_insertion", "label": "Hind tendon lever", "min": 0.15, "max": 0.5, "step": 0.01},

	{"group": "Elastic"},
	{"prop": "fore_spring", "label": "Fore spring", "min": 0.0, "max": 1.0, "step": 0.01},
	{"prop": "hind_spring", "label": "Hind spring", "min": 0.0, "max": 1.0, "step": 0.01},
	{"prop": "spring_latch", "label": "Spring latch", "min": 0.0, "max": 1.0, "step": 0.01},

	{"group": "Gait"},
	{"prop": "foot_lead", "label": "Foot lead", "min": 0.0, "max": 1.5, "step": 0.01},
	{"prop": "beat_coupling", "label": "Beat coupling", "min": 0.0, "max": 1.0, "step": 0.01},
	{"prop": "front_foot_bias", "label": "Front foot bias", "min": -1.0, "max": 1.0, "step": 0.01},
	{"prop": "rear_foot_bias", "label": "Rear foot bias", "min": -1.0, "max": 1.0, "step": 0.01},

	{"group": "Physique"},
	{"prop": "density", "label": "Density", "min": 0.2, "max": 4.0, "step": 0.01},
	{"prop": "muscle_power", "label": "Muscle power", "min": 0.2, "max": 4.0, "step": 0.01},
	{"prop": "fast_twitch", "label": "Fast twitch", "min": 0.0, "max": 1.0, "step": 0.01},
	{"prop": "heart_power", "label": "Heart power", "min": 0.2, "max": 3.0, "step": 0.01},
	{"prop": "fat_reserve", "label": "Fat reserve", "min": 0.0, "max": 3.0, "step": 0.05},

	{"group": "Movement"},
	{"prop": "move_speed", "label": "Move speed", "min": 20.0, "max": 600.0, "step": 5.0},
	{"prop": "turn_speed_deg", "label": "Turn speed (deg/s)", "min": 20.0, "max": 720.0, "step": 5.0},
	{"prop": "turn_speed_falloff", "label": "Turn falloff @ speed", "min": 0.0, "max": 0.9, "step": 0.01},
	{"prop": "turn_responsiveness", "label": "Turn response", "min": 1.0, "max": 20.0, "step": 0.1},
	{"prop": "turn_pivot", "label": "Turn pivot", "min": 0.0, "max": 160.0, "step": 1.0},
	{"prop": "sprint_multiplier", "label": "Sprint multiplier", "min": 1.0, "max": 3.0, "step": 0.05},
	{"prop": "reverse_speed_factor", "label": "Reverse speed", "min": 0.2, "max": 1.0, "step": 0.01},

	{"group": "Combat"},
	{"prop": "bite_reach", "label": "Bite reach", "min": 2.0, "max": 60.0, "step": 1.0},
	{"prop": "bite_radius", "label": "Bite radius", "min": 2.0, "max": 50.0, "step": 1.0},
	{"prop": "bite_cooldown", "label": "Bite cooldown", "min": 0.05, "max": 2.0, "step": 0.01},
	{"prop": "bite_damage", "label": "Bite depth", "min": 0.2, "max": 8.0, "step": 0.05},
	{"prop": "jaw_power", "label": "Jaw power", "min": 0.1, "max": 12.0, "step": 0.05},
	{"prop": "chew_interval", "label": "Chew interval", "min": 0.1, "max": 2.0, "step": 0.01},

	{"group": "Dentition"},
	{"prop": "tooth_count", "label": "Teeth per arch", "min": 1.0, "max": 24.0, "step": 1.0},
	{"prop": "tooth_size", "label": "Tooth length", "min": 0.04, "max": 0.6, "step": 0.01},
	{"prop": "tooth_sharpness", "label": "Sharpness", "min": 0.0, "max": 1.0, "step": 0.01},
	{"prop": "jaw_gape_deg", "label": "Gape (deg)", "min": 15.0, "max": 120.0, "step": 1.0},
	{"prop": "tooth_variation", "label": "Tooth variation", "min": 0.0, "max": 0.6, "step": 0.01},
]


## Named starting points for tuning. Anything omitted keeps the default.
##
## One per posture, because posture is the axis these three are laid out along.
## Everything that separates them as animals to play — how they turn, how much of
## their legs you can see, how high they stand, what they can reach and what can
## reach them — is downstream of that one trait plus the ordinary silhouette and
## power numbers every species already had.
##
## The physique rows are worth reading as a set. Mass is not listed anywhere
## because it is not a setting — the silhouette above each `density` already
## decides most of it, and these three numbers only say what kind of animal that
## silhouette is made of: how solid, how strong for its size, and how hard its
## jaws shut. That is why the Cat can be quicker than the Lizard while weighing a
## fraction of the Elephant, and why the Elephant's jaws are in a different
## league without its `jaw_power` being extreme: it is wearing a skull twice the
## reference width, and bite force goes as the square of that.
const PRESETS: Dictionary = {
	# The sprawled reference, and the body every other number in this file is
	# quoted against. Belly near the floor, legs out to the sides, and a spine
	# that does part of the walking — which is why it is the one preset that keeps
	# its undulation at full strength.
	"Lizard": {},

	# Semi-upright. Legs drawn in under the body, so the plan-view reach is barely
	# two thirds of the leg and the shoulder disappears beneath the torso; the
	# spine stops undulating because the legs have taken the stride back off it.
	# What it buys is the whole point of the stance: the drive and the turn rate
	# come off the posture table, not from these numbers, and the difference is
	# larger than anything written below.
	"Cat": {
		"posture": Posture.SEMI_UPRIGHT,
		"segment_count": 12, "segment_length": 14.0, "max_bend_deg": 26.0,
		"spine_stiffness": 0.88, "spine_damping": 0.64, "body_wave": 5.0,
		"wave_frequency": 0.9, "wave_speed": 2.0,
		# A rope of a tail hung off a rounded rump, not a body tapering away: the
		# base knot steps the profile down behind the pelvis to a third of the
		# hip and it barely tapers from there — a cat's tail is famously the
		# same thickness most of its length, and that near-constant section is
		# also real counterweight behind the hips, which the hind-driven leap is
		# standing on. The waisted neck is the same fix at the other end — a
		# round skull on a neck, not a head blending into the chest.
		"head_width": 11.0, "neck_width": 8.0, "chest_width": 15.0,
		"waist_width": 12.0, "hip_width": 15.0,
		"tail_base_width": 5.0, "tail_tip_width": 2.2,
		"front_limb_t": 0.17, "rear_limb_t": 0.50,
		"arm_length": 40.0, "leg_length": 46.0, "stance_width": 0.85,
		# The two ends of this animal are not the same limb, and that is the whole
		# of what separates it from a scaled lizard standing further up.
		#
		# In front: a strut. The elbow is carried at a hundred and fifty degrees —
		# the two bones close to in line — because a cat's forelimb is there to hold
		# the front of it up and to land on, and a column does both better than a
		# spring. Behind: an engine. The knee stands at a hundred and fourteen,
		# folds tighter than its stance normally would, swings through a wider fan
		# and carries the longer, lighter distal bone, which between them are the
		# crouch, the gather and the leap.
		#
		# The two clear the ground by within a pixel of each other all the same,
		# and nothing arranges that: a longer hind leg folded further and a shorter
		# foreleg held straight arrive at the same height, which is why a cat's back
		# is level over legs that are doing opposite jobs.
		#
		# How far apart they may be pushed is bounded by something real rather than
		# by taste. A straighter limb has less of itself left in the ground plane to
		# swing — that is the whole trade the stance is making — so it takes shorter
		# steps, and a girdle taking steps less than about half the length of the
		# other's is a girdle stepping twice for every one of its partner's. Which is
		# not a gait. Past that the animal would need a shoulder blade that slides
		# along its ribs to make up the difference, and it has not got one.
		"fore_flex_deg": -18.0, "hind_flex_deg": 18.0,
		"fore_fold_range": 0.95, "hind_fold_range": 1.20,
		"fore_upper_share": 0.50, "hind_upper_share": 0.45,
		"fore_swing_deg": 56.0, "hind_swing_deg": 74.0,
		# Digitigrade: it stands on its toes already, so there is a real push there.
		"toe_push": 0.45,
		# The hind tendons come in close to the joint: a lever geared a shade for
		# speed, which is what lets the engine end of this animal turn its legs
		# over quicker than the strut end without carrying different muscle.
		"hind_insertion": 0.28,
		# ...and a good deal of rope behind. The hind limb that folds tighter than
		# its stance and swings through the wider fan is also the one carrying the
		# store, which is not a coincidence: a spring is wound by folding a joint,
		# so the girdle with the travel is the only girdle that can hold anything.
		# The foreleg's share is the smaller half of the same tissue and is spent
		# on landings rather than on take-offs.
		"fore_spring": 0.35, "hind_spring": 0.55,
		# No turn rate of its own: this animal is light and it is strong for its
		# size, and those two facts are already written below as `density` and
		# `muscle_power`. How it gets away is those two through its own levers —
		# see Locomotion.PUSH_REFERENCE — and quoting a number here as well would
		# be saying the same thing twice and then arguing with itself.
		"move_speed": 85.0,
		"turn_responsiveness": 14.0, "turn_pivot": 40.0,
		"sprint_multiplier": 1.80,
		"density": 0.68, "muscle_power": 1.56, "jaw_power": 1.1, "fat_reserve": 0.8,
		# An ambush hunter's heart: a shade under the reference, on an animal
		# carrying half again its muscle for its weight. What that pairing comes to
		# is a creature that is quick, that can spend hard, and that cannot keep it
		# up — the chase is meant to be over in seconds or not at all.
		"heart_power": 0.95,
		"bite_damage": 2.4, "bite_reach": 30.0, "bite_radius": 14.0,
		"bite_cooldown": 0.32, "chew_interval": 0.40,
		# Head carried clear of the shoulder. The legs that throw this animal
		# several times its own standing height are the four rows above rather than
		# anything here — a knee folded past its stance, a long light shin, a store
		# wound along it and enough muscle for its weight to beat gravity twice
		# over — which is the whole point of there no longer being a leap number.
		"neck_lift": 0.10,
		# Few teeth, long and keen. A killing mouth rather than a holding one:
		# almost no contact area, so what force there is goes straight in.
		"tooth_count": 7, "tooth_size": 0.30, "tooth_sharpness": 0.92,
		"jaw_gape_deg": 58.0, "tooth_variation": 0.20,
	},

	# Columnar. Feet stacked directly under the body, which is held nearly a whole
	# leg off the ground — so this animal's torso is out of reach of anything the
	# other two can bring to bear, and only its legs can be got at from below.
	# That is not a rule written for it; it is where its bands land.
	#
	# Its jaws are the heaviest in the file without `jaw_power` being extreme,
	# because bite force goes as the square of the skull and this one is nearly
	# twice the reference width. And it cannot leave the ground at all — a fact
	# nothing in this entry states, and nothing in it could: its knees do not
	# close, so there is nowhere to push from, and its muscle cannot beat its own
	# weight, so there would be nothing to push with if there were. See Leap.
	"Elephant": {
		"posture": Posture.COLUMNAR,
		"segment_count": 16, "segment_length": 19.0, "max_bend_deg": 10.0,
		"spine_stiffness": 0.95, "spine_damping": 0.50, "body_wave": 3.0,
		"head_width": 24.0, "chest_width": 34.0, "waist_width": 29.0,
		# Rounded hindquarters and a stump. The old build tapered from the hips
		# to the chain's end like everything else adapted from the lizard, which
		# wore this animal a tail the size of its own trunk; the reference sheet
		# gives it a rope half a girdle-gap long. The base knot rounds the rump
		# off at the pelvis and the length clips the flesh there — the spine
		# behind it still exists, it is simply not elephant.
		"hip_width": 31.0, "tail_base_width": 3.0, "tail_tip_width": 2.0,
		"tail_length": 0.55,
		# Shoulders brought up close behind the skull. An elephant is a huge head
		# carried on almost no neck, and the whole of that is where the pectoral
		# girdle sits: at 0.22 the head rode a fifth of the animal ahead of its
		# own shoulders, which is a browser's reach, not an elephant's — the
		# sheet parks the skull's edge a few pixels off the shoulder. The trunk
		# between the girdles gains what the neck gives up.
		"front_limb_t": 0.14, "rear_limb_t": 0.54,
		# Held nearly vertical, so the clearance is most of the leg and the
		# plan-view reach is under a third of it — which is what makes the feet land
		# close underneath the body.
		#
		# The length is against the *trunk*, and that is the correction: at 132 px
		# on a 300 px body these were legs four tenths of the animal long, standing
		# it a third higher off the ground than it was deep through the chest. What
		# that draws is an elephant-coloured animal on stilts. A heavy quadruped's
		# belly clearance is about its own depth — it is a body slung between its
		# legs, not perched on them — and at 82 px under a 67 px-deep chest this one
		# now is. Nothing else in the file had to move: the height, the bands, what
		# can walk under it and what its trunk can reach are all read off the legs.
		# ...and the forelimbs the longer pair, which is why the back slopes down
		# from the shoulder. It is an ordinary length rather than a drawn attitude:
		# the front of the animal is held higher because the bones holding it are
		# longer, and the pitch falls out in the gait.
		"arm_length": 92.0, "leg_length": 88.0,
		"stance_width": 0.75,
		# Columns, and this is the correction the whole build turned on. The stance
		# already stands its joints at a hundred and seventy degrees; this leans a
		# few degrees either side of that — the elbow straighter than the knee,
		# which is a real elephant — and takes the fold almost entirely away.
		#
		# What that last number does is the interesting part, because it is not a
		# pose: a joint that cannot close is an animal that cannot crouch, cannot
		# gather, cannot spring, and cannot lengthen its stride by sinking into its
		# own legs. Every one of those was previously either absent or written down
		# somewhere as a special case for heavy animals. Here they are one number,
		# and what is left to move the creature along is the swing of the whole limb
		# from the shoulder and the toe at the end of it.
		"fore_flex_deg": -3.0, "hind_flex_deg": 4.0,
		"fore_fold_range": 0.45, "hind_fold_range": 0.50,
		# Weight carried high: a long humerus and femur over short, thick distal
		# bones. Graviportal proportions, and they are what make the leg read as a
		# pillar rather than as a long shin with a knob at the top.
		"fore_upper_share": 0.58, "hind_upper_share": 0.56,
		"fore_swing_deg": 46.0, "hind_swing_deg": 50.0,
		# It walks on its toes over a fibrous pad, and with the joints doing so
		# little this is most of what actually pushes the animal along.
		"toe_push": 0.60,
		# ...and the tendons insert well out along the bone, at both ends of the
		# animal. A lever geared for force rather than sweep, which is what a limb
		# whose whole job is holding weight against the ground should be — the
		# swing pays for it, and on a leg this heavy the pendulum was already the
		# slower term, so the price was being paid anyway.
		"fore_insertion": 0.36, "hind_insertion": 0.36,
		# The elastic tissue in these legs is real and entirely useless for
		# jumping, which is the interesting half of what this build demonstrates. A
		# store gives its work back by pushing a joint open — see Spring.payout —
		# and a knee that opens by a seventh of the limb returns a seventh of what
		# it holds. So nothing here says an Elephant cannot jump, and nothing here
		# says its tendons are poor: it cannot spend them.
		"fore_spring": 0.30, "hind_spring": 0.30,
		# ...and no turn rate here either, for the opposite reason: nothing needed
		# to say this animal is slow off the mark. It is twenty-three times the
		# Lizard's weight and its muscle only grew with the square of what its
		# bulk grew with the cube of, so it accelerates at under half the Lizard's
		# rate and comes round slower still on a body half as long again.
		"move_speed": 65.0,
		"turn_speed_falloff": 0.70,
		"turn_responsiveness": 5.0, "turn_pivot": 110.0,
		"sprint_multiplier": 1.30, "reverse_speed_factor": 0.40,
		"density": 1.66, "muscle_power": 1.31, "jaw_power": 5.5, "fat_reserve": 1.6,
		# A large heart on the animal with the least muscle per unit of weight in the
		# file, and a walk that is already three quarters of everything it has. The
		# three together are a creature that covers ground all day and cannot chase
		# anything: there is very little of its own speed left to borrow into, and
		# what there is goes quickly.
		"heart_power": 1.20,
		"bite_damage": 2.8, "bite_reach": 34.0, "bite_radius": 22.0,
		"bite_cooldown": 0.70, "chew_interval": 0.60,
		"neck_lift": 0.14,
		# Broad flat molars. The bluntest mouth here: it spreads a very large bite
		# over a very large area, so it crushes and grinds where the Cat opens.
		"tooth_count": 6, "tooth_size": 0.16, "tooth_sharpness": 0.15,
		"jaw_gape_deg": 46.0, "tooth_variation": 0.14,
	},

	# --- and three builds that exist to show the range ------------------------
	# None of the three below carries a gait, a footfall order or an animation.
	# They are bones, weights and angles, exactly as the three above are, and what
	# comes out of them is a rotary gallop, a two-legged stride and a hop —
	# because those are what bodies of those proportions do. The interesting thing
	# about each is which single number is responsible, and that is what the
	# comments say.


	# The same erect stance with the opposite emphasis: a back that folds twice as
	# far as anything else here, legs that can throw the whole animal three times
	# its own height, and almost no weight to throw. Those three are what make a
	# gallop available at all — see Footfall.launch — and speed is what makes it
	# happen, so this build walks, trots and then commits to a suspended,
	# spine-driven bound as it comes up through its own Froude number.
	"Cheetah": {
		"posture": Posture.ERECT,
		# A segment up on the reference: the sheet draws this animal long — a
		# stretched trunk between the girdles and a tail even with it — and the
		# extra station is where both come from. The back stays at full freedom;
		# more joints at the same bend is how it clears the rotary threshold
		# with room to spare.
		"segment_count": 15, "segment_length": 15.0, "max_bend_deg": 34.0,
		"spine_stiffness": 0.80, "spine_damping": 0.70, "body_wave": 4.0,
		"wave_frequency": 0.9, "wave_speed": 2.2,
		# The greyhound outline: deep chest, drawn waist, small skull on a
		# waisted neck — and a tail as long as the trunk and no thicker than a
		# rope, hung off its own base knot instead of tapering out of the hips.
		# It is a rudder at 400 px/s, and it reads as one now.
		"head_width": 9.0, "neck_width": 6.5, "chest_width": 14.0,
		"waist_width": 9.0, "hip_width": 13.0,
		"tail_base_width": 3.0, "tail_tip_width": 1.4,
		"front_limb_t": 0.15, "rear_limb_t": 0.48,
		"arm_length": 52.0, "leg_length": 58.0,
		"stance_width": 0.70,
		# The cat's asymmetry taken further: a foreleg that is nearly a strut over a
		# hind leg that folds tighter than anything else in the file and swings
		# through half again the fan. That is where the gather comes from, and it is
		# the same two rows of the same table an elephant fills in the other
		# direction.
		"fore_flex_deg": -8.0, "hind_flex_deg": 28.0,
		"fore_fold_range": 1.05, "hind_fold_range": 1.45,
		"fore_upper_share": 0.50, "hind_upper_share": 0.44,
		"fore_swing_deg": 62.0, "hind_swing_deg": 84.0,
		"toe_push": 0.70,
		# The highest-geared limbs in the file: tendons right in against the
		# joints, so every contraction is spent on sweep. It is the same trade the
		# long light shin is making — force given up for foot speed — and it is
		# most of why this build's legs turn over the way they do.
		"fore_insertion": 0.28, "hind_insertion": 0.25,
		"fore_spring": 0.40, "hind_spring": 0.65,
		"move_speed": 130.0,
		"turn_speed_falloff": 0.50, "turn_responsiveness": 13.0, "turn_pivot": 44.0,
		"sprint_multiplier": 2.00, "reverse_speed_factor": 0.45,
		"density": 0.57, "muscle_power": 1.89, "jaw_power": 1.0, "fat_reserve": 0.4,
		# The most muscle per unit of weight in the file behind the smallest heart
		# in it, which is the whole of what a cheetah is: everything is spent out of
		# the store, nothing is sustained, and the animal that runs down anything on
		# the plain is also the one that has to stop first.
		"heart_power": 0.70,
		"bite_damage": 2.2, "bite_reach": 34.0, "bite_radius": 12.0,
		"bite_cooldown": 0.30, "chew_interval": 0.38,
		"neck_lift": 0.08,
		"tooth_count": 8, "tooth_size": 0.28, "tooth_sharpness": 0.90,
		"jaw_gape_deg": 54.0, "tooth_variation": 0.18,
	},

	# Two legs, and nothing anywhere says so. `arm_length` is a fifth of
	# `leg_length`, so an arm cannot reach a floor its own shoulder is a whole hind
	# leg above — see Locomotion.BEARING_RATIO — and a body with two limbs it
	# cannot stand on stands on the other two. Everything that follows is the rest
	# of the simulation noticing: the shoulders are carried level over the hips by
	# the back instead of by the forelimbs, the duty factor is quoted against two
	# legs rather than four, the footfall pattern loses its fore girdle, and the
	# arms are held folded against the chest because nothing is holding them out.
	#
	# The heavy head and the long deep tail are the counterweight that makes it
	# possible, and they are ordinary silhouette numbers doing it: mass is read off
	# the drawn body, so a tail is genuinely weight behind the hips.
	"T. rex": {
		"posture": Posture.ERECT,
		"segment_count": 15, "segment_length": 18.0, "max_bend_deg": 12.0,
		"spine_stiffness": 0.93, "spine_damping": 0.55, "body_wave": 2.5,
		"wave_frequency": 0.7, "wave_speed": 1.4,
		# The one build whose tail *should* read as a continuation of the body —
		# a theropod tail is the back half of the animal, thick at the hips and
		# tapering over its whole length — so it keeps the legacy profile with no
		# base knot, and gets more of the spine instead: hips brought forward
		# put two fifths of the animal behind them, which is what makes the
		# counterweight genuinely counterweigh. The neck knot pinches behind a
		# skull that is most of the front end.
		"head_width": 17.0, "neck_width": 12.0, "chest_width": 19.0,
		"waist_width": 15.0, "hip_width": 20.0, "tail_tip_width": 1.5,
		"front_limb_t": 0.20, "rear_limb_t": 0.42,
		# Nearly level, and deliberately not zero: the reference sheet carries
		# this trunk a hair over a tenth of a turn nose-up, which is what a beam
		# balanced over a heavier tail reads as. The counterweight below is what
		# affords it.
		"trunk_lift_deg": 13.0,
		"arm_length": 16.0, "leg_length": 86.0,
		# Narrow, but not on the midline. A two-legged animal tracks close to its
		# own centreline and cannot track *through* it: the feet have to stay either
		# side of the body they are carrying, and a leg this near vertical has very
		# little fold plane left to keep its knee outboard with.
		"stance_width": 0.72,
		# A theropod knee stands markedly bent and stays bent — the bird's crouch —
		# so the hind limb is flexed past its stance rather than straighter than it.
		# The forelimb's articulation is real and entirely academic: nothing is
		# standing on it, so it is held folded against the chest whatever it says.
		"fore_flex_deg": 50.0, "hind_flex_deg": 12.0,
		"fore_fold_range": 1.0, "hind_fold_range": 0.80,
		"fore_upper_share": 0.52, "hind_upper_share": 0.48,
		"fore_swing_deg": 50.0, "hind_swing_deg": 70.0,
		"toe_push": 0.60,
		# Geared a shade for force: four tonnes on two feet is a load path first
		# and a swing second, and the lever leans the way the load does.
		"hind_insertion": 0.32,
		# A bird's leg, and the store goes with the crouch: real but modest, on a
		# body far too heavy for it to be worth much. What comes out is a creature
		# that can get itself off the ground and has no business doing it often.
		"fore_spring": 0.18, "hind_spring": 0.22,
		"move_speed": 205.0,
		"turn_speed_falloff": 0.60, "turn_responsiveness": 7.0, "turn_pivot": 90.0,
		"sprint_multiplier": 1.35, "reverse_speed_factor": 0.45,
		"density": 1.01, "muscle_power": 1.46, "jaw_power": 7.0, "fat_reserve": 0.9,
		# A good heart on four times the reference's weight, and it needs to be: this
		# build walks at three quarters of everything it has, so the band it can
		# borrow into is narrow and it is into it the moment the key goes down.
		"heart_power": 1.05,
		"bite_damage": 4.0, "bite_reach": 40.0, "bite_radius": 20.0,
		"bite_cooldown": 0.60, "chew_interval": 0.55,
		"neck_lift": 0.16,
		"tooth_count": 11, "tooth_size": 0.30, "tooth_sharpness": 0.70,
		"jaw_gape_deg": 62.0, "tooth_variation": 0.22,
	},

	# The same two-legged arithmetic with the spring turned all the way up. Arms a
	# third of the legs, so it is bipedal for exactly the reason the T. rex is —
	# and a hind limb that is a folded Z of elastic tissue, so the moment it is
	# going fast enough for its size the two hind limbs stop alternating and land
	# together. That is a hop, and it is the same collapse of `hind_split` that
	# turns a Cheetah's gallop into a bound; there is one mechanism, and a body
	# with only two legs on the ground makes it look like a different animal.
	#
	# Below the transition it goes back to alternating steps, which is right: a
	# kangaroo moving slowly does not hop either.
	"Kangaroo": {
		"posture": Posture.ERECT,
		"segment_count": 12, "segment_length": 16.0, "max_bend_deg": 20.0,
		"spine_stiffness": 0.88, "spine_damping": 0.62, "body_wave": 2.0,
		"wave_frequency": 0.8, "wave_speed": 1.6,
		# A thick muscular tail that is nevertheless its own structure: the base
		# knot steps it down from the rump — a stout root that stays deeper than
		# anything the Lizard trails, because this tail is the third leg of the
		# tripod rest and a working counterweight to the hop, not a tapering
		# body. Small skull on a real neck, heavy hindquarters over a drawn
		# waist.
		"head_width": 7.0, "neck_width": 5.0, "chest_width": 13.0,
		"waist_width": 11.0, "hip_width": 16.0,
		"tail_base_width": 12.5, "tail_tip_width": 3.5,
		"front_limb_t": 0.20, "rear_limb_t": 0.42,
		# Reared: the trunk is carried most of the way to upright over the hips,
		# which is what a kangaroo *is* from the side — a Z of leg, a near
		# vertical body and a tail closing the tripod. The heavier tail above is
		# the other half of the same stance.
		"trunk_lift_deg": 50.0,
		"arm_length": 22.0, "leg_length": 62.0,
		"stance_width": 0.50,
		# Folded to a Z and built to open: the deepest crouch and the longest foot
		# in the file, which between them are a hop.
		"fore_flex_deg": 46.0, "hind_flex_deg": 30.0,
		"fore_fold_range": 1.0, "hind_fold_range": 1.50,
		"fore_upper_share": 0.52, "hind_upper_share": 0.42,
		"fore_swing_deg": 50.0, "hind_swing_deg": 78.0,
		"toe_push": 0.85,
		# Tendons in close on the hind pair — the gastrocnemius end of the same
		# rope the spring row below describes, geared for the sweep a hop is.
		"hind_insertion": 0.26,
		# Nearly all rope. The whole hind limb below the knee is a spring wound
		# along the longest foot in the file, which is the other half of what makes
		# this a hop rather than a stride — and the reason the same animal is a
		# poor walker: a store is cheap to bounce on and expensive to carry.
		"fore_spring": 0.25, "hind_spring": 0.95,
		"move_speed": 170.0,
		"turn_speed_deg": 60.0,
		"turn_speed_falloff": 0.55, "turn_responsiveness": 9.0, "turn_pivot": 60.0,
		"sprint_multiplier": 2.35, "reverse_speed_factor": 0.40,
		"density": 0.64, "muscle_power": 2.09, "jaw_power": 0.8, "fat_reserve": 0.8,
		# A shade under the reference on a light body that carries plenty of muscle,
		# which leaves it an ordinary store and the widest band in the file to spend
		# it across: it walks at under half of what it has. The hop it is famous for
		# being cheap at is the tendon in the row above rather than anything here.
		"heart_power": 0.95,
		"bite_damage": 1.6, "bite_reach": 26.0, "bite_radius": 9.0,
		"bite_cooldown": 0.50, "chew_interval": 0.45,
		"neck_lift": 0.12,
		"tooth_count": 8, "tooth_size": 0.12, "tooth_sharpness": 0.15,
		"jaw_gape_deg": 44.0, "tooth_variation": 0.14,
	},
}


## Copies every schema-listed property from `other` onto this resource.
func copy_from(other: CreatureParams) -> void:
	for row in SCHEMA:
		if row.has("prop"):
			set(row["prop"], other.get(row["prop"]))


## Applies a PRESETS entry on top of a fresh set of defaults.
func apply_preset(preset_name: String) -> void:
	copy_from(CreatureParams.new())
	var overrides: Dictionary = PRESETS.get(preset_name, {})
	for key in overrides:
		set(key, overrides[key])
