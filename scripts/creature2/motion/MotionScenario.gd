## The nine scenarios — a hand on the controls, so the loop can be watched doing
## the things it is hard to catch it doing.
##
## Every one of them is a *command*, and that is the whole design of this file.
## The bench does not animate an accelerating cat: it asks for full speed from a
## standstill and lets `Travel` deliver what the feet can press, exactly as the W
## key does. A brink is not a scripted balk, it is sixty pixels of ground that
## stops being there. A shove is `Creature2.shove` — the same seam a charge and a
## collision push through — and the collapse is the same collapse a death is.
## Nothing here reaches inside the mover, nothing here is a special case in it,
## and if a scenario looks wrong the finding belongs to the loop rather than to
## the script that asked for it.
##
## Two of them build ground (`Terrain.add`, the field the game already had) and
## the rest run on the bare floor. Where the handoff quotes a number in its own
## world's units — a 300 px/s shove against a 163 px/s sprint — the *share* is
## what carries over and the number is taken from this animal, because a blow
## that is three times a cat's flat-out is not the blow the design drew.
class_name MotionScenario
extends RefCounted

## The ask a scenario cruises at, as a share of flat out — the handoff's warm
## start, and the throttle the drive slider opens on. Flat out stopped being
## an authored 100 px/s the day the legs started quoting their own ceiling
## (`Footwork.deliverable`, ~157 px/s on the reference cat), so the share is
## re-pinned to keep the scenarios' working pace where it was tuned: a fast
## walk of ~60 px/s, quick enough to be worth watching and slow enough that
## the ledge run is still on its pad when the probe looks.
const CRUISE: float = 0.38

## The shove, as a multiple of this animal's own flat out, and when it lands.
##
## The handoff quotes 300 px/s against a body that sprints at 163 — 1.84× flat
## out — and this cat cannot keep its feet under that: measured, anything past
## about 1.4× rolls it straight over, which would make S8 a second collapse
## scenario and S9 redundant. What S8 is *for* is the recovery — the heel, the
## rescue steps, the weight coming back over the feet — so the blow is the
## biggest one that leaves the animal standing, with room under the threshold.
## At 1.15 it staggers ~12 px across its own line, heels ~13° and steps to catch
## itself (`tests/PhysicsHudProbe.gd` pins exactly that).
## Re-pinned with `CRUISE` when flat out became the legs' derived ceiling:
## the scenario's calibrated stimulus is ~115 px/s on the reference cat —
## hard enough to demand rescue steps, short of the topple the collapse
## scenario owns — and the share moves so the stimulus does not.
const SHOVE_SHARE: float = 0.73
const SHOVE_AT: float = 1.6
const COLLAPSE_AT: float = 1.6

## The ground the two terrain scenarios build: how far ahead of the spawn the
## edge stands, how much it rises or drops, and how much floor there is either
## side of it. The rise is inside what a fore leg climbs in stride and the drop
## is past what a hind leg can reach down (see `Outlook.CLIMB_SHARE` and
## `DESCEND_SHARE`) — which is the whole difference between a step and a brink,
## and neither is stated here.
const LEDGE_AT: float = 210.0
const LEDGE_RISE: float = 10.0
const LEDGE_SPAN: float = 130.0
const BRINK_AT: float = 300.0
const BRINK_DROP: float = 60.0
const BRINK_SPAN: float = 340.0

## How long a body is left to arrive at its own start before the recording opens:
## a creature laid out on a plateau begins the tick with its feet at the floor's
## height, and the first stride of that is the body finding the ground rather
## than walking on it.
const SETTLE: float = 0.5

