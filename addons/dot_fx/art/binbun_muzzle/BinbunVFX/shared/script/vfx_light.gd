@tool
extends OmniLight3D
class_name DotMuzzleVfxLight

@export var base_energy : float = 2.0:
	set(value):
		base_energy = value
		light_energy = base_energy * light_multiplier
@export_range(0.0,1.0,0.01) var light_multiplier : float = 1.0:
	set(value):
		light_multiplier = value
		light_energy = base_energy * light_multiplier
