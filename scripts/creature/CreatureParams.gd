## All tunable numbers for the creature, in one place.
##
## This is a Resource so it can be edited in the Inspector, saved as a .tres
## preset, and swapped at runtime. SCHEMA below mirrors the exported properties
## and is what the in-game tuning panel builds its sliders from — add a property
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
## Where along the spine (0 = head, 1 = tail tip) the limbs attach.
@export_range(0.02, 0.5, 0.01) var front_limb_t: float = 0.16
@export_range(0.2, 0.9, 0.01) var rear_limb_t: float = 0.46

# -------------------------------------------------------------- posture ----
@export_group("Posture")
## How this animal holds its legs under it: 0 sprawled, 1 semi-upright, 2
## columnar. See Posture — one trait, and the stance width, the body clearance,
## how much of the upper limb the torso stands over, how much the spine
## undulates, how many feet stay down and how readily the animal turns all come
## out of it. It is an anatomical category, not a tuning group: two creatures
## with the same numbers and different postures are different animals.
@export_range(0, 2, 1) var posture: int = Posture.SPRAWLED

# --------------------------------------------------------------- height ----
@export_group("Height")
## How far above the shoulder the head is carried, as a fraction of the animal's
## own length. Zero is a head held in the plane of the body — a lizard. Large is
## a browser, and the whole of what makes one: a long neck raises what the jaws
## can reach without touching anything else about the creature.
@export_range(0.0, 0.6, 0.01) var neck_lift: float = 0.0
## Peak of a standing leap, as a multiple of the animal's own standing height.
## Zero is a body that cannot leave the ground, which is a real answer — a heavy
## columnar animal has no way to throw itself into the air, and nothing had to
## forbid it.
@export_range(0.0, 4.0, 0.05) var leap_height: float = 0.6
## Lift the wings generate, zero on anything without them. It is the only thing
## separating a creature that can glide and fly from one that can only leap:
## with none, the two airborne states are simply unreachable — see Elevation.
@export_range(0.0, 2.0, 0.05) var wing_lift: float = 0.0

# ---------------------------------------------------------------- limbs ----
@export_group("Limbs")
## Total reach of a two-bone chain (split 52% upper / 48% lower).
@export_range(8.0, 120.0, 1.0) var arm_length: float = 34.0
@export_range(8.0, 120.0, 1.0) var leg_length: float = 40.0
## Rest foot distance from its anchor, as a fraction of total limb length.
## Keep below 1.0 so the IK chain is never locked straight.
@export_range(0.3, 0.98, 0.01) var stance_reach: float = 0.78
## How far out to the side the rest stance sits (relative to fore/aft bias).
@export_range(0.2, 2.0, 0.01) var stance_width: float = 1.0
## Furthest a foot may get from its socket, as a fraction of total limb length.
## This is a hard limit on the working envelope, not a target: a foot the body
## has outrun skids along it instead of pulling the leg straight. Keep it under
## 1.0 or a dragged limb stops reading as a limb.
@export_range(0.5, 1.0, 0.01) var limb_max_reach: float = 0.94
## Half-angle of the fan a foot may swing through, measured from its rest
## stance. Stops a limb the body has walked past from folding forward under the
## chin or trailing back alongside the tail.
@export_range(20.0, 110.0, 1.0) var limb_swing_deg: float = 62.0
## FABRIK relaxation passes per limb per tick.
@export_range(1, 12, 1) var fabrik_iterations: int = 6

