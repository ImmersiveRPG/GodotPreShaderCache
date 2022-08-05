# Copyright (c) 2022 Matthew Brennan Jones <matthew.brennan.jones@gmail.com>
# This file is licensed under the MIT License
# https://github.com/ImmersiveRPG/GodotPreShaderCache

extends Node

signal on_each(file_name, geometry_instance, resource_type)
signal on_done()

const delay_time_on_each := 5
const delay_time_on_done := 5000

var _is_running := false
var _thread : Thread
var _is_logging := false
var _shader_cache := []
var _prev_shader_compilation_mode := 0

var _counter_mutex := Mutex.new()
var _counter := 1

func _exit_tree() -> void:
	if _is_running:
		_is_running = false

	if _thread:
		_thread.wait_to_finish()
		_thread = null

	_shader_cache.clear()

func send_next() -> void:
	_counter_mutex.lock()
	_counter += 1
	_counter_mutex.unlock()

func start(scene : Node, on_each : String, on_done : String) -> void:
	# Connect callbacks
	var err := OK
	err = self.connect("on_each", scene, on_each)
	assert(err == OK)
	err = self.connect("on_done", scene, on_done)
	assert(err == OK)

	# Temporarily change shader compilation mode to synchronous
	_prev_shader_compilation_mode = ProjectSettings.get_setting("rendering/gles3/shaders/shader_compilation_mode") as int
	ProjectSettings.set_setting("rendering/gles3/shaders/shader_compilation_mode", 0)

	# Start thread
	_thread = Thread.new()
	err = _thread.start(self, "_run_thread", 0, Thread.PRIORITY_LOW)
	assert(err == OK)

func stop(scene : Node, on_each : String, on_done : String) -> void:
	# Reset shader compilation mode to previous
	ProjectSettings.set_setting("rendering/gles3/shaders/shader_compilation_mode", _prev_shader_compilation_mode)

	# Disconnect callbacks
	self.disconnect("on_each", scene, on_each)
	self.disconnect("on_done", scene, on_done)

func _run_thread(_arg : int) -> void:
	_is_running = true
	var materials := []

	# Cache all the materials
	for file_name in self._get_resource_file_list():
		var resource_type = self._get_resource_type(file_name)
		match resource_type:
			ShaderMaterial, SpatialMaterial, ParticlesMaterial:
				var geometry_instance = self._cache_resource_material(file_name, resource_type)
				if geometry_instance:
					materials.append({ "file_name" : file_name, "geometry_instance" : geometry_instance, "resource_type" : resource_type })
			_:
				if _is_logging: print("##### Skipping caching: ", file_name)

	# Send all the cached materials to the scene
	while not materials.empty():
		_counter_mutex.lock()
		var is_empty := _counter < 1
		_counter_mutex.unlock()
		if is_empty:
			OS.delay_msec(delay_time_on_each)
			continue

		var entry = materials.pop_front()
		#print("Cached: %s" % entry.file_name.split('/')[-1])
		_counter_mutex.lock()
		_counter -= 1
		_counter_mutex.unlock()
		self.call_deferred("emit_signal", "on_each", entry.file_name, entry.geometry_instance, entry.resource_type)

	OS.delay_msec(delay_time_on_done)
	self.call_deferred("emit_signal", "on_done")
	_is_running = false

func _cache_resource_material(resource : String, resource_type : GDScriptNativeClass) -> GeometryInstance:
	var start_time := 0.0
	var size := 0.8

	# Load the material resource
	start_time = OS.get_ticks_msec()
	var mat := ResourceLoader.load(resource)
	var is_desired_format := mat is ShaderMaterial or mat is SpatialMaterial or mat is ParticlesMaterial
	if not is_desired_format:
		return null

	if _is_logging: print(resource)
	if _is_logging: print("    Loading resource: ", OS.get_ticks_msec() - start_time)
	start_time = OS.get_ticks_msec()

	#print(mat)
	match resource_type:
		# Create a cube mesh that is loaded with the material
		ShaderMaterial, SpatialMaterial:
			var mesh_instance := MeshInstance.new()
			var cube_mesh := CubeMesh.new()
			cube_mesh.size = Vector3.ONE * size
			if _is_logging: print("    Creating mesh: ", OS.get_ticks_msec() - start_time)
			start_time = OS.get_ticks_msec()

			cube_mesh.material = mat
			mesh_instance.mesh = cube_mesh
			if _is_logging: print("    Setting mesh material: ", OS.get_ticks_msec() - start_time)
			start_time = OS.get_ticks_msec()

			_shader_cache.append(mat)
			return mesh_instance
		ParticlesMaterial:
			var particles := Particles.new()
			var cube_mesh := CubeMesh.new()
			cube_mesh.size = Vector3.ONE * size
			if _is_logging: print("    Creating particles: ", OS.get_ticks_msec() - start_time)
			start_time = OS.get_ticks_msec()

			cube_mesh.material = mat
			particles.process_material = mat
			particles.draw_pass_1 = cube_mesh
			if _is_logging: print("    Setting particles material: ", OS.get_ticks_msec() - start_time)
			start_time = OS.get_ticks_msec()

			_shader_cache.append(mat)
			return particles
	return null

func _get_resource_type(file_name : String) -> GDScriptNativeClass:
	var f := File.new()
	f.open(file_name, File.READ)
	var text := f.get_as_text()
	f.close()

	#[gd_resource type="ParticlesMaterial" load_steps=3 format=2]
	for line in text.split("\n"):
		line = line.rstrip("\r")
		if line.find("[gd_resource") == 0 and line.find("]") == line.length()-1:
			line = line.substr("[gd_resource".length(), line.length()-2).lstrip(" ").rstrip(" ")
			#print("!!! line ", line)
			var entries = line.split(" ")
			for entry in entries:
				#print("    !!! entry ", entry)
				var pair = entry.split("=")
				#print(pair)
				if pair[0] == "type":
					var value = pair[1].lstrip("\"").rstrip("\"")
					match value:
						"Environment": return Environment
						"ButtonGroup": return ButtonGroup
						"CapsuleMesh": return CapsuleMesh
						"CubeMesh": return CubeMesh
						"Gradient": return Gradient
						"ParticlesMaterial": return ParticlesMaterial
						"PrismMesh": return PrismMesh
						"Shader": return Shader
						"ShaderMaterial": return ShaderMaterial
						"SpatialMaterial": return SpatialMaterial
						_:
							push_warning("Unexpected resource type: %s" % [value])
							return null

	return null

func _get_resource_file_list() -> Array:
	var resources := []

	# Get all the resource files in the project
	var to_search := ["res://"]
	while not to_search.empty():
		var path = to_search.pop_front()
		#print("while \"%s\"..." % [path])
		var dir := Directory.new()
		var result = dir.open(path)
		assert(result == OK)
		dir.list_dir_begin()

		var has_more_entries := true
		while has_more_entries:
			var entry = dir.get_next()
			var full_entry = dir.get_current_dir() + "/" + entry
			#print("    while \"%s\" \"%s\"" % [dir.get_current_dir(), entry])
			if dir.current_is_dir():
				if entry != "" and entry != ".." and entry != ".":
					#print("!!!!!! added full_entry \"%s\" \"%s\"..." % [entry, full_entry])
					to_search.append(full_entry)
			else:
				if entry != "":
					#print("    ", full_entry)
					if full_entry.get_extension() == "tres":
						resources.append(full_entry)

			if entry == "":
				has_more_entries = false

		dir.list_dir_end()

	return resources