## The scenarios, in the order the handoff lists them — the number keys pick them
## 1–9. `warm` is the speed the body starts carrying, `loop` is how long the run
## lasts before it starts over (0 runs until something else is picked).
const CASES: Array[Dictionary] = [
	{"tag": "S1", "name": "CRUISE", "ground": &"flat", "warm": CRUISE, "loop": 0.0},
	{"tag": "S2", "name": "ACCELERATE", "ground": &"flat", "warm": 0.0, "loop": 0.0},
	{"tag": "S3", "name": "BRAKE", "ground": &"flat", "warm": 1.0, "loop": 0.0},
	{"tag": "S4", "name": "TURN ON SPOT", "ground": &"flat", "warm": 0.0, "loop": 0.0},
	{"tag": "S5", "name": "TURN AT CRUISE", "ground": &"flat", "warm": CRUISE, "loop": 0.0},
	{"tag": "S6", "name": "LEDGE", "ground": &"ledge", "warm": CRUISE, "loop": 7.5},
	{"tag": "S7", "name": "BRINK", "ground": &"brink", "warm": CRUISE, "loop": 8.5},
	{"tag": "S8", "name": "SHOVE", "ground": &"flat", "warm": CRUISE, "loop": 7.0},
	{"tag": "S9", "name": "COLLAPSE", "ground": &"flat", "warm": CRUISE, "loop": 7.0},
]


var creature: Creature2
var terrain: Terrain

## Which scenario is running, how long it has been running, and what it is asking
## for — a share of flat out, which is what the drive slider reads and writes.
var index: int = 0
var elapsed: float = 0.0
var drive: float = 0.0

## Whether the hand has taken over. Touching the drive slider or the turn keys
## stops the script asking for anything: from then on the scenario is only the
## ground it built, and the animal is being driven.
var manual: bool = false

var _turn_hold: float = 0.0
var _shoved: bool = false
var _dropped: bool = false


func attach(p_creature: Creature2, p_terrain: Terrain) -> void:
	creature = p_creature
	terrain = p_terrain


## What this scenario is called, with the numbers this animal actually gets: the
## ledge and the brink are heights in px and carry over as they are, and the
## shove is quoted in the px/s it will genuinely arrive as.
func label(i: int) -> String:
	var case: Dictionary = CASES[wrapi(i, 0, CASES.size())]
	match str(case["name"]):
		"LEDGE":
			return "LEDGE +%d" % int(LEDGE_RISE)
		"BRINK":
			return "BRINK −%d" % int(BRINK_DROP)
		"SHOVE":
			return "SHOVE %d" % int(round(shove_speed()))
		_:
			return str(case["name"])


func tag(i: int) -> String:
	return str(CASES[wrapi(i, 0, CASES.size())]["tag"])


## The blow S8 lands, px/s — this animal's own flat out at the handoff's share.
func shove_speed() -> float:
	return (creature.flat_out() if creature != null else 100.0) * SHOVE_SHARE


## What the loop is being asked for, px/s — the drive readout.
func ask_speed() -> float:
	return drive * (creature.flat_out() if creature != null else 0.0)


## Picks a scenario and starts it from the top.
func pick(i: int) -> void:
	index = clampi(i, 0, CASES.size() - 1)
	restart()


## Back to the beginning of this scenario: the ground rebuilt, the body put back
## where it spawned with whatever speed the scenario starts at, and the loop's
## record cleared — a timeline that ran across the join would be drawing a stride
## that never happened.
func restart() -> void:
	if creature == null:
		return
	var case: Dictionary = CASES[index]
	_build_ground(StringName(case["ground"]))
	elapsed = 0.0
	manual = false
	_turn_hold = 0.0
	_shoved = false
	_dropped = false
	drive = float(case["warm"])
	creature.reset()
	_ask(drive, 0.0)
	if drive > 0.0:
		# A warm start is a velocity, not a pose: the body is given the motion the
		# scenario opens at and the loop carries on from there.
		creature.shove(Vector2.RIGHT.rotated(creature.heading) * ask_speed())
	# Let the body arrive before anything is recorded of it — and re-arm the ring
	# afterwards, which is what clears it (MotionReadout.watch).
	var readout: MotionReadout = creature.motion_readout()
	var watching: bool = readout.watching
	readout.watch(false)
	creature.simulate(SETTLE)
	readout.watch(watching)