# ----------------------------------------------------------------- gait ----
@export_group("Gait")
## A planted foot stays put until it drifts this far from its ideal position.
@export_range(4.0, 90.0, 0.5) var stride_distance: float = 26.0
## Fake vertical lift at the top of the step arc (drawn as a screen offset).
@export_range(0.0, 40.0, 0.5) var step_height: float = 9.0
## Step time at a standstill; shortens automatically as speed rises.
@export_range(0.05, 1.2, 0.01) var step_duration: float = 0.26
## How far ahead of the body feet aim while moving (fraction of stride).
@export_range(0.0, 1.5, 0.01) var foot_lead: float = 0.45
## How eagerly the diagonal partner joins the same beat. 0 = independent legs.
@export_range(0.0, 1.0, 0.01) var diagonal_coupling: float = 0.55
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
## How much fat the species lays down, as a multiple of the body plan's profile —
## thickest over the trunk, thinning toward the head, tail and limbs. It is not a
## damage-resistance number: fat is a real layer in the depth stack, so a padded
## creature is heavier, and the same jaws reach its muscle shallower because the
## fat spent part of the bite getting there. 0 is an animal with none.
@export_range(0.0, 3.0, 0.05) var fat_reserve: float = 1.0

# ------------------------------------------------------------- movement ----
@export_group("Movement")
@export_range(20.0, 600.0, 5.0) var move_speed: float = 190.0
@export_range(50.0, 3000.0, 10.0) var acceleration: float = 800.0
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


