## Species-tunable parameters for one creature's sight.
##
## The distances describe the perceptual field in world pixels. Rendering values
## only describe how unresolved space is presented; keeping both on a Resource
## lets a future species preset swap the complete sight character without
## teaching the creature or the world renderer about species names.
class_name SightProfile
extends Resource

@export_category("Perception")
@export_range(40.0, 1000.0, 1.0) var clear_reach: float = 300.0
@export_range(20.0, 500.0, 1.0) var clear_width: float = 130.0
@export_range(10.0, 300.0, 1.0) var clear_near_radius: float = 52.0
@export_range(80.0, 1800.0, 1.0) var peripheral_reach: float = 560.0
@export_range(40.0, 900.0, 1.0) var peripheral_width: float = 260.0
@export_range(20.0, 500.0, 1.0) var peripheral_near_radius: float = 130.0
@export_range(0.0, 0.75, 0.01) var motion_reach_gain: float = 0.32

@export_category("Rendering")
@export_range(0.0, 6.0, 0.05) var unseen_blur_lod: float = 3.15
@export_range(0.0, 5.0, 0.05) var peripheral_blur_lod: float = 1.55
@export_range(0.0, 1.0, 0.01) var unseen_desaturation: float = 0.92
@export_range(0.0, 1.0, 0.01) var unseen_contrast: float = 0.58
@export_range(0.0, 1.0, 0.01) var peripheral_desaturation: float = 0.55
@export_range(0.0, 1.0, 0.01) var peripheral_contrast: float = 0.88
@export_range(0.0, 1.0, 0.01) var paper_wash: float = 0.18
@export_range(0.0, 1.0, 0.01) var peripheral_opacity: float = 0.82
@export var unresolved_paper: Color = Color("eef0f2")

