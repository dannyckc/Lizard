## What keeps the animal running, and what a wound does to it — BodyState's
## successor, reading the §6 feature table's consequences.
##
## The census owns the flesh; this file owns what the flesh was *for*. Blood is
## one pool, drained by whatever vessels stand breached; the heart is one organ,
## and **death is a stopped heart** — the v1 law carried over verbatim: nothing
## anywhere asks "is it dead", everything asks whether the heart is beating,
## and `arrested` is the one answer. A creature is not killed by a number
## reaching zero somewhere else; it is killed by a wound reaching the heart, or
## by the blood that would have reached it running out on the ground.
##
## Everything here is a consequence, never a decision: `absorb` is handed the
## wound reports Corpus.wound resolves (which organs the front reached, which
## vessels it breached, which nerves it cut) and keeps their state; `tick`
## integrates the bleeding and nothing else. The effects are the feature
## table's own words — "arrest" stops the heart where it stands, "collapse"
## (the brain) stops everything including the heart that serves it, "aerobic"
## (the lungs) shrinks the wind the stamina model will draw on, a cut nerve
## takes its region's function — and none of them is a special case about a
## body part: the throat kills because the carotid is shallow *geometry*, and
## this file never hears the word "throat".
class_name Vitals
extends RefCounted

## Blood drained per second per unit of a breached vessel's flow, as a share
## of the whole pool. Sized with CLOT_RATE below so the untreated totals come
## out as anatomy says they should: a torn carotid (flow 2.5) costs ~0.83 of
## the pool before it seals — past DRAINED, so a throat bite kills in under
## half a minute; a nicked femoral (1.8) costs ~0.6 and is survivable, barely.
const BLEED_RATE: float = 0.02

## How quickly an open vessel closes itself, per second — the flow decays
## exponentially, so a small breach seals in seconds and a torn artery has
## emptied the animal before it matters.
const CLOT_RATE: float = 0.06

## Below this flow a breach has sealed and stops being carried.
const SEALED: float = 0.05

## Blood share below which the heart has nothing left to move. The arrest this
## causes is the same arrest a heart wound causes, because it is: the pump
## stopping is the death, whatever stopped it.
const DRAINED: float = 0.35


## Whether the heart has stopped. THE death readout — everything else is a
## way of getting here.
var arrested: bool = false

## What is left in the pool, 0..1 of the intact animal's.
var blood: float = 1.0

## How much wind the lungs still supply, 0..1 — the aerobic ceiling's input.
## The product of the two lungs' hp, so losing one is survivable and losing
## both is a slower arrest than the heart's but the same end.
var wind: float = 1.0

## Vessels currently open: the feature dictionaries themselves, with a live
## `flow` decaying toward sealed. The same dictionary re-breached is re-opened,
## not duplicated.
var bleeds: Array[Dictionary] = []

## Chains whose nerve supply has been cut — function loss, read by the feet.
var numb: Dictionary = {}


## Takes one wound's consequences from the census's resolution. The report is
## Corpus.wound's return; nothing in it is re-derived here.
func absorb(report: Dictionary) -> void:
	for organ: Dictionary in report.get("organs", []):
		match String(organ.get("effect", "")):
			"arrest":
				if float(organ.get("hp", 1.0)) <= 0.0:
					arrested = true
			"collapse":
				if float(organ.get("hp", 1.0)) <= 0.0:
					arrested = true
			"aerobic":
				_measure_wind(organ)
			_:
				pass
	for vessel: Dictionary in report.get("breached", []):
		# Re-opened at its authored flow however far it had clotted. Carried
		# once per vessel, by name — the census hands back the same per-body
		# dictionary every time this vessel is reached.
		vessel["open_flow"] = float(vessel.get("flow", 1.0))
		var carried: bool = false
		for open: Dictionary in bleeds:
			if open.get("name", "") == vessel.get("name", ""):
				carried = true
				break
		if not carried:
			bleeds.append(vessel)
	for nerve: Dictionary in report.get("severed", []):
		numb[nerve.get("serves", "")] = true


## One tick of consequence: the open vessels drain the pool and clot toward
## sealed, and a pool below what the heart can work with stops it. Returns
## whether the heart stopped *this tick*, so the owner collapses the body once
## rather than asking every frame.
func tick(delta: float) -> bool:
	var was: bool = arrested
	var k: int = bleeds.size() - 1
	while k >= 0:
		var vessel: Dictionary = bleeds[k]
		var flow: float = float(vessel.get("open_flow", 0.0))
		blood = maxf(blood - flow * BLEED_RATE * delta, 0.0)
		flow *= exp(-CLOT_RATE * delta)
		vessel["open_flow"] = flow
		if flow < SEALED:
			bleeds.remove_at(k)
		k -= 1
	if blood <= DRAINED:
		arrested = true
	return arrested and not was


## Function left in a chain's nerve supply: nothing or everything. Read by the
## support (a numb leg has no press), and deliberately not blended — a cut
## nerve is cut.
func numbness(chain: StringName) -> float:
	return 0.0 if numb.get(String(chain), false) else 1.0


## The lab's revival: a heart restarted, the pool refilled, the vessels
## sealed. A tool, not a mechanic — the game has no resurrection, the lab has
## a K key.
func revive() -> void:
	arrested = false
	blood = 1.0
	bleeds.clear()
	numb.clear()


## The wind is the product of the lungs that are left. Asked when a lung is
## hit rather than kept live, because lungs only change when wounded.
func _measure_wind(hit: Dictionary) -> void:
	# hit is one lung; wind is both. The caller's corpus owns the pair, but
	# the report hands organs one at a time — so wind is folded in
	# multiplicatively from each lung's standing hp as it is hit.
	wind = clampf(wind * (0.5 + 0.5 * float(hit.get("hp", 1.0))), 0.05, 1.0)