## Drives the runtime tuning panel. Rows with "group" are section headers.
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
	{"prop": "chest_width", "label": "Chest", "min": 2.0, "max": 40.0, "step": 0.5},
	{"prop": "waist_width", "label": "Waist", "min": 1.0, "max": 40.0, "step": 0.5},
	{"prop": "hip_width", "label": "Hip", "min": 1.0, "max": 40.0, "step": 0.5},
	{"prop": "tail_tip_width", "label": "Tail tip", "min": 0.5, "max": 20.0, "step": 0.5},
	{"prop": "tail_enabled", "label": "Tail", "bool": true},
	{"prop": "front_limb_t", "label": "Shoulder pos", "min": 0.02, "max": 0.5, "step": 0.01},
	{"prop": "rear_limb_t", "label": "Hip pos", "min": 0.2, "max": 0.9, "step": 0.01},

	{"group": "Posture"},
	{"prop": "posture", "label": "Stance (0/1/2)", "min": 0.0, "max": 2.0, "step": 1.0},

	{"group": "Height"},
	{"prop": "neck_lift", "label": "Neck lift", "min": 0.0, "max": 0.6, "step": 0.01},
	{"prop": "leap_height", "label": "Leap height", "min": 0.0, "max": 4.0, "step": 0.05},
	{"prop": "wing_lift", "label": "Wing lift", "min": 0.0, "max": 2.0, "step": 0.05},

	{"group": "Limbs"},
	{"prop": "arm_length", "label": "Arm length", "min": 8.0, "max": 120.0, "step": 1.0},
	{"prop": "leg_length", "label": "Leg length", "min": 8.0, "max": 120.0, "step": 1.0},
	{"prop": "stance_reach", "label": "Stance reach", "min": 0.3, "max": 0.98, "step": 0.01},
	{"prop": "stance_width", "label": "Stance width", "min": 0.2, "max": 2.0, "step": 0.01},
	{"prop": "limb_max_reach", "label": "Max reach", "min": 0.5, "max": 1.0, "step": 0.01},
	{"prop": "limb_swing_deg", "label": "Swing fan (deg)", "min": 20.0, "max": 110.0, "step": 1.0},
	{"prop": "fabrik_iterations", "label": "FABRIK iters", "min": 1.0, "max": 12.0, "step": 1.0},

	{"group": "Gait"},
	{"prop": "stride_distance", "label": "Stride distance", "min": 4.0, "max": 90.0, "step": 0.5},
	{"prop": "step_height", "label": "Step height", "min": 0.0, "max": 40.0, "step": 0.5},
	{"prop": "step_duration", "label": "Step duration", "min": 0.05, "max": 1.2, "step": 0.01},
	{"prop": "foot_lead", "label": "Foot lead", "min": 0.0, "max": 1.5, "step": 0.01},
	{"prop": "diagonal_coupling", "label": "Diagonal coupling", "min": 0.0, "max": 1.0, "step": 0.01},
	{"prop": "front_foot_bias", "label": "Front foot bias", "min": -1.0, "max": 1.0, "step": 0.01},
	{"prop": "rear_foot_bias", "label": "Rear foot bias", "min": -1.0, "max": 1.0, "step": 0.01},

	{"group": "Physique"},
	{"prop": "density", "label": "Density", "min": 0.2, "max": 4.0, "step": 0.01},
	{"prop": "muscle_power", "label": "Muscle power", "min": 0.2, "max": 4.0, "step": 0.01},
	{"prop": "fat_reserve", "label": "Fat reserve", "min": 0.0, "max": 3.0, "step": 0.05},

	{"group": "Movement"},
	{"prop": "move_speed", "label": "Move speed", "min": 20.0, "max": 600.0, "step": 5.0},
	{"prop": "acceleration", "label": "Acceleration", "min": 50.0, "max": 3000.0, "step": 10.0},
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
		"head_width": 11.0, "chest_width": 15.0, "waist_width": 12.0,
		"hip_width": 14.0, "tail_tip_width": 1.2,
		"front_limb_t": 0.17, "rear_limb_t": 0.50,
		"arm_length": 40.0, "leg_length": 46.0, "stance_width": 0.85, "stance_reach": 0.80,
		"stride_distance": 30.0, "step_duration": 0.20, "step_height": 10.0,
		"move_speed": 260.0, "acceleration": 1300.0,
		"turn_speed_deg": 250.0, "turn_responsiveness": 14.0, "turn_pivot": 40.0,
		"sprint_multiplier": 1.80,
		"density": 1.0, "muscle_power": 1.6, "jaw_power": 1.1, "fat_reserve": 0.8,
		"bite_damage": 2.4, "bite_reach": 30.0, "bite_radius": 14.0,
		"bite_cooldown": 0.32, "chew_interval": 0.40,
		# Head carried clear of the shoulder, and legs that can throw the whole
		# animal several times its own standing height. The leap is the semi-
		# upright stance's signature and the reason it exists in the ecosystem:
		# it is the only terrestrial build that can get over a charge.
		"neck_lift": 0.10, "leap_height": 2.6,
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
	# twice the reference width. And it cannot leave the ground at all: nothing
	# forbids it, its `leap_height` is simply zero.
	"Elephant": {
		"posture": Posture.COLUMNAR,
		"segment_count": 16, "segment_length": 20.0, "max_bend_deg": 10.0,
		"spine_stiffness": 0.95, "spine_damping": 0.50, "body_wave": 3.0,
		"head_width": 26.0, "chest_width": 38.0, "waist_width": 34.0,
		"hip_width": 36.0, "tail_tip_width": 2.0,
		"front_limb_t": 0.20, "rear_limb_t": 0.52,
		# Legs longer than the animal is wide, and held nearly vertical: the
		# clearance is most of the leg and the plan-view reach is under a third of
		# it, which is what makes the feet land close underneath the body.
		"arm_length": 126.0, "leg_length": 132.0,
		"stance_width": 0.75, "stance_reach": 0.95,
		"stride_distance": 52.0, "step_duration": 0.55, "step_height": 10.0,
		"move_speed": 135.0, "acceleration": 300.0,
		"turn_speed_deg": 70.0, "turn_speed_falloff": 0.70,
		"turn_responsiveness": 5.0, "turn_pivot": 110.0,
		"sprint_multiplier": 1.30, "reverse_speed_factor": 0.40,
		"density": 1.9, "muscle_power": 1.3, "jaw_power": 5.0, "fat_reserve": 1.6,
		"bite_damage": 2.8, "bite_reach": 34.0, "bite_radius": 24.0,
		"bite_cooldown": 0.70, "chew_interval": 0.60,
		"neck_lift": 0.14, "leap_height": 0.0,
		# Broad flat molars. The bluntest mouth here: it spreads a very large bite
		# over a very large area, so it crushes and grinds where the Cat opens.
		"tooth_count": 6, "tooth_size": 0.16, "tooth_sharpness": 0.15,
		"jaw_gape_deg": 46.0, "tooth_variation": 0.14,
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
