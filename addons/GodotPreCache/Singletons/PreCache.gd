# Copyright (c) 2022-2023 Matthew Brennan Jones <matthew.brennan.jones@gmail.com>
# This file is licensed under the MIT License
# https://github.com/ImmersiveRPG/GodotPreCache

extends Node

# TODO:
# . Add an enum so we can control what to cache: enum ToCache {All, TextScenes, Images, Textures, Shaders, Materials, }
# . Make it load images as resources before import
# . load image files too resources, because image.load will fail on exported games
# . Remove need to call PreCache.stop
# . Change to use viewport
# . Replace mutexes with synchronized?
# . Large particles sometimes cover other blocks

signal on_each(percent, file_name, thing, resource_type)
signal on_done()

var _is_running_mutex := Mutex.new()
var _is_running := false

var _is_logging := false
var _paths_to_ignore := []
var _cache := {}
var _prev_shader_compilation_mode := 0

var _thread : Thread

func _exit_tree() -> void:
	_cache.clear()

func _get_is_running() -> bool:
	_is_running_mutex.lock()
	var is_running := _is_running
	_is_running_mutex.unlock()
	return is_running

func _set_is_running(value : bool) -> void:
	_is_running_mutex.lock()
	_is_running = value
	_is_running_mutex.unlock()

func has_cached(file_name : String) -> bool:
	return file_name in _cache

func start(scene : Node, on_each : String, on_done : String, paths_to_ignore := []) -> void:
	# Connect callbacks
	var err := OK
	err = self.connect("on_each", scene, on_each)
	assert(err == OK)
	err = self.connect("on_done", scene, on_done)
	assert(err == OK)

	# Temporarily change shader compilation mode to synchronous
	_prev_shader_compilation_mode = ProjectSettings.get_setting("rendering/gles3/shaders/shader_compilation_mode") as int
	ProjectSettings.set_setting("rendering/gles3/shaders/shader_compilation_mode", 0)

	_paths_to_ignore = paths_to_ignore

	# Start thread
	self._set_is_running(true)
	_thread = Thread.new()
	err = _thread.start(self, "_run_thread_cache_shaders", 0, Thread.PRIORITY_LOW)
	assert(err == OK)

func stop(scene : Node, on_each : String, on_done : String) -> void:
	if self._get_is_running():
		self._set_is_running(false)

	if _thread:
		_thread.wait_to_finish()
		_thread = null

	# Reset shader compilation mode to previous
	ProjectSettings.set_setting("rendering/gles3/shaders/shader_compilation_mode", _prev_shader_compilation_mode)

	# Disconnect callbacks
	self.disconnect("on_each", scene, on_each)
	self.disconnect("on_done", scene, on_done)



func _get_ext_resource_textures(file_name : String) -> Array:
	var texture_files := []

	var headers = self._parse_resource_file_section_headers(file_name, "ext_resource")
	for header in headers:
		for key in header:
			if key == "type":
				var value = header[key]
				if value == "Texture":
					var path = header["path"]
					texture_files.append(path)

	return texture_files


