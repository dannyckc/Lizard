## The v2 body schema, stated once — see docs/V2_DESIGN.md §5.
##
## Everything in the v2 creature is either a process that updates the census or
## a view that reads it, and this file is the census's *resolution*: how finely
## body addresses `(chain, t, θ, d)` quantize into polar cells, what the radial
## layers are, and what each tissue weighs. It is deliberately nothing but
## constants. The moment a number in here depends on a particular animal it has
## stopped being schema and become authoring, and it belongs in a BodySpec.
##
## One owner per quantity, so to be explicit about what is *not* here:
## the pull of the world is `Gravity.PULL` (scripts/world/Gravity.gd) and the
## only integrator is `Gravity.Fall` — v2 adds no second copy of either.
class_name BodySchema
extends RefCounted

## The radial order of tissue around a bone core, per the cat: muscle is bound
## to the skeleton and drives it; fat wraps muscle; skin wraps fat. Depth
## resolution walks these outside-in (skin first) when a wound resolves.
enum Layer { BONE, MUSCLE, FAT, SKIN }

## Relative tissue densities, indexed by Layer. What turns a cell's wedge-shell
## volume into mass in `Corpus.mass()` — nothing else may quote its own.
const DENSITY: Array[float] = [1.9, 1.06, 0.92, 1.1]

## Chain kinds. A creature's four limbs are four chains of the same *kind*: the
## census resolution is a property of being a limb, not of being the front-left
## one. Instance names (FL/FR/HL/HR) belong to the armature.
const TRUNK := &"trunk"
const NECK := &"neck"
const TAIL := &"tail"
const LIMB := &"limb"

## Fixed subdivisions along each chain — the `station` axis of the census.
## Census stations, not physics nodes: the armature's chain graph is a
## controller with far fewer stations (§4.3), and render rings are interpolated
## between them. These are the rows damage and mass are bookkept in.
const STATIONS := {
	TRUNK: 16,
	NECK: 6,
	TAIL: 8,
	LIMB: 6,
}

## Fixed angular wedges around each chain's axis — the `sector` axis.
const SECTORS := {
	TRUNK: 10,
	NECK: 10,
	TAIL: 6,
	LIMB: 6,
}

## How many render rings the mesh interpolates per armature stick. Visual
## smoothness only — physics cost is fixed by the node graph, so this is a free
## dial and nothing below the mesh may read it.
const RINGS_PER_STICK := 3


## Total census columns for a body with `limbs` limbs — the size every cell
## array is allocated to. Stated here so the allocation and the schema cannot
## drift apart. For the reference cat (4 limbs): 16·10 + 6·10 + 8·6 + 4·6·6
## = 412 columns, ~1 650 cells across the four layers.
static func column_count(limbs: int = 4) -> int:
	return STATIONS[TRUNK] * SECTORS[TRUNK] \
		+ STATIONS[NECK] * SECTORS[NECK] \
		+ STATIONS[TAIL] * SECTORS[TAIL] \
		+ limbs * STATIONS[LIMB] * SECTORS[LIMB]
