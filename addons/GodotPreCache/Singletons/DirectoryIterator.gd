# Copyright (c) 2022-2023 Matthew Brennan Jones <matthew.brennan.jones@gmail.com>
# This file is licensed under the MIT License
# https://github.com/ImmersiveRPG/GodotPreCache

extends Node
class_name DirectoryIterator

var _path : String
var _dir : Directory
var _file_name := ""
var _skip_navigational := false
var _skip_hidden := false

func _init(path : String, skip_navigational := false, skip_hidden := false) -> void:
	_path = path
	_skip_navigational = skip_navigational
	_skip_hidden = skip_hidden

func should_continue() -> bool:
	return not _file_name.empty()

func _iter_init(arg) -> bool:
	_dir = Directory.new()
	assert(_dir.open(_path) == OK)
	assert(_dir.list_dir_begin(_skip_navigational, _skip_hidden) == OK)
	_file_name = _dir.get_next()
	return should_continue()

func _iter_next(arg) -> bool:
	_file_name = _dir.get_next()

	# Close the directory if this is the end
	var retval := should_continue()
	if not retval:
		_dir.list_dir_end()
	return retval

func _iter_get(arg) -> Dictionary:
	return {
		"name" : _file_name,
		"is_dir" : _dir.current_is_dir()
	}
