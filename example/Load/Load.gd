# Copyright (c) 2022 Matthew Brennan Jones <matthew.brennan.jones@gmail.com>
# This file is licensed under the MIT License
# https://github.com/ImmersiveRPG/GodotPreShaderCache

extends Spatial


var _offset := Vector3.ZERO
var _prev_shader_compilation_mode := 0

func _enter_tree() -> void:
	var err := OK
	err = ShaderCache.connect("on_each", self, "_on_each")
	assert(err == OK)
	err = ShaderCache.connect("on_done", self, "_on_done")
	assert(err == OK)

func _exit_tree() -> void:
	ShaderCache.disconnect("on_each", self, "_on_each")
	ShaderCache.disconnect("on_done", self, "_on_done")

func _ready() -> void:
	# Temporarily change shader compilation mode to synchronous
	_prev_shader_compilation_mode = ProjectSettings.get_setting("rendering/gles3/shaders/shader_compilation_mode") as int
	ProjectSettings.set_setting("rendering/gles3/shaders/shader_compilation_mode", 0)

	ShaderCache.start()

func _process(delta : float) -> void:
	# Rotate each cube
	for child in self.get_children():
		if child is MeshInstance:
			child.rotation.x += delta * deg2rad(60.0)

func update_offset() -> void:
	var size := 0.4
	_offset.x += size * 2.0
	if _offset.x >= 20.0:
		_offset.x = 0.0
		_offset.y -= size * 2.0

func _on_each(file_name : String, geometry_instance : GeometryInstance, resource_type : GDScriptNativeClass) -> void:
	var start_time := OS.get_ticks_msec()
	self.add_child(geometry_instance)
	geometry_instance.transform.origin = _offset
	self.update_offset()

	match resource_type:
		ShaderMaterial:
			print("Cached shader material: %s" % [file_name])
		SpatialMaterial:
			print("Cached spatial material: %s" % [file_name])
		ParticlesMaterial:
			print("Cached particle material: %s" % [file_name])

	#print(resource)
	ShaderCache.send_next()

func _on_done() -> void:
	# Change shader compilation mode from synchronous back to original
	ProjectSettings.set_setting("rendering/gles3/shaders/shader_compilation_mode", _prev_shader_compilation_mode)

	var err := self.get_tree().change_scene("res://example/Start/Start.tscn")
	assert(err == OK)
