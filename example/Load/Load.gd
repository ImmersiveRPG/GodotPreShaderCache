# Copyright (c) 2022 Matthew Brennan Jones <matthew.brennan.jones@gmail.com>
# This file is licensed under the MIT License
# https://github.com/ImmersiveRPG/GodotPreShaderCache

extends Spatial


var _offset := Vector3.ZERO

func _ready() -> void:
	ShaderCache.start(self, "_on_each", "_on_done", 100, 3000)

func _process(delta : float) -> void:
	# Rotate each cube
	for child in self.get_children():
		if child is MeshInstance:
			child.rotation.x += delta * deg2rad(60.0)

func _on_each(percent : float, file_name : String, mesh : GeometryInstance, resource_type : GDScriptNativeClass) -> void:
	# Add the mesh to the scene
	self.add_child(mesh)
	mesh.transform.origin = _offset

	# Update the offset for the next mesh
	var size := 0.4
	_offset.x += size * 2.0
	if _offset.x >= 20.0:
		_offset.x = 0.0
		_offset.y -= size * 2.0

	match resource_type:
		ShaderMaterial:
			print("Cached shader material: %s" % [file_name])
		SpatialMaterial:
			print("Cached spatial material: %s" % [file_name])
		ParticlesMaterial:
			print("Cached particle material: %s" % [file_name])

	$LoadingProgressBar.value = percent * 100.0
	ShaderCache.send_next()

func _on_done() -> void:
	ShaderCache.stop(self, "_on_each", "_on_done")

	var err := self.get_tree().change_scene("res://example/Start/Start.tscn")
	assert(err == OK)
