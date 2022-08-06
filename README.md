# GodotPreShaderCache
A Godot plugin to compile and pre cache shader materials

# TODO

* Remove need to call ShaderCache.stop
* Break ShaderCache into 2 threads to remove stupid spin lock. Keep in same file:
	* One for caching shader
	* And another for adding to client when it says it is ready 