func _run_thread_cache_shaders(_arg : int) -> void:
	var resource_files := self._get_res_file_list(["tscn", "tres"], _paths_to_ignore)

	# Find all the texture resources inside tcsn files
	for file_name in resource_files.duplicate():
		match file_name.get_extension().to_lower():
			"tscn":
				var texture_ext_resources = self._get_ext_resource_textures(file_name)
				for entry in texture_ext_resources:
					if not entry in resource_files:
						resource_files.append(entry)
			_:
				pass

	resource_files = self._sort_resource_files_by_type(resource_files)

	var i := 0
	var total := resource_files.size()
	while self._get_is_running() and not resource_files.empty():
		var file_name = resource_files.pop_front()
		i += 1
		var percent := i / float(total)

		# Warn of materials inside scenes that can't be cached
		self._warn_un_cacheable_sub_resource_materials(file_name)

		match file_name.get_extension().to_lower():
			"tscn", "tres", "bmp", "dds", "exr", "hdr", "jpeg", "jpg", "png", "svg", "svgz", "tga", "webp":
				var resource_type = self._get_resource_type(file_name)
				match resource_type:
					PackedScene, Texture, Shader, ShaderMaterial, SpatialMaterial, ParticlesMaterial, CanvasItemMaterial:
						var thing = self._cache_resource_material(file_name, resource_type)
						if thing:
							#var entry := { "file_name" : file_name, "thing" : thing, "resource_type" : resource_type }
							#self.call_deferred("emit_signal", "on_each", percent, entry.file_name, entry.thing, entry.resource_type)
							CallThrottled.call_throttled(funcref(self, "emit_signal"), ["on_each", percent, file_name, thing, resource_type])
						else:
							push_error("Failed to cache: %s, %s" % [file_name, resource_type])
					_:
						if _is_logging: print("##### Skipping caching: ", file_name)

	self._set_is_running(false)
	#self.call_deferred("emit_signal", "on_done")
	CallThrottled.call_throttled(funcref(self, "emit_signal"), ["on_done"])

func _cache_resource_material(file_name : String, resource_type : GDScriptNativeClass):
	var start_time := 0.0
	var size := 0.8

	start_time = OS.get_ticks_msec()
	var res : Resource = null

	match resource_type:
		Texture:
			# Load the image resource
			res = Image.new()
			var err : int = res.load(file_name)
			assert(err == OK)
		_:
			# Load the resource
			res = ResourceLoader.load(file_name)

	var is_desired_format := res is PackedScene or res is Image or res is Shader or res is ShaderMaterial or res is SpatialMaterial or res is ParticlesMaterial or res is CanvasItemMaterial
	if not is_desired_format:
		return null

	if _is_logging: print(file_name)
	if _is_logging: print("    Loading resource: ", OS.get_ticks_msec() - start_time)
	start_time = OS.get_ticks_msec()

	#print(res)
	match resource_type:
		PackedScene:
			_cache[file_name] = res
			return res
		Texture:
			var image_texture := ImageTexture.new()
			image_texture.create_from_image(res)

			_cache[file_name] = image_texture
			return image_texture
		Shader:
			var shader_mat := ShaderMaterial.new()
			shader_mat.shader = res
			var mesh_instance := MeshInstance.new()
			var cube_mesh := CubeMesh.new()
			cube_mesh.size = Vector3.ONE * size
			cube_mesh.material = shader_mat
			mesh_instance.mesh = cube_mesh

			_cache[file_name] = res
			return mesh_instance
		# Create a cube mesh that is loaded with the material
		ShaderMaterial, SpatialMaterial:
			var mesh_instance := MeshInstance.new()
			var cube_mesh := CubeMesh.new()
			cube_mesh.size = Vector3.ONE * size
			if _is_logging: print("    Creating mesh: ", OS.get_ticks_msec() - start_time)
			start_time = OS.get_ticks_msec()

			cube_mesh.material = res
			mesh_instance.mesh = cube_mesh
			if _is_logging: print("    Setting mesh material: ", OS.get_ticks_msec() - start_time)
			start_time = OS.get_ticks_msec()

			_cache[file_name] = res
			return mesh_instance
		ParticlesMaterial:
			var particles := Particles.new()
			var cube_mesh := CubeMesh.new()
			cube_mesh.size = Vector3.ONE * size
			if _is_logging: print("    Creating particles: ", OS.get_ticks_msec() - start_time)
			start_time = OS.get_ticks_msec()

			cube_mesh.material = res
			particles.process_material = res
			particles.draw_pass_1 = cube_mesh
			if _is_logging: print("    Setting particles material: ", OS.get_ticks_msec() - start_time)
			start_time = OS.get_ticks_msec()

			_cache[file_name] = res
			return particles
		CanvasItemMaterial:
			var mesh_instance := MeshInstance2D.new()
			var quad_mesh := QuadMesh.new()
			mesh_instance.scale = Vector2(25, -25)
			if _is_logging: print("    Creating mesh2d: ", OS.get_ticks_msec() - start_time)
			start_time = OS.get_ticks_msec()

			mesh_instance.mesh = quad_mesh
			mesh_instance.material = res
			if _is_logging: print("    Setting mesh2d material: ", OS.get_ticks_msec() - start_time)
			start_time = OS.get_ticks_msec()

			_cache[file_name] = res
			return mesh_instance

	return null

