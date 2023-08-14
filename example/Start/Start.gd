extends Spatial


func _on_ButtonMakeSprite3D_pressed() -> void:
	print(ResourceLoader.has_cached("res://icon.png"))
	print(ResourceLoader.has_cached("res://example/GodotSprite3D/GodotSprite3D.tscn"))

	var start := OS.get_ticks_usec()
	var scene = ResourceLoader.load("res://example/GodotSprite3D/GodotSprite3D.tscn")
	print("!! load: %s" % [OS.get_ticks_usec() - start])

	start = OS.get_ticks_usec()
	var node = scene.instance()
	print("!! instance: %s" % [OS.get_ticks_usec() - start])

	start = OS.get_ticks_usec()
	self.add_child(node)
	print("!! add_child: %s" % [OS.get_ticks_usec() - start])

	node.transform.origin = Vector3(0, 9.264, -7)
	print([node, scene])
	
	print(ResourceLoader.has_cached("res://icon.png"))
	print(ResourceLoader.has_cached("res://example/GodotSprite3D/GodotSprite3D.tscn"))
