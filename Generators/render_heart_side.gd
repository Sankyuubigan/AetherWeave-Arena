extends SceneTree
## РЕНДЕР-ПОДТВЕРЖДЕНИЕ (26.11.26): вынос кистей ВПЕРЁД проверяем с БОКОВОЙ
## камеры — сзади вынос вперёд ракурсно укорачивается и кажется «руки у груди»,
## поэтому задний вид не доказательство. Снимаем 2 клипа × 2 ракурса.
## Запуск (окно!): Godot -s res://Generators/render_heart_side.gd

const PLAYER_SCENE := "res://Scenes/player.tscn"
const OUT := "res://tasks/261125_1509-02207363/shots_heart_side/"
## [клип, доля длины]
const SHOTS := [
	["Pistol_Shoot", 0.25],
	["Pistol_Shoot", 0.60],
	["Spell_Cast", 0.38],
]

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	_setup_world()
	var player: Node3D = load(PLAYER_SCENE).instantiate()
	root.add_child(player)
	player.global_position = Vector3(0, 1.0, 0)
	player.rotation.y = 0.0
	for i in 40:
		await physics_frame
	player.get_node_or_null("GraphicsWrapper").rotation.y = PI
	var comp = player.get_node_or_null("PlayerAnimationComponent")
	var cam: Camera3D = player.get_node_or_null("SpringArm3D/Camera3D")
	if comp == null or cam == null:
		print("SIDE FAIL: нет компонента/камеры")
		quit(1)
		return

	for item in SHOTS:
		var clip: String = item[0]
		var frac: float = item[1]
		comp.play_cast_anim(clip)
		var len: float = comp.cast_last_len()
		var target_t: float = len * frac
		var t := 0.0
		while t < target_t:
			await process_frame
			t += get_root().get_process_delta_time()
		# Перс смотрит в −Z (wrapper π). Боковая камера — с +X, смотрит на −X.
		var base := player.global_position
		for view in ["side", "back"]:
			if view == "side":
				cam.global_position = base + Vector3(4.6, 1.9, 0.0)
			else:
				cam.global_position = base + Vector3(0.8, 2.4, 4.2)
			cam.look_at(base + Vector3(0, 1.25, 0), Vector3.UP)
			for i in 4:
				await process_frame
			var img := root.get_viewport().get_texture().get_image()
			if img == null:
				print("  SHOT FAIL (нужен оконный режим)")
				continue
			var f := "%s_%s_%s.png" % [clip, String.num(frac, 2), view]
			print("  shot %-34s err=%d" % [f,
				img.save_png(ProjectSettings.globalize_path(OUT + f))])
	print("SIDE RENDER: готово → ", OUT)
	quit(0)

func _setup_world() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.16, 0.18, 0.21)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.65, 0.67, 0.72)
	env.environment = e
	root.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 35, 0)
	sun.shadow_enabled = true
	root.add_child(sun)
	var body := StaticBody3D.new()
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(200, 1, 200)
	col.shape = shape
	body.add_child(col)
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(200, 1, 200)
	mi.mesh = bm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.34, 0.37, 0.32)
	mi.material_override = mat
	body.add_child(mi)
	root.add_child(body)
	body.global_position = Vector3(0, -0.5, 0)
