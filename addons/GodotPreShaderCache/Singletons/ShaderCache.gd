# Copyright (c) 2022 Matthew Brennan Jones <matthew.brennan.jones@gmail.com>
# This file is licensed under the MIT License
# https://github.com/ImmersiveRPG/GodotPreShaderCache

extends Node

signal on_each(percent, file_name, geometry_instance, resource_type)
signal on_done()

var _delay_msec_on_each := 5
var _delay_msec_on_done := 5000

var _is_running_mutex := Mutex.new()
var _is_running := false

var _is_logging := false
var _resource_files := []
var _shader_cache := []
var _prev_shader_compilation_mode := 0

var _materials_mutex := Mutex.new()
var _materials := []

var _ready_counter_mutex := Mutex.new()
var _ready_counter := 1

var _total_to_cache := 0
var _thread_cache_shaders : Thread
var _thread_fire_callbacks : Thread

func _exit_tree() -> void:
	_shader_cache.clear()

func _get_is_running() -> bool:
	_is_running_mutex.lock()
	var is_running := _is_running
	_is_running_mutex.unlock()
	return is_running

func _set_is_running(value : bool) -> void:
	_is_running_mutex.lock()
	_is_running = value
	_is_running_mutex.unlock()

func send_next() -> void:
	_ready_counter_mutex.lock()
	_ready_counter += 1
	_ready_counter_mutex.unlock()

func start(scene : Node, on_each : String, on_done : String, paths_to_ignore := [], delay_msec_on_each := 5, delay_msec_on_done := 5000) -> void:
	_delay_msec_on_each = delay_msec_on_each
	_delay_msec_on_done = delay_msec_on_done

	# Connect callbacks
	var err := OK
	err = self.connect("on_each", scene, on_each)
	assert(err == OK)
	err = self.connect("on_done", scene, on_done)
	assert(err == OK)

	# Temporarily change shader compilation mode to synchronous
	_prev_shader_compilation_mode = ProjectSettings.get_setting("rendering/gles3/shaders/shader_compilation_mode") as int
	ProjectSettings.set_setting("rendering/gles3/shaders/shader_compilation_mode", 0)

	_resource_files = self._get_res_file_list(["tscn", "tres"], paths_to_ignore)

	# Get total number of shaders we will cache
	var shader_types := [ShaderMaterial, SpatialMaterial, ParticlesMaterial]
	for file_name in _resource_files:
		if file_name.get_extension().to_lower() == "tres":
			var resource_type = self._get_resource_type(file_name)
			if shader_types.has(resource_type):
				_total_to_cache += 1

	# Start threads
	self._set_is_running(true)
	_thread_cache_shaders = Thread.new()
	err = _thread_cache_shaders.start(self, "_run_thread_cache_shaders", 0, Thread.PRIORITY_LOW)
	assert(err == OK)

	_thread_fire_callbacks = Thread.new()
	err = _thread_fire_callbacks.start(self, "_run_thread_fire_callbacks", 0, Thread.PRIORITY_LOW)
	assert(err == OK)

func stop(scene : Node, on_each : String, on_done : String) -> void:
	if self._get_is_running():
		self._set_is_running(false)

	if _thread_cache_shaders:
		_thread_cache_shaders.wait_to_finish()
		_thread_cache_shaders = null

	if _thread_fire_callbacks:
		_thread_fire_callbacks.wait_to_finish()
		_thread_fire_callbacks = null

	# Reset shader compilation mode to previous
	ProjectSettings.set_setting("rendering/gles3/shaders/shader_compilation_mode", _prev_shader_compilation_mode)

	# Disconnect callbacks
	self.disconnect("on_each", scene, on_each)
	self.disconnect("on_done", scene, on_done)

