# Copyright (c) 2022 Matthew Brennan Jones <matthew.brennan.jones@gmail.com>
# This file is licensed under the MIT License
# https://github.com/ImmersiveRPG/GodotPreShaderCache

extends StaticBody

export var _has_power := false
export var _has_signal := true
var colors := [Color.aqua, Color.orange, Color.green, Color.red]

onready var _omni_light = $BackLight/OmniLight
onready var _spot_light = $BackLight/SpotLight

var _normal_shader = null

func _ready() -> void:
	self._on_Timer_timeout()

func _on_toggle_power() -> void:
	_has_power = not _has_power
	self._on_Timer_timeout()

func _on_toggle_signal() -> void:
	_has_signal = not _has_signal
	self._on_Timer_timeout()

func _on_Timer_timeout() -> void:
	$BackLight.visible = _has_power

	$ScreenNormal.visible = _has_power and _has_signal
	$ScreenStatic.visible = _has_power and not _has_signal

	if _has_power and _has_signal:
		if not _normal_shader:
			_normal_shader = $ScreenNormal.mesh.surface_get_material(0)

		# Pick a random color
		var i = randi() % colors.size()
		var color = colors[i]

		# Set screen color
		_normal_shader.set_shader_param("screen_color", Vector3(color.r, color.g, color.b))

		# Set light color
		_omni_light.light_color = color
		_spot_light.light_color = color
	elif _has_power and not _has_signal:
		# Set light color
		_omni_light.light_color = Color.white
		_spot_light.light_color = Color.white
