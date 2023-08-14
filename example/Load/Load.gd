# Copyright (c) 2022 Matthew Brennan Jones <matthew.brennan.jones@gmail.com>
# This file is licensed under the MIT License
# https://github.com/ImmersiveRPG/GodotPreShaderCache

extends Spatial


var _offset := Vector3.ZERO
onready var _progress_bar = $CenterContainer/VBoxContainer/MarginContainer/LoadingProgressBar

func _ready() -> void:
	yield(self.get_tree().create_timer(2), "timeout")

	# Setup CallThrottled frame budget and threshold
	var frame_budget_usec : int = floor(1000000 / float(Engine.get_frames_per_second()))
	var frame_budget_threshold_usec := 5000
	CallThrottled.start(frame_budget_usec, frame_budget_threshold_usec)

	# Setup ShaderCache
	var paths_to_ignore := [
		"res:///addons/"
	]
	ShaderCache.start(self, "_on_each", "_on_done", paths_to_ignore)

func _process(delta : float) -> void:
	# Rotate each cube
	for child in self.get_children():
		if child is MeshInstance:
			child.rotation.x += delta * deg2rad(60.0)

func _on_each(percent : float, file_name : String, mesh : Node, resource_type : GDScriptNativeClass) -> void:
	# Add the mesh to the scene
	self.add_child(mesh)
	if "position" in mesh:
		var pos = $Camera.unproject_position(_offset)
		mesh.position = Vector2(pos.x, pos.y)
	else:
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
		CanvasItemMaterial:
			print("Cached canvas item material: %s" % [file_name])
	#print("Cached: %s" % [file_name])

	_progress_bar.value = percent * 100.0

func _on_done() -> void:
	yield(self.get_tree().create_timer(4), "timeout")
	ShaderCache.stop(self, "_on_each", "_on_done")

	var err := self.get_tree().change_scene("res://example/Start/Start.tscn")
	assert(err == OK)
