## Saves a strip of the v2 creature galloping, falling and standing back up —
## the visual gate on the 2026-08-15 locomotion work. Must run windowed —
## headless renders nothing.
##
##   /Applications/Godot.app/Contents/MacOS/Godot --path . \
##       --resolution 1600x1000 --script tests/GallopShot.gd
##
## Throwaway diagnostic scaffolding.
extends SceneTree

const OUT: String = "user://gallop"
const TICK: float = 1.0 / 60.0

var main: Node
var frames: int = 0
var saved: Array = []
## Gallop strip frames, taken every few ticks through two strides.
var _strip: int = 0
var _phase: String = "warm"
var _shoved: bool = false
var _down_seen: bool = false
var _up_seen: bool = false


func _initialize() -> void:
	main = load("res://scenes/V2Lab.tscn").instantiate()
	root.add_child(main)


func _process(_delta: float) -> bool:
	frames += 1
	var c: Creature2 = main.creature
	if c == null:
		return false
	if frames == 2:
		main.terrain.clear()
		main.set_physics_process(false)
		main.set_process(false)
	if frames < 3:
		return false
	# The lab's process is off (its input pump would blank the command), so the
	# camera follows from here.
	main.camera.position = c.centre()
	main.camera.zoom = Vector2(3.2, 3.2)

	match _phase:
		"warm":
			c.command.throttle = 1.0
			c.command.sprint = true
			if frames > 200:
				_phase = "strip"
		"strip":
			c.command.throttle = 1.0
			c.command.sprint = true
			if frames % 6 == 0 and _strip < 8:
				_strip += 1
				_shoot("gallop-%d" % _strip, c)
			if _strip >= 8:
				_phase = "fall"
		"fall":
			c.command.throttle = 0.0
			c.command.sprint = false
			if not _shoved and c.speed < 20.0:
				# The knock: sideways, high on the flank, past what the legs hold.
				var side: Vector2 = Vector2(-c.move_dir.y, c.move_dir.x)
				c.shove(side * 170.0, Vector3(c.centre().x, c.centre().y, 42.0))
				_shoved = true
			if _shoved and c.armature.collapsed and not _down_seen:
				_down_seen = true
				_shoot("downed", c)
			if _down_seen and c.travel._down == Travel.Down.RISING and not _up_seen:
				_up_seen = true
				_shoot("rising", c)
			if _up_seen and c.travel._down == Travel.Down.UP:
				_shoot("recovered", c)
				_finish()
			if frames > 1400:
				_shoot("timeout", c)
				_finish()
	return false


func _shoot(word: String, c: Creature2) -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	var path: String = "%s/gallop-%02d-%s.png" % [OUT, saved.size() + 1, word]
	root.get_viewport().get_texture().get_image().save_png(path)
	saved.append(ProjectSettings.globalize_path(path))
	print("%s: state=%s speed=%.0f feet=%d roll=%.2f arch=%.2f bunch=%.2f bound=%.2f" % [
		word, c.travel._state_word(), c.speed, c.poise.feet,
		c.travel.keel.roll, c.armature.arch, c.armature.bunched,
		c.travel.rhythm.bound])


func _finish() -> void:
	for p in saved:
		print("saved ", p)
	quit()
