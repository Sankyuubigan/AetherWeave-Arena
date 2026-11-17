extends SceneTree
## Кадровая проверка прыжка после фикса _cut_from (сдвиг ключей назад):
## обычный прыжок на реальном компоненте + цифры производного клипа.
## Запуск (скрытое окно): _tmp_probe/run_jump_check.ps1

const OUT := "res://_tmp_probe/"

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var world := Node3D.new()
	root.add_child(world)
	var floor_body := StaticBody3D.new()
	var floor_shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(30, 1, 30)
	floor_shape.shape = box
	floor_body.add_child(floor_shape)
	floor_body.position = Vector3(0, -0.5, 0)
	var floor_mesh := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(30, 1, 30)
	floor_mesh.mesh = mesh
	floor_body.add_child(floor_mesh)
	world.add_child(floor_body)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, -30, 0)
	world.add_child(sun)
	var player = load("res://Scenes/player.tscn").instantiate()
	player.position = Vector3(0, 1.0, 0)
	world.add_child(player)
	var cam := Camera3D.new()
	world.add_child(cam)
	cam.position = Vector3(0.4, 1.7, 3.4)
	cam.look_at(Vector3(0, 1.0, 0))
	cam.current = true

	var comp = player.get_node("PlayerAnimationComponent")
	for i in 100:
		await process_frame
	# Цифры: первый ключ Jump_Launch должен стоять у нуля (не на 0.33)
	var jl: Animation = comp.anim_player.get_animation("Jump_Launch")
	var j0: Animation = comp.anim_player.get_animation("Jump")
	var first_jl: float = jl.track_get_key_time(0, 0)
	var first_j: float = j0.track_get_key_time(0, 0)
	print("RJ: Jump первый ключ=", "%.2f" % first_j, " → Jump_Launch первый ключ=", "%.2f" % first_jl, " (длина ", "%.2f" % jl.length, ")")

	await _shot("jump_00_idle.png")
	# как в PlayerController: физика + анимация вместе
	player.velocity.y = player.jump_velocity
	comp.play_jump(false)
	# Съёмка по PHYSICS-кадрам: process без vsync летит быстрее физики,
	# 100 process-кадров ≈ 0.75с — приземления не дождались (первый прогон).
	for f in 110:
		await physics_frame
		match f:
			4: await _shot("jump_01_launch.png")
			14: await _shot("jump_02_rise.png")
			26: await _shot("jump_03_apex.png")
			40: await _shot("jump_04_fall.png")
			55: await _shot("jump_05_fall2.png")
			70: await _shot("jump_06_land.png")
			90: await _shot("jump_07_after.png")
			105: await _shot("jump_08_recover_end.png")
	print("RJ: конец, состояние=", comp.loco_state(), "/", comp.playback.get_current_node())
	quit(0)

func _shot(file_name: String) -> void:
	await process_frame
	var img: Image = root.get_viewport().get_texture().get_image()
	img.save_png(OUT + file_name)
	print("RJ: кадр ", file_name)