func _run_thread_cache_shaders(_arg : int) -> void:
	while self._get_is_running() and not _resource_files.empty():
		var file_name = _resource_files.pop_front()
		match file_name.get_extension().to_lower():
			# Warn of materials inside scenes that can't be cached
			"tscn":
				self._warn_un_cacheable_sub_resource_materials(file_name)
			# Cache all the materials
			"tres":
				var resource_type = self._get_resource_type(file_name)
				match resource_type:
					ShaderMaterial, SpatialMaterial, ParticlesMaterial:
						var geometry_instance = self._cache_resource_material(file_name, resource_type)
						if geometry_instance:
							_materials.append({ "file_name" : file_name, "geometry_instance" : geometry_instance, "resource_type" : resource_type })
					_:
						if _is_logging: print("##### Skipping caching: ", file_name)


func _run_thread_fire_callbacks(_arg : int) -> void:
	var i := 0
	while self._get_is_running():
		# Check if app is ready to fire next callback
		_ready_counter_mutex.lock()
		var is_ready := _ready_counter > 0
		_ready_counter_mutex.unlock()

		# Check if there are more materials to send to app
		_materials_mutex.lock()
		var is_empty := _materials.empty()
		_materials_mutex.unlock()

		# Just wait if app is not ready
		if not is_ready or is_empty:
			OS.delay_msec(10)
			continue

		if not is_empty:
			_materials_mutex.lock()
			var entry = _materials.pop_front()
			_materials_mutex.unlock()

			_ready_counter_mutex.lock()
			_ready_counter -= 1
			_ready_counter_mutex.unlock()

			i += 1
			var percent := i / float(_total_to_cache)
			OS.delay_msec(_delay_msec_on_each)
			self.call_deferred("emit_signal", "on_each", percent, entry.file_name, entry.geometry_instance, entry.resource_type)

			if i == _total_to_cache:
				self._set_is_running(false)
				OS.delay_msec(_delay_msec_on_done)
				self.call_deferred("emit_signal", "on_done")

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

func _warn_un_cacheable_sub_resource_materials(file_name : String) -> void:
	var headers = self._parse_resource_file_section_header(file_name, "sub_resource")
	for header in headers:
		for key in header:
			if key == "type":
				var value = header[key].lstrip("\"").rstrip("\"")
				match value:
					"ParticlesMaterial", "SpatialMaterial", "ShaderMaterial":
						push_warning("ShaderCache: scene '%s' sub resource %s can't be pre cached, unless saved in own *.tres file." % [file_name, value])

func _get_resource_type(file_name : String) -> GDScriptNativeClass:
	var headers = self._parse_resource_file_section_header(file_name, "gd_resource")
	for header in headers:
		for key in header:
			if key == "type":
				var type = header[key].lstrip("\"").rstrip("\"")
				match type:
					"ParticlesMaterial": return ParticlesMaterial
					"ShaderMaterial": return ShaderMaterial
					"SpatialMaterial": return SpatialMaterial
					_:
						return null

	return null


func _parse_resource_file_section_header(file_name : String, section_name : String) -> Array:
	var f := File.new()
	f.open(file_name, File.READ)
	var text := f.get_as_text()
	f.close()

	#print(file_name)
	var headers := []
	for line in text.split("\n"):
		line = line.rstrip("\r")
		var section_start := "[%s" % [section_name]
		if line.find(section_start) == 0 and line.find("]") == line.length()-1:
			line = line.substr(section_start.length(), line.length()-2).strip_edges()
			var entries = line.split(" ")
			var header := {}
			for entry in entries:
				var pair = entry.split("=")
				header[pair[0]] = pair[1]
				#print(pair)
			headers.append(header)
	#print("============================")
	return headers

func _get_res_file_list(extensions : Array, paths_to_ignore : Array) -> Array:
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
				var is_ignored := false
				for path_to_ignore in paths_to_ignore:
					if entry == "" or full_entry.begins_with(path_to_ignore):
						is_ignored = true

				if entry != "" and not is_ignored:
					#print("    ", full_entry)
					if extensions.has(full_entry.get_extension().to_lower()):
						resources.append(full_entry)

			if entry == "":
				has_more_entries = false

		dir.list_dir_end()

	return resources
