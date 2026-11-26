extends SceneTree
## РЕНДЕР-ПРОБА «куда смотрит перс» (26.11.26). Оконный режим (не headless:
## в headless нет текстур вьюпорта). Снимает 4 PNG в tasks/<сессия>/shots/:
##   start_yaw0.png   — как игра стартует сейчас (wrapper.yaw = 0)
##   start_yaw180.png — если развернуть обёртку на 180°
##   cast_standing.png— каст СТОЯ после бега (главный сценарий бага)
##   cast_spawn.png   — каст на старте (yaw = 0)
## Запуск: Godot (окно) -s res://Generators/render_facing_shots.gd

const PLAYER_SCENE := "res://Scenes/player.tscn"
const OUT := "res://tasks/261125_1509-02207363/shots/"

var player: Node3D
var wrapper: Node3D
var cam: Camera3D

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.15, 0.17, 0.2)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.6, 0.62, 0.7)
	e.ambient_light_energy = 1.0
	env.environment = e
	root.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45, 30, 0)
	sun.shadow_enabled = true
	root.add_child(sun)
	_make_floor()

	player = load(PLAYER_SCENE).instantiate()
	root.add_child(player)
	player.global_position = Vector3(0, 1.0, 0)
	for i in 40:
		await physics_frame
	wrapper = player.get_node_or_null("GraphicsWrapper")
	cam = player.get_node_or_null("SpringArm3D/Camera3D")
	if wrapper == null or cam == null:
		print("RENDER FAIL: нет wrapper/camera")
		quit(1)
		return

	# 1) старт как есть
	wrapper.rotation.y = 0.0
	await _shot("start_yaw0.png")

	# 2) обёртка на 180°
	wrapper.rotation.y = PI
	await _shot("start_yaw180.png")

	# 3) каст СТОЯ после бега: перс «бежал вперёд» (yaw=π), кастует
	wrapper.rotation.y = PI
	var comp = player.get_node_or_null("PlayerAnimationComponent")
	var sc = player.get_node_or_null("SpellCasterComponent")
	if comp != null:
		comp.play_cast_anim("Cast_1H_Magic_01")
	if sc != null:
		var aim: Vector3 = sc._aim_dir_point(player, 30.0)
		player.face_aim_target(aim, 2.0)
	for i in 60:
		await physics_frame
	await _shot("cast_standing.png")
	print("  после каста: wrapper.yaw = %+.1f° (ожидалось ~180°)" % rad_to_deg(wrapper.rotation.y))

	# 4) каст на старте (yaw=0 — как игра начинает)
	wrapper.rotation.y = 0.0
	player._cast_facing_timer = 0.0
	await physics_frame
	if sc != null:
		var aim2: Vector3 = sc._aim_dir_point(player, 30.0)
		player.face_aim_target(aim2, 2.0)
	for i in 60:
		await physics_frame
	await _shot("cast_spawn.png")
	print("  каст на старте: wrapper.yaw = %+.1f° (кламп 100° сработал бы тут)" % rad_to_deg(wrapper.rotation.y))
	quit(0)

func _shot(file: String) -> void:
	for i in 6:
		await process_frame
	var img := root.get_viewport().get_texture().get_image()
	if img == null:
		print("  SHOT FAIL: нет изображения (нужен оконный режим)")
		return
	var path := OUT + file
	var err := img.save_png(ProjectSettings.globalize_path(path))
	print("  shot %-22s err=%d" % [file, err])

func _make_floor() -> void:
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
	mat.albedo_color = Color(0.35, 0.38, 0.32)
	mi.material_override = mat
	body.add_child(mi)
	root.add_child(body)
	body.global_position = Vector3(0, -0.5, 0)
