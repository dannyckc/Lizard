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
## How this animal holds its legs under it: 0 sprawled, 1 semi-upright, 2 erect,
## 3 columnar — ordered by the trait itself, the angle the limbs are carried out
## of the ground plane. See Posture — one trait, and the stance width, the body
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


## The six template builds, re-derived from the living animals.
##
## A preset is bones, weights and angles, and nothing else. No entry below
## carries a gait, a footfall order, a stride length, a step time, a height or a
## "bipedal" flag, because every one of those is measured off the body each tick:
## an Elephant ambles because its knees do not fold, and a T. rex walks on two
## legs because its arms measure too short to bear. What a sheet is allowed to
## say is what a skeleton is — how long the chain is, how wide the animal is
## drawn at seven knots, where the girdles hang, what angle each joint is carried
## at, what the tissue is made of, and how fast the species asks to go.
##
## Every number below is a measurement of the real animal, translated into the
## game's units rather than invented in them. Proportions carry over directly:
## where along itself a species hangs its hips, how its limb divides between the
## two bones, what fraction of its length is tail, how much longer the hind pair
## is than the fore. Absolute scale does not — the world compresses leg length
## and height for the top-down picture (see Footfall.FROUDE_WALK for the same
## compression stated about speed) — so lengths are placed by ratio against the
## reference chain, and the derivation for each is written where the number is.
##
## Each entry is laid out in the order the derivation runs — spine, silhouette,
## girdles, height, limbs, articulation, elastic, physique, drive — so it reads
## top to bottom the way the body is built. Three groups appear at the bottom of
## an entry without appearing on its sheet, and they are the ones the body plan
## puts outside its own scope: solver feel (how the verlet chain is relaxed), the
## turn tuning, and the combat and dentition numbers.
##
## Anything omitted keeps the class default, so an entry reads as what it is: the
## difference between this animal and the reference build. The reference build is
## the *class defaults*, not any entry here: it is the calibration origin every
## constant in the file is quoted against, and it stays put when a species is
## retuned — which is why even the Lizard now carries a sheet of its own.
##
## The physique rows are worth reading as a set. Mass is not listed anywhere
## because it is not a setting — the silhouette above each `density` already
## decides most of it, and those four numbers only say what kind of animal that
## silhouette is made of: how solid, how strong for its size, what circulation is
## behind it and how much of it is fat. `fast_twitch` is finally spent here too:
## it was parked at the mixed default on every old sheet, and it is most of what
## separates a reptile's getaway from an elephant's shove — real muscle is not
## the same tissue in the two of them, and now the sheets say so.
const PRESETS: Dictionary = {
	# 01 · LIZARD · SPRAWLED · TILT 12° · JOINT 102°
	#
	# A large terrestrial lizard — a monitor is the model. The build the class
	# defaults were authored as, so its sheet is short: what is written is where
	# a real lizard disagrees with the reference origin, and everything omitted
	# is a statement that the origin already measured this animal.
	#
	# The skeleton first. A lizard is mostly tail — 1.3 to 1.5 snout-vent lengths
	# of it on a monitor — so the vent sits at 0.42 of the animal and the whole
	# 58% behind it tapers away smoothly: no base knot and no neck knot, because
	# a lizard genuinely is one unbroken spindle from snout to tip. The hind
	# limbs are a third longer than the fore (the sprint pair — the fastest
	# lizards lift their forelimbs off the ground entirely), and the femur is
	# swung through a wide arc from the hip while the shoulder rows a narrower
	# one, which is the sprawled stride: retraction of the whole limb, not
	# flexion of its joints.
	#
	# What a stance is worth it demonstrates on its own: sin(12°) starves the
	# launch term, so the asymmetric regime never opens however hard the body is
	# driven — flat out is a trot, and nothing anywhere forbids it a gallop. The
	# stride given up to that is bought back by the back: `wave_gain` is 1.0 at
	# this stance and no other, and 24° over fourteen stations is a spine that
	# genuinely walks.
	#
	# The physique is the reptile half of the sheet. Squamate locomotor muscle
	# is fast glycolytic fibre nearly throughout — a lizard is thrown by tissue
	# built to spend — and the circulation behind it cannot keep any of it up:
	# a three-chambered heart, and lungs a running trunk flexes sideways
	# through (Carrier's constraint — a sprinting lizard can barely breathe).
	# So: fast_twitch well above the mixed default, a heart well below the
	# reference mammal's, and a getaway animal that must stop when the store
	# does. The fat lives in the tail, and there is not much of it.
	"Lizard": {
		"max_bend_deg": 24.0,
		"body_wave": 6.0, "wave_frequency": 0.85,
		# One smooth spindle: chest the widest station, head most of a chest
		# wide on almost no neck, and the tail a plain continuation of the hips
		# down to a whip tip.
		"head_width": 12.0, "chest_width": 15.0, "waist_width": 11.5,
		"hip_width": 12.5, "tail_tip_width": 1.0,
		"front_limb_t": 0.15, "rear_limb_t": 0.42,
		# Hind limb 0.55 of snout-vent length, forelimb 0.40 — the monitor's
		# ratio, and the reason the hips ride higher than the shoulders: the
		# same stance angle on a longer bone is more clearance.
		"arm_length": 34.0, "leg_length": 44.0, "stance_width": 0.95,
		"fore_swing_deg": 60.0, "hind_swing_deg": 72.0,
		# Long toes on a flat foot: real push at the end of a rowing stance,
		# and nothing like a digitigrade's.
		"toe_push": 0.20,
		# Reptile tendon stores next to nothing — the spring in a lizard start
		# is the muscle itself.
		"fore_spring": 0.10, "hind_spring": 0.15,
		"fast_twitch": 0.72, "heart_power": 0.75, "fat_reserve": 0.9,
		"move_speed": 95.0, "sprint_multiplier": 1.90,
		"turn_responsiveness": 13.0, "turn_pivot": 42.0,
		# A pleurodont mouth: many small keen teeth in a wide gape, none of
		# them specialised, replaced throughout life — a mouth for holding and
		# tearing small prey rather than for killing large.
		"jaw_power": 0.9, "bite_damage": 2.0, "bite_reach": 28.0,
		"bite_radius": 15.0, "bite_cooldown": 0.40,
		"tooth_count": 14, "tooth_size": 0.12, "tooth_sharpness": 0.68,
		"jaw_gape_deg": 72.0, "tooth_variation": 0.22,
	},

	# 02 · CAT · SEMI-UPRIGHT · TILT 50° · JOINT 132°
	#
	# The domestic cat, measured: 46 cm of head and body ahead of 30 cm of tail
	# — the tail base at 0.56 of the animal — on a chain of twelve stations,
	# because a cat's back is short and extraordinarily mobile for its length.
	# The intermembral ratio is the felid 0.80: forelimb four fifths of the
	# hind, and the two ends do opposite jobs with it. In front a strut, the
	# elbow carried 16° straighter than its stance, there to hold the front of
	# the animal up and to land on. Behind an engine: the knee stands 20° more
	# flexed, folds a quarter past its stance, swings a far wider fan and
	# carries the longer, lighter shank — the crouch, the gather and the leap.
	# Nothing arranges the level back: a longer hind limb folded further and a
	# shorter foreleg held straight clear the ground by the same amount.
	#
	# The bend budget is deliberately one notch short of the Cheetah's: a cat's
	# gallop is transverse — the back works, but it is the dorsomobile
	# specialist a station further on that reverses its leads. See
	# Footfall.ROTARY_SPINE, which is the line the two sheets straddle.
	#
	# Digitigrade — it already stands on its toes, and there is real push
	# there. The physique is an ambush hunter's: fast fibre well over the mixed
	# default, half again the muscle for its weight, a heart a shade under the
	# reference — an animal built to spend hard for seconds and then stop.
	"Cat": {
		"posture": Posture.SEMI_UPRIGHT,
		"segment_count": 12, "segment_length": 14.0, "max_bend_deg": 26.0,
		"body_wave": 4.5, "wave_frequency": 0.9, "wave_speed": 2.0,
		# A round skull on a waisted neck; a rope of a tail hung off a rounded
		# rump. The base knot steps the profile down behind the pelvis to a
		# third of the hip and it barely tapers from there — a cat's tail is a
		# near-constant section, and it is real counterweight behind the hips.
		"head_width": 11.5, "neck_width": 8.5, "chest_width": 14.5,
		"waist_width": 11.5, "hip_width": 14.0,
		"tail_base_width": 5.0, "tail_tip_width": 2.2,
		"front_limb_t": 0.16, "rear_limb_t": 0.52,
		"neck_lift": 0.10,
		"arm_length": 38.0, "leg_length": 47.0, "stance_width": 0.85,
		"fore_flex_deg": -16.0, "hind_flex_deg": 20.0,
		"fore_fold_range": 0.92, "hind_fold_range": 1.25,
		"fore_upper_share": 0.50, "hind_upper_share": 0.46,
		"fore_swing_deg": 58.0, "hind_swing_deg": 76.0,
		"toe_push": 0.50,
		# The hind tendons come in close to the joint — a lever geared a shade
		# for speed, which is what lets the engine end turn its legs over
		# quicker than the strut end without carrying different muscle. The
		# foreleg stays at the reference insertion, an exact no-op.
		"hind_insertion": 0.27,
		# ...and a good deal of rope behind it. The girdle that folds tighter
		# than its stance is the only one with travel to wind a store with,
		# which is why the spring sits where the fold does. The foreleg's share
		# is spent on landings rather than take-offs.
		"fore_spring": 0.30, "hind_spring": 0.60,
		"density": 0.65, "muscle_power": 1.60, "fast_twitch": 0.68,
		"heart_power": 0.90, "fat_reserve": 0.9,
		"move_speed": 88.0, "sprint_multiplier": 1.85,
		"spine_stiffness": 0.88, "spine_damping": 0.64,
		"turn_speed_deg": 210.0, "turn_responsiveness": 14.0, "turn_pivot": 38.0,
		"turn_speed_falloff": 0.50, "reverse_speed_factor": 0.60,
		# Thirty teeth in a short-muzzled skull: long canines with a nerve-fine
		# kill spot, carnassials behind them, and almost nothing else — a
		# killing mouth, all point and no grinding surface.
		"jaw_power": 1.15, "bite_damage": 2.5, "bite_reach": 30.0,
		"bite_radius": 13.0, "bite_cooldown": 0.30, "chew_interval": 0.35,
		"tooth_count": 7, "tooth_size": 0.32, "tooth_sharpness": 0.95,
		"jaw_gape_deg": 62.0, "tooth_variation": 0.15,
	},

	# 03 · ELEPHANT · COLUMNAR · TILT 72° · JOINT 170°
	#
	# The African bush elephant: the graviportal extreme, and the sheet where
	# almost every row is the same fact — weight — measured somewhere else.
	#
	# The stance already stands its joints at 170°; this leans a few degrees
	# either side of that — elbow straighter than knee, which is a real
	# elephant — and then takes the fold almost entirely away. That last number
	# is the whole build, because it is not a pose: a joint that cannot close
	# is an animal that cannot crouch, cannot gather, cannot spring, and cannot
	# lengthen its stride by sinking into its own legs. What is left to move it
	# along is the swing of the whole limb from the shoulder and the toe at the
	# end of it — the real animal walks on its toe tips over a fibrous heel
	# pad, however flat its foot looks from outside.
	#
	# The proportions are measured ones. Shoulder height roughly equals body
	# length on a bush elephant, the forelimb is the longer pair (the shoulder
	# is its highest point), the humerus and femur are long over short thick
	# distal bones (upper shares near the graviportal ceiling), and the tail is
	# a rope with a tuft — about a quarter of the animal, clipped short, hung
	# off rounded hindquarters. The skull is enormous and sits directly on the
	# pectoral girdle: an elephant has almost no neck, and the head is carried
	# high because the shoulder it rides on is.
	#
	# Its top speed never crosses FROUDE_WALK — the hip is a whole leg off the
	# ground and mass cubes where muscle squares — so the run is an amble, and
	# nothing had to forbid a gallop. The physique says why twice over: muscle
	# that is the slowest fibre in the file (elephant locomotor muscle is
	# overwhelmingly slow-oxidative — tissue built to hold weight up all day),
	# behind the largest heart in it. An animal that covers ground from dawn to
	# dark and cannot chase anything.
	"Elephant": {
		"posture": Posture.COLUMNAR,
		"segment_count": 16, "segment_length": 19.0, "max_bend_deg": 9.0,
		"body_wave": 2.5,
		# One deep barrel: chest and hips nearly the same station, almost no
		# waist between them, and a head most of a chest wide blending straight
		# into the shoulders with no neck knot at all.
		"head_width": 24.0, "chest_width": 33.0, "waist_width": 30.0,
		"hip_width": 31.0, "tail_base_width": 2.5, "tail_tip_width": 1.5,
		"tail_length": 0.60,
		"front_limb_t": 0.14, "rear_limb_t": 0.56,
		"neck_lift": 0.15,
		# Held nearly vertical, so the clearance is most of the leg and the
		# plan-view reach under a third of it, which is what lands the feet
		# close beneath the body — an elephant's trackway is famously narrow.
		"arm_length": 92.0, "leg_length": 88.0, "stance_width": 0.70,
		"fore_flex_deg": -2.0, "hind_flex_deg": 5.0,
		"fore_fold_range": 0.45, "hind_fold_range": 0.50,
		"fore_upper_share": 0.60, "hind_upper_share": 0.57,
		"fore_swing_deg": 45.0, "hind_swing_deg": 49.0,
		"toe_push": 0.60,
		# Tendons well out along the bone at both ends: a lever geared for
		# force rather than sweep, which is what a limb whose whole job is
		# holding weight against the ground should be. The swing pays for it,
		# and on a leg this heavy the pendulum was the slower term already.
		"fore_insertion": 0.38, "hind_insertion": 0.37,
		# The heel pads are real elastic tissue and entirely useless for
		# jumping: a store gives its work back by pushing a joint open, and a
		# knee that opens by a seventh of the limb returns a seventh of what it
		# holds. Nothing here says an Elephant cannot jump. It cannot spend them.
		"fore_spring": 0.25, "hind_spring": 0.25,
		"density": 1.42, "muscle_power": 1.30, "fast_twitch": 0.25,
		"heart_power": 1.25, "fat_reserve": 1.7,
		"move_speed": 62.0, "sprint_multiplier": 1.35,
		"spine_stiffness": 0.95, "spine_damping": 0.50,
		"turn_speed_deg": 120.0, "turn_speed_falloff": 0.70,
		"turn_responsiveness": 5.0, "turn_pivot": 115.0,
		"reverse_speed_factor": 0.40,
		# Four molars the size of bricks, worked fore-and-aft: the bluntest
		# mouth in the file, spreading an enormous bite over an enormous area.
		# It crushes and grinds where the Cat's opens.
		"jaw_power": 6.0, "bite_damage": 2.7, "bite_reach": 33.0,
		"bite_radius": 22.0, "bite_cooldown": 0.75, "chew_interval": 0.65,
		"tooth_count": 5, "tooth_size": 0.15, "tooth_sharpness": 0.10,
		"jaw_gape_deg": 42.0, "tooth_variation": 0.12,
	},

	# 04 · CHEETAH · ERECT · TILT 66° · JOINT 150°
	#
	# The fastest terrestrial animal, and a sheet that is one sentence said
	# five ways: everything is spent on stride rate. The build is the Cat's
	# asymmetry taken to its limit — a near-strut foreleg over a hind leg that
	# folds tighter than anything else in the file and swings half again the
	# fan — on limbs half as long again for the body, a drawn waist, and a
	# skull shrunk to a dome (a cheetah's head is small even for its weight;
	# the airway through it is not).
	#
	# The back is what makes it a different gait rather than a faster one.
	# Fifteen stations at 36° of bend put `spine_freedom` clear of ROTARY_SPINE,
	# so past 0.70 of a gather the fore split reverses and the gallop comes out
	# rotary, doubly suspended — the dorsomobile cycle the real animal runs,
	# with the spine adding and removing a sixth of body length every stride.
	# The tail is the other flight surface: as long as the trunk, thick enough
	# to steer with, hung off its own base knot. A rudder at speed.
	#
	# The physique is the sprint stated as tissue. Cheetah locomotor muscle is
	# the fastest measured in any large mammal — the sheet's highest fibre
	# share — behind the file's highest-geared tendons (insertions right in
	# against both joints) and its biggest hind spring share. What bounds the
	# chase in life is heat: it cannot dump what thirty seconds of this
	# produces. The simulation has no thermometer, so the same wall is stated
	# through the one organ that means "cannot keep it up" here — the smallest
	# heart in the file, on the most muscle. Nothing is sustained; everything
	# is spent out of the store; the animal that runs down anything on the
	# plain is the one that has to stop first.
	"Cheetah": {
		"posture": Posture.ERECT,
		"segment_count": 15, "segment_length": 15.0, "max_bend_deg": 36.0,
		"body_wave": 3.5, "wave_frequency": 0.9, "wave_speed": 2.2,
		# Deep-chested and drawn in hard at the loin: the coursing outline. The
		# small domed skull rides a long waisted neck.
		"head_width": 8.5, "neck_width": 6.0, "chest_width": 15.0,
		"waist_width": 10.0, "hip_width": 14.0,
		"tail_base_width": 3.5, "tail_tip_width": 1.8,
		"front_limb_t": 0.15, "rear_limb_t": 0.52,
		"neck_lift": 0.09,
		# The leggiest quadruped here: shoulder height ~0.65 of head-and-body
		# on the real animal, against the Cat's ~0.45, and the forelimb nearly
		# the hind's equal (intermembral ~0.9 — a galloper drives with both
		# ends where a leaper drives with one).
		"arm_length": 53.0, "leg_length": 59.0, "stance_width": 0.65,
		"fore_flex_deg": -6.0, "hind_flex_deg": 26.0,
		"fore_fold_range": 1.10, "hind_fold_range": 1.45,
		"fore_upper_share": 0.49, "hind_upper_share": 0.44,
		"fore_swing_deg": 66.0, "hind_swing_deg": 86.0,
		# Digitigrade on semi-retractable claws that grip like track spikes.
		"toe_push": 0.65,
		# Tendons right in against the joints, so every contraction is spent on
		# sweep. The same trade the long light shin is making — force given up
		# for foot speed — and most of why these legs turn over the way they do.
		"fore_insertion": 0.27, "hind_insertion": 0.24,
		"fore_spring": 0.45, "hind_spring": 0.70,
		"density": 0.62, "muscle_power": 1.95, "fast_twitch": 0.85,
		"heart_power": 0.65, "fat_reserve": 0.4,
		"move_speed": 135.0, "sprint_multiplier": 2.00,
		"spine_stiffness": 0.80, "spine_damping": 0.70,
		# The falloff is the lowest of the fast builds: a cheetah corners at
		# speed — the tail and the claws are for exactly that — where every
		# other sprinter has to slow first.
		"turn_speed_deg": 175.0, "turn_speed_falloff": 0.45,
		"turn_responsiveness": 13.0, "turn_pivot": 45.0,
		"reverse_speed_factor": 0.45,
		# The weakest bite of any big cat — the skull gave its muscle room to
		# the airway, and the kill is a clamp on the windpipe held for minutes
		# rather than a puncture. Small canines, keen cheek teeth.
		"jaw_power": 0.9, "bite_damage": 2.0, "bite_reach": 33.0,
		"bite_radius": 12.0, "bite_cooldown": 0.30, "chew_interval": 0.38,
		"tooth_count": 7, "tooth_size": 0.24, "tooth_sharpness": 0.85,
		"jaw_gape_deg": 52.0, "tooth_variation": 0.18,
	},

	# 05 · T. REX · ERECT · BIPED BY MEASUREMENT
	#
	# Tyrannosaurus rex off the skeletal reconstructions: twelve metres nose to
	# tail tip with the hip joint almost exactly halfway along, a skull a
	# twelfth of the animal on a thick S-curved neck, a tail that is the entire
	# back half, and an arm a quarter the hind limb's length. That last ratio
	# is the sheet's one deliberate demonstration: an arm of 25 cannot reach a
	# floor its own shoulder is a leg of 88 above, so it falls under
	# leg × BEARING_RATIO and the forelimbs stop bearing. Everything after that
	# is the rest of the simulation noticing — the shoulders are carried by the
	# back instead of the arms, duty and footfall are quoted against two legs,
	# and the arms are held folded against the chest because nothing is holding
	# them out.
	#
	# Hips at the real animal's halfway point put half of it behind them, and
	# mass is read off the drawn silhouette, so the tail genuinely
	# counterweighs — caudofemoral retraction made a T. rex's tail a third of
	# its locomotor muscle, which is why it is drawn as deep as the hips and
	# tapering over its whole length with no base knot: a theropod tail is not
	# hung off the body, it *is* the body. That counterweight is what affords
	# the near-level trunk: 12° is a beam balanced over a heavier tail, and it
	# is deliberately not zero. It is also why the tail never props a slow
	# walk the way the Kangaroo's does — carried at 12° it runs out behind the
	# animal a whole hip height off the floor. See Locomotion.tail_prop.
	#
	# The knee stands markedly bent and stays bent — the bird's crouch, on the
	# bird's leg: a long tibia and arctometatarsus below a shorter femur, and
	# the fold shallow, because eight tonnes does not gather itself deeply onto
	# one pair of joints. Biomechanics puts its top speed under 30 km/h, a fast
	# walk rather than a run, and nothing here asserts it: the mass, the crouch
	# and the fibre deliver it.
	"T. rex": {
		"posture": Posture.ERECT,
		"segment_count": 16, "segment_length": 19.5, "max_bend_deg": 13.0,
		"body_wave": 2.5, "wave_frequency": 0.7, "wave_speed": 1.4,
		"head_width": 21.0, "neck_width": 15.0, "chest_width": 24.0,
		"waist_width": 19.0, "hip_width": 25.0, "tail_tip_width": 1.3,
		"front_limb_t": 0.19, "rear_limb_t": 0.47,
		"neck_lift": 0.15, "trunk_lift_deg": 12.0,
		# Narrow, but not on the midline: a two-legged animal tracks close to
		# its own centreline and cannot track through it.
		"arm_length": 25.0, "leg_length": 88.0, "stance_width": 0.70,
		# The forelimb's articulation is real and entirely academic: nothing
		# stands on it, so it is folded against the chest whatever it says.
		"fore_flex_deg": 55.0, "hind_flex_deg": 14.0,
		"hind_fold_range": 0.78,
		"fore_upper_share": 0.55, "hind_upper_share": 0.46,
		"fore_swing_deg": 50.0, "hind_swing_deg": 72.0,
		# Digitigrade on three spreading toes — most of a metre of foot rolling
		# the animal over each stance.
		"toe_push": 0.60,
		# Geared a shade for force: eight tonnes on two feet is a load path
		# first and a swing second, and the lever leans the way the load does.
		"hind_insertion": 0.33,
		# A bird's leg, and the store goes with the crouch: real but modest, on
		# a body far too heavy for it to be worth much.
		"fore_spring": 0.20, "hind_spring": 0.25,
		# Pneumatised skull and vertebrae over a dense hindquarter — near water
		# overall — carrying the most absolute muscle in the file at a middling
		# fibre mix: a tyrannosaur was no sprinter, and its prey were slower.
		"density": 1.15, "muscle_power": 1.50, "fast_twitch": 0.42,
		"heart_power": 1.05, "fat_reserve": 0.9,
		"move_speed": 205.0, "sprint_multiplier": 1.30,
		"spine_stiffness": 0.93, "spine_damping": 0.55,
		"turn_speed_deg": 140.0, "turn_speed_falloff": 0.60,
		"turn_responsiveness": 7.0, "turn_pivot": 95.0,
		"reverse_speed_factor": 0.45,
		# The hardest bite of any terrestrial animal ever measured, delivered
		# through banana-thick serrated spikes set in a metre and a half of
		# skull: teeth built to shatter bone rather than to slice, so they are
		# stout and only moderately keen, and the damage is depth.
		"jaw_power": 8.5, "bite_damage": 4.5, "bite_reach": 42.0,
		"bite_radius": 21.0, "bite_cooldown": 0.65, "chew_interval": 0.55,
		"tooth_count": 12, "tooth_size": 0.32, "tooth_sharpness": 0.62,
		"jaw_gape_deg": 64.0, "tooth_variation": 0.25,
	},

	# 06 · KANGAROO · ERECT · BIPED · HIND SPRING 0.95
	#
	# The red kangaroo: the same two-legged arithmetic as the T. rex with every
	# remaining row pushed to the macropod extreme. Arms a third of the legs,
	# so it is bipedal for exactly the reason the T. rex is; then the deepest
	# crouch in the file (the Z-folded rest limb), the longest foot in it (a
	# third of the hind limb is foot — the family is named for it), and a hind
	# limb that is mostly rope below the knee: the gastrocnemius and plantaris
	# tendons that make the hop cheaper the faster it goes.
	#
	# The hop is not a gait anything selects. Past its own transition
	# `hind_split` collapses and the two hind limbs stop alternating and land
	# together — the identical collapse that turns the Cheetah's gallop into a
	# bound, on a body with only two legs on the ground.
	#
	# Below the transition the real animal cannot alternate at all: large
	# macropods are anatomically unable to stride their hind legs out of phase
	# on the ground, and what they do instead is the pentapedal crawl — plant
	# the tail, swing both hind feet forward past it as one. The sheet is built
	# to afford exactly that and the gait engine now delivers it: the trunk is
	# reared 55° over the hips (a kangaroo from the side is a Z of leg, a near
	# vertical body and a tail closing the tripod), so a tail that is nearly
	# half the animal runs *down* from the pelvis and reaches the floor with
	# girth to spare — see Locomotion.tail_prop, which measures precisely this,
	# and finds nothing on the level-trunked T. rex.
	#
	# The tail carries a fifth of the animal's muscle in life, and the base
	# knot says so: a stout root stepped down from heavy hindquarters, its own
	# structure and not a tapering body.
	"Kangaroo": {
		"posture": Posture.ERECT,
		"segment_count": 12, "segment_length": 16.0, "max_bend_deg": 22.0,
		"body_wave": 2.0,
		# Slight shoulders, heavy hindquarters: the whole animal deepens toward
		# its engine. A small deer-like skull on a real neck.
		"head_width": 7.0, "neck_width": 5.0, "chest_width": 13.0,
		"waist_width": 12.0, "hip_width": 17.0,
		"tail_base_width": 12.0, "tail_tip_width": 3.5,
		"front_limb_t": 0.19, "rear_limb_t": 0.46,
		"neck_lift": 0.13, "trunk_lift_deg": 55.0,
		"arm_length": 22.0, "leg_length": 62.0, "stance_width": 0.50,
		"fore_flex_deg": 46.0, "hind_flex_deg": 30.0,
		"hind_fold_range": 1.50,
		# Femur 0.30 of the limb, tibia 0.35, foot the rest: the shortest upper
		# share the chain allows, under a toe that is most of the propulsion.
		"hind_upper_share": 0.40,
		"fore_swing_deg": 48.0, "hind_swing_deg": 80.0,
		"toe_push": 0.90,
		# Tendons in close on the hind pair — the gastrocnemius end of the same
		# rope the spring row describes, geared for the sweep a hop is.
		"hind_insertion": 0.25,
		# Nearly all rope. The whole hind limb below the knee is a spring wound
		# along the longest foot in the file, which is the other half of what
		# makes this a hop rather than a stride — and the reason the same
		# animal is a poor walker: a store is cheap to bounce on and expensive
		# to carry.
		"fore_spring": 0.25, "hind_spring": 0.95,
		# The hop's economy is the tendon, not the heart — but the heart is a
		# sound one, because a red kangaroo covers desert distances: an
		# ordinary store behind the widest band in the file to spend it across.
		"density": 0.66, "muscle_power": 2.00, "fast_twitch": 0.62,
		"heart_power": 1.00, "fat_reserve": 0.7,
		"move_speed": 165.0, "sprint_multiplier": 2.30,
		"spine_stiffness": 0.88, "spine_damping": 0.62,
		"turn_speed_deg": 65.0, "turn_speed_falloff": 0.55,
		"turn_responsiveness": 9.0, "turn_pivot": 60.0,
		"reverse_speed_factor": 0.40,
		# A grazer's mouth: incisors in front, a molar battery behind, and a
		# gap where a predator keeps its canines. Nothing here is a weapon —
		# the animal's weapon is the same hind limb everything else is.
		"jaw_power": 0.75, "bite_damage": 1.5, "bite_reach": 25.0,
		"bite_radius": 9.0, "bite_cooldown": 0.50, "chew_interval": 0.45,
		"tooth_count": 7, "tooth_size": 0.11, "tooth_sharpness": 0.12,
		"jaw_gape_deg": 40.0, "tooth_variation": 0.14,
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