## One tick of being driven. Runs before the creature's own tick, because what it
## writes is the command that tick reads.
func tick(delta: float) -> void:
	if creature == null:
		return
	elapsed += delta
	var case: Dictionary = CASES[index]
	var loop: float = float(case["loop"])
	if loop > 0.0 and elapsed > loop:
		restart()
		return
	if manual:
		_ask(drive, _turn_hold)
		return
	var t: float = elapsed
	match str(case["tag"]):
		"S1":
			_ask(CRUISE, 0.0)
		"S2":
			# From a standstill to everything, so the delivery clamps and the body
			# is visibly feeling its own mass on the ACCEL track.
			_ask(0.0 if t < 0.4 else 1.0, 0.0)
		"S3":
			_ask(1.0 if t < 0.6 else 0.0, 0.0)
		"S4":
			_ask(0.0, 1.0 if t > 0.5 else 0.0)
		"S5":
			_ask(CRUISE, 0.85 if t > 1.1 else 0.0)
		"S6", "S7":
			_ask(CRUISE, 0.0)
		"S8":
			_ask(CRUISE, 0.0)
			if not _shoved and t > SHOVE_AT:
				_shoved = true
				_shove()
		"S9":
			_ask(CRUISE, 0.0)
			if not _dropped and t > COLLAPSE_AT:
				_dropped = true
				creature.toggle_collapsed()


# ------------------------------------------------------------------ the hand ----

## The drive slider, and the arrow keys under it. Taking hold of it is what puts
## the scenario into the hand: the ground it built stays, and nothing asks for
## anything on the animal's behalf again until another scenario is picked.
func hand_drive(share: float) -> void:
	manual = true
	drive = clampf(share, 0.0, 1.0)


func nudge(by: float) -> void:
	hand_drive(drive + by)


## A and D, held. Zero is the key coming up rather than the hand letting go — the
## scenario stays manual, exactly as the drive does.
func hand_turn(dir: float) -> void:
	if absf(dir) > 0.001:
		manual = true
	_turn_hold = clampf(dir, -1.0, 1.0)


# ---------------------------------------------------------------- the pieces ----

## The command, from a share of flat out: under the walk it is a throttle, over it
## the animal is sprinting. One place, so what the scenarios ask for and what the
## slider asks for are the same ask.
func _ask(share: float, turn: float) -> void:
	drive = clampf(share, 0.0, 1.0)
	var cmd: Creature2.Command = creature.command
	var walk: float = maxf(creature.body.move_speed, 1.0)
	var flat: float = maxf(creature.flat_out(), 1.0)
	var want: float = drive * flat
	cmd.sprint = want > walk
	cmd.throttle = clampf(want / (flat if cmd.sprint else walk), 0.0, 1.0)
	cmd.turn = clampf(turn, -1.0, 1.0)
	cmd.jump = false
	# The bench has no cursor on the world: nothing is being aimed at, so the head
	# rides where the body points it.
	cmd.aim_active = false


## The blow, through the seam every other push in the game uses — at the height of
## the animal's own weight, which is the term that decides whether it is shoved
## along or rolled over (see `Travel.twist`).
func _shove() -> void:
	var facing: Vector2 = Vector2.RIGHT.rotated(creature.heading)
	var across := Vector2(-facing.y, facing.x)
	var at: Vector2 = creature.centre()
	creature.shove(across * shove_speed(),
		Vector3(at.x, at.y, creature.poise.height))


func _build_ground(kind: StringName) -> void:
	if terrain == null:
		return
	terrain.clear()
	if creature == null:
		return
	var from: Vector2 = creature.armature.spawn_at
	var facing: Vector2 = Vector2.RIGHT.rotated(creature.armature.spawn_heading)
	match kind:
		&"ledge":
			# A broad pad whose near rim stands where the edge is asked for, so the
			# animal walks up onto it in stride and the carries anticipate the rise.
			terrain.add(from + facing * (LEDGE_AT + LEDGE_SPAN), LEDGE_SPAN,
				LEDGE_RISE, 0.0, "ledge")
		&"brink":
			# ...and the drop is the same thing seen from on top of it: the body
			# spawns on the plateau, and the ground stops at its far rim.
			terrain.add(from + facing * (BRINK_AT - BRINK_SPAN), BRINK_SPAN,
				BRINK_DROP, 0.0, "brink")
