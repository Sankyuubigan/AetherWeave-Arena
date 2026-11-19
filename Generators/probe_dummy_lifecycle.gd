extends SceneTree

## ГЕЙТ фикса Q37 (фидбэк юзера 19.11.26): красная капсула возвращалась после
## respawn (HealthComponent.respawn → mesh.show()), манекен не исчезал при смерти.
## NeuroDummyProp._process зеркалит is_dead. Проба: живой → смерть → респавн.
## ГЕЙТ: ALIVE cap=false prop=true | DEAD cap=false prop=false | RESPAWN cap=false prop=true.

func _init() -> void:
	await process_frame
	await process_frame
	await process_frame

	var arena = load("res://Scenes/MainArena.tscn").instantiate()
	root.add_child(arena)
	current_scene = arena
	await process_frame
	await process_frame

	var dummy = arena.get_node("Dummy") as Node3D
	var cap = dummy.get_node("MeshInstance3D") as MeshInstance3D
	var prop = dummy.get_node("Training Dummy") as Node3D
	var out := "res://_tmp_probe/neuro_props/"

	var cam := Camera3D.new()
	arena.add_child(cam)
	cam.current = true
	cam.position = Vector3(2.0, 1.6, -2.2)
	cam.look_at(Vector3(0, 1.0, -5))

	for i in 8:
		await process_frame
	print("GATE ALIVE: cap=", cap.visible, " prop=", prop.visible)
	root.get_texture().get_image().save_png(out + "lifecycle_alive.png")

	dummy.call("take_damage", 500)
	for i in 5:
		await process_frame
	print("GATE DEAD: cap=", cap.visible, " prop=", prop.visible)
	for i in 8:
		await process_frame
	root.get_texture().get_image().save_png(out + "lifecycle_dead.png")

	await create_timer(5.5).timeout
	for i in 8:
		await process_frame
	print("GATE RESPAWN: cap=", cap.visible, " prop=", prop.visible)
	root.get_texture().get_image().save_png(out + "lifecycle_respawn.png")
	quit(0)
