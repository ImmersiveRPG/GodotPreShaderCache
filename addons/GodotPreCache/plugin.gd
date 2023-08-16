# Copyright (c) 2022-2023 Matthew Brennan Jones <matthew.brennan.jones@gmail.com>
# This file is licensed under the MIT License
# https://github.com/ImmersiveRPG/GodotPreCache

tool
extends EditorPlugin

# Get the name and paths of all the autoloads
const autoloads := [
	{"name": "PreCache", "path": "res://addons/GodotPreCache/Singletons/PreCache.gd"},
]

func _enter_tree() -> void:
	# Install all the autoloads
	for entry in autoloads:
		print("Adding Autoload: %s" % [entry.name])
		if not ProjectSettings.has_setting("autoload/%s" % [entry.name]):
			self.add_autoload_singleton(entry.name, entry.path)

	print("Installed plugin Godot Pre Cache")

func _exit_tree() -> void:
	# Uninstall all the autoloads
	var reverse_autoloads := autoloads.duplicate()
	reverse_autoloads.invert()
	for entry in reverse_autoloads:
		print("Removing Autoload: %s" % [entry.name])
		if ProjectSettings.has_setting("autoload/%s" % [entry.name]):
			self.remove_autoload_singleton(entry.name)

	print("Uninstalled plugin Godot Pre Cache")
