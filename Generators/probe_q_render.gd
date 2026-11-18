extends SceneTree

## Рендер-проба батча качества (QUEUE Q1-Q6, 19.11.26): желе-монстр на
## MainArena + декали-пробы (подпалина / лава / кровь) на полу между камерой
## и желе. PNG → _tmp_probe/q_jelly_decals.png, гейт QSHOT. PNG смотрю сам.

const ADC = preload("res://Graphics/AnimatedDecalComponent.gd")
const DF = preload("res://Graphics/DecalFrames.gd")

func _init() -> void:
	await process_frame
	var ps := (load("res://Scenes/MainArena.tscn") as PackedScene).instantiate()
	current_scene = ps
	root.add_child(ps)
	await process_frame
	await process_frame

	var cam := Camera3D.new()
	root.add_child(cam)
	cam.position = Vector3(12.5, 2.2, -2)
	cam.look_at(Vector3(7, 2.6, -6))
	cam.current = true

	# Декали-пробы на полу между камерой (12.5, -2) и желе (7, -6).
	var entries := [
		[DF.explosion_scorch(Color(1.0, 0.45, 0.1)), 12.0, 1.6, false, Vector3(10, 0.03, -3.2)],
		[DF.lava_puddle(Color(1.0, 0.38, 0.03)), 6.0, 2.4, true, Vector3(9.5, 0.03, -4.2)],
		[DF.blood_splatter(Color(0.42, 0.015, 0.015)), 8.0, 2.4, false, Vector3(10.2, 0.03, -4.8)],
	]
	for e in entries:
		var d := ADC.new()
		d.configure(e[0], e[1], 120.0, e[2], e[3])
		if e[3]:
			d.set_emission(4.0)
		root.add_child(d)
		d.place(e[4], Vector3.UP)

	for i in 40:
		await process_frame

	DirAccess.make_dir_recursive_absolute("res://_tmp_probe")
	var img := root.get_texture().get_image()
	img.save_png("res://_tmp_probe/q_jelly_decals.png")
	print("QSHOT")
	quit(0)
