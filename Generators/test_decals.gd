extends SceneTree

## Тест QUEUE Q5: декали — генераторы DecalFrames.blood_splatter/lava_puddle,
## AnimatedDecalComponent.set_emission, мета-флоу decal_scale/lava_pool в
## ProjectileComponent._spawn_scorch (метеор → подпалина + лужа лавы).
## Гейт: GATE ALL PASS, иначе quit(1).

const DecalFrames = preload("res://Graphics/DecalFrames.gd")
const ADC = preload("res://Graphics/AnimatedDecalComponent.gd")
const ProjScript = preload("res://Logic/ProjectileComponent.gd")

var fails := 0

func _init() -> void:
	await process_frame
	_run()

func _check(name: String, cond: bool) -> void:
	if cond:
		print("PASS: " + name)
	else:
		fails += 1
		print("FAIL: " + name)

func _painted(im: Image) -> int:
	var n := 0
	for y in 64:
		for x in 64:
			if im.get_pixel(x, y).a > 0.3:
				n += 1
	return n

func _run() -> void:
	var scene := Node3D.new()
	root.add_child(scene)
	current_scene = scene # ПОСЛЕ add_child: сеттер -s-режима до входа в дерево не сработал

	# Пол для ray-нормали (surface_normal) и place().
	var floor_body := StaticBody3D.new()
	var floor_mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(30, 0.5, 30)
	floor_mesh.mesh = box
	floor_body.add_child(floor_mesh)
	var floor_shape := CollisionShape3D.new()
	var bshape := BoxShape3D.new()
	bshape.size = Vector3(30, 0.5, 30)
	floor_shape.shape = bshape
	floor_body.add_child(floor_shape)
	floor_body.position = Vector3(0, -0.25, 0)
	scene.add_child(floor_body)

	# --- Генераторы кадров ---
	var blood := DecalFrames.blood_splatter(Color(0.42, 0.015, 0.015))
	_check("blood: 6 кадров", blood.size() == 6)
	_check("blood: центр непрозрачный", blood[0].get_pixel(32, 32).a > 0.0)
	_check("blood: расползание", _painted(blood[5]) >= _painted(blood[0]))

	var lava := DecalFrames.lava_puddle(Color(1.0, 0.38, 0.03))
	_check("lava: 8 кадров", lava.size() == 8)
	var painted := false
	for y in 64:
		for x in 64:
			if lava[0].get_pixel(x, y).a > 0.05:
				painted = true
	_check("lava: корка нарисована", painted)

	# --- AnimatedDecalComponent + set_emission ---
	var decal := ADC.new()
	decal.configure(blood, 8.0, 14.0, 2.4)
	scene.add_child(decal)
	decal.place(Vector3(0, 0.05, 0), Vector3.UP)
	_check("place: над полом", decal.global_position.y > 0.0)
	decal.set_emission(2.5)
	_check("emission_energy применён", decal.texture_emission != null and absf(decal.emission_energy - 2.5) < 0.01)

	# Декаль-проба больше не нужна (не мешает подсчёту ниже) — free сразу.
	decal.free()

	# --- Мета-флоу снаряда: decal_scale + lava_pool → подпалина + лужа ---
	var proj := ProjScript.new()
	proj.set_meta("decal_scale", 2.4)
	proj.set_meta("lava_pool", true)
	scene.add_child(proj)
	proj.global_position = Vector3(0, 0.2, 0)
	proj._spawn_scorch()
	var decal_count := 0
	for c in scene.get_children():
		if c is Decal:
			decal_count += 1
	_check("метеор: подпалина + лужа = 2 декали", decal_count == 2)

	if fails == 0:
		print("GATE ALL PASS")
	else:
		print("GATE FAILURES: %d" % fails)
	quit(1 if fails > 0 else 0)