func _warn_un_cacheable_sub_resource_materials(file_name : String) -> void:
	var headers = self._parse_resource_file_section_headers(file_name, "sub_resource")
	for header in headers:
		for key in header:
			if key == "type":
				var value = header[key]
				match value:
					"ParticlesMaterial", "SpatialMaterial", "ShaderMaterial", "CanvasItemMaterial":
						push_warning("PreCache: scene '%s' sub resource %s can't be pre cached, unless saved in own *.tres file." % [file_name, value])

func _get_resource_type(file_name : String) -> GDScriptNativeClass:
	var ext := file_name.get_extension().to_lower()
	match ext:
		"bmp", "dds", "exr", "hdr", "jpeg", "jpg", "png", "svg", "svgz", "tga", "webp":
			return Texture
		"tscn":
			return PackedScene

	var headers = self._parse_resource_file_section_headers(file_name, "gd_resource")
	for header in headers:
		for key in header:
			if key == "type":
				var type = header[key]
				match type:
					"Shader": return Shader
					"ParticlesMaterial": return ParticlesMaterial
					"ShaderMaterial": return ShaderMaterial
					"SpatialMaterial": return SpatialMaterial
					"CanvasItemMaterial": return CanvasItemMaterial
					_:
						return null

	return null


func _sort_resource_files_by_type(resource_files : Array) -> Array:
	var images := []
	var shaders := []
	var spatial_mats := []
	var shader_mats := []
	var particle_mats := []
	var canvas_mats := []
	var scenes := []

	# Sort the list of resources by type
	while not resource_files.empty():
		var file_name = resource_files.pop_front()

		match file_name.get_extension().to_lower():
			"tscn":
				scenes.append(file_name)
			"bmp", "dds", "exr", "hdr", "jpeg", "jpg", "png", "svg", "svgz", "tga", "webp":
				images.append(file_name)
			"tres":
				var resource_type = self._get_resource_type(file_name)
				match resource_type:
					Shader:
						shaders.append(file_name)
					SpatialMaterial:
						spatial_mats.append(file_name)
					ShaderMaterial:
						shader_mats.append(file_name)
					ParticlesMaterial:
						particle_mats.append(file_name)
					CanvasItemMaterial:
						canvas_mats.append(file_name)

	resource_files.append_array(images)
	resource_files.append_array(shaders)
	resource_files.append_array(spatial_mats)
	resource_files.append_array(shader_mats)
	resource_files.append_array(particle_mats)
	resource_files.append_array(canvas_mats)
	resource_files.append_array(scenes)

	return resource_files

func _parse_resource_file_section_headers(file_name : String, section_name : String) -> Array:
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
				header[pair[0]] = pair[1].lstrip("\"").rstrip("\"")
				#print(pair)
			headers.append(header)
	#print("============================")
	return headers

func _get_res_file_list(extensions : Array, paths_to_ignore : Array) -> Array:
	var resources := []
	var paths := ["res://"]
	while not paths.empty():
		var path = paths.pop_front()

		for entry in DirectoryIterator.new(path, true, true):
			if entry.is_dir:
				paths.append(path + entry.name + '/')
			else:
				var full_entry = path + entry.name

				var is_ignored := false
				for path_to_ignore in paths_to_ignore:
					if full_entry.begins_with(path_to_ignore):
						is_ignored = true

				if not is_ignored and extensions.has(full_entry.get_extension().to_lower()):
					resources.append(full_entry)

	return resources

