@tool
extends Node3D

@export_tool_button("Test muzzle flash", "Callable")
var test_flash = play_muzzle_flash

# play all particles once, which should make the whole muzzle flash.
func play_muzzle_flash() -> void:
	for particle in get_children():
		if particle is GPUParticles3D:
			particle.restart()
			particle.emitting = true
