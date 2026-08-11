## Where a HUD drawer stands, stated once for all of them.
##
## One rule rather than one per drawer, because a drawer's rect is not a taste:
## the view buttons sit in the top right corner, so a drawer opens under them, on
## the same edge, and takes the paper between them and the foot of the window. A
## drawer that says how wide it is gets placed, sized and paid for by these three
## numbers and nothing else — and the field pays for it in one place too, because
## `reserved` is also what the world subtracts from the window before deciding
## where the middle of what is left is. Anything opened beside the two F3 stops
## behaves the way they do by using this, and there is no second opinion about
## where the right-hand column begins.
class_name HudDock
extends RefCounted

## The standoff from the window's right edge. The identity block's own margin, so
## a drawer's outer edge lines up with the view buttons above it.
const INSET: float = 32.0
## The top of a drawer: under the buttons it was opened from, with the same air
## between them as they have over them.
const TOP: float = 78.0
## ...and the paper left under it.
const BOTTOM: float = 30.0


## Stands `panel` in the dock at its own width. Anchored to the right edge and to
## both the top and the bottom, so a drawer is as tall as the window allows and
## its contents have the whole height to divide up rather than a fixed rect to be
## squeezed into.
static func place(panel: Control, wide: float) -> void:
	panel.anchor_left = 1.0
	panel.anchor_right = 1.0
	panel.anchor_top = 0.0
	panel.anchor_bottom = 1.0
	panel.offset_left = -(wide + INSET)
	panel.offset_right = -INSET
	panel.offset_top = TOP
	panel.offset_bottom = -BOTTOM
	panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	# A drawer whose contents will not fit a short window grows down past its own
	# foot rather than up over the buttons it was opened from.
	panel.grow_vertical = Control.GROW_DIRECTION_END


## How tall a drawer comes out in a window this tall.
static func height(window_height: float) -> float:
	return maxf(window_height - TOP - BOTTOM, 0.0)


## The column of the window a drawer of this width takes for itself: what the
## field gives up while it is open. Half of it is how far the picture moves over,
## because the animal belongs in the middle of the paper that is left rather than
## in the middle of the window — see Main._camera_focus.
static func reserved(wide: float) -> float:
	return wide + INSET
