extends SceneTree
## Поиск кромки играбельного пола по z (x=0..40).

func _init() -> void:
	await process_frame
	var arena := (load("res://Scenes/MainArena.tscn") as PackedScene).instantiate()
	root.add_child(arena)
	current_scene = arena
	for i in 10:
		await process_frame
	var space: PhysicsDirectSpaceState3D = arena.get_world_3d().direct_space_state
	for p in [Vector2(0, -42), Vector2(0, -45), Vector2(0, -48), Vector2(0, -50),
			Vector2(20, -45), Vector2(40, -45), Vector2(40, -50),
			Vector2(60, -45), Vector2(80, -45), Vector2(-20, -45),
			Vector2(-40, -45), Vector2(-60, -45)]:
		var q := PhysicsRayQueryParameters3D.create(
			Vector3(p.x, 50, p.y), Vector3(p.x, -50, p.y))
		var hit: Dictionary = space.intersect_ray(q)
		if hit.is_empty():
			print("[RAY] (%d,%d): NET GRUNTA" % [p.x, p.y])
		else:
			print("[RAY] (%d,%d): y=%.2f" % [p.x, p.y, hit.position.y])
	quit(0)
