extends SceneTree
## Кадровая проверка отмены кастов при спаме (баг 17.11.26): повторный каст
## того же скилла РЕСТАРТУЕТ жест, другой скилл ПЕРЕБИВАЕТ — поверх живого
## Run, последовательностью фиксированного компонента (stop→play→capture).
## ОДИН процесс (§11.29), запуск скрытно: _tmp_probe/run_ub.ps1 (тот же паттерн).
## Кадры: _tmp_probe/spam_<метка>_fXX.png

const PLAYER_SCENE := "res://Scenes/player.tscn"
const TEST_LIB := "res://Graphics/Animations/ual_casts_test.res"
const OUT_DIR := "res://_tmp_probe"

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	DisplayServer.window_set_position(Vector2i(-2400, -2400))
	var packed: PackedScene = load(PLAYER_SCENE)
	var player: Node = packed.instantiate()
	_strip_scripts(player)
	root.add_child(player)
	await process_frame
	await process_frame

	var loco: AnimationPlayer = player.get_node("GraphicsWrapper/AnimationPlayer")
	var castp := AnimationPlayer.new()
	loco.get_parent().add_child(castp)
	castp.root_node = loco.root_node
	var src_lib = load(TEST_LIB)
	var clib := AnimationLibrary.new()
	for an in src_lib.get_animation_list():
		if String(an).ends_with("_UB"):
			clib.add_animation(an, src_lib.get_animation(an))
	castp.add_animation_library("", clib)

	var floor_node := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(20, 20)
	floor_node.mesh = pm
	var fmat := StandardMaterial3D.new()
	fmat.albedo_color = Color(0.35, 0.35, 0.4)
	floor_node.material_override = fmat
	root.add_child(floor_node)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, -30, 0)
	root.add_child(sun)
	var sun2 := DirectionalLight3D.new()
	sun2.rotation_degrees = Vector3(-40, 150, 0)
	sun2.light_energy = 0.5
	root.add_child(sun2)
	var cam := Camera3D.new()
	root.add_child(cam)
	cam.look_at_from_position(Vector3(0, 1.35, 3.6), Vector3(0, 1.0, 0), Vector3.UP)
	cam.make_current()

	loco.play("Run")
	for i in 20:
		await process_frame

	# 1-е нажатие сердца
	castp.stop(); castp.play("Heart_Cast_UB", 0.1); castp.capture("Heart_Cast_UB", 0.1)
	await _frames(20, "h1")
	# 2-е нажатие сердца ПОСРЕДИ жеста → рестарт с нуля
	castp.stop(); castp.play("Heart_Cast_UB", 0.1); castp.capture("Heart_Cast_UB", 0.1)
	print("SPAMCHK повтор: pos=", castp.current_animation_position)
	await _frames(15, "h2")
	# переключение на Throw посреди сердечка → перебивание
	castp.stop(); castp.play("Throw_UB", 0.1); castp.capture("Throw_UB", 0.1)
	print("SPAMCHK перебит: current=", castp.current_animation)
	await _frames(25, "thr")

	print("SPAM RENDER DONE")
	quit(0)

func _frames(n: int, tag: String) -> void:
	for i in n:
		await process_frame
		if i % 5 == 0:
			var img := root.get_texture().get_image()
			var path := "%s/spam_%s_f%02d.png" % [OUT_DIR, tag, i / 5]
			img.save_png(path)
			print("SPAMCHK ", tag, " f", i / 5, " → ", path)

func _strip_scripts(n: Node) -> void:
	if n.get_script() != null:
		n.set_script(null)
	for c in n.get_children():
		_strip_scripts(c)
