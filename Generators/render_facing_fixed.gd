extends SceneTree
## РЕНДЕР-ПРОБА ПОСЛЕ ФИКСА (26.11.26): подтверждаем глазами, что
##  1) СТАРТ игры — перс спиной к камере (было: лицом);
##  2) КАСТ СТОЯ после бега — НЕ разворачивает (главная жалоба юзера);
##  3) КАСТ при наклоне камеры вниз — тоже не разворачивает;
##  4) КАСТ с целью вбок — доворачивает в сторону цели (не в камеру).
## Запуск (окно!): Godot -s res://Generators/render_facing_fixed.gd

const PLAYER_SCENE := "res://Scenes/player.tscn"
const OUT := "res://tasks/261125_1509-02207363/shots_fixed/"

var player: Node3D
var wrapper: Node3D
var cam: Camera3D
var sc
var comp

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	_setup_world()
	player = load(PLAYER_SCENE).instantiate()
	root.add_child(player)
	player.global_position = Vector3(0, 1.0, 0)
	for i in 40:
		await physics_frame
	wrapper = player.get_node_or_null("GraphicsWrapper")
	cam = player.get_node_or_null("SpringArm3D/Camera3D")
	sc = player.get_node_or_null("SpellCasterComponent")
	comp = player.get_node_or_null("PlayerAnimationComponent")
	if wrapper == null or cam == null or sc == null:
		print("FIXED FAIL: нет узлов")
		quit(1)
		return
	print("старт: wrapper.yaw = %+.1f° (должно быть 180)" % rad_to_deg(wrapper.rotation.y))

	# 1) старт как есть (после фикса _ready)
	await _shot("1_start.png")

	# 2) каст стоя после бега «вперёд»
	wrapper.rotation.y = PI
	player._cast_facing_timer = 0.0
	await physics_frame
	_aim_and_cast()
	await _shot("2_cast_after_run.png")

	# 3) каст при камере, наклонённой вниз (был главный триггер бага)
	player._cam_pitch = deg_to_rad(-55.0)
	for i in 4:
		await physics_frame
	_aim_and_cast()
	await _shot("3_cast_cam_down.png")

	# 4) каст с целью сбоку — доворот в сторону, а не в камеру
	player._cam_pitch = deg_to_rad(-10.0)
	player.rotation.y = 0.0
	wrapper.rotation.y = PI
	await physics_frame
	if comp != null:
		comp.play_cast_anim("Cast_1H_Magic_01")
	player.face_aim_target(player.global_position + Vector3(-25, 0, 0), 2.0)
	for i in 60:
		await physics_frame
	print("  цель вбок → wrapper.yaw = %+.1f° (ждём ~ -90 от старта 180 = 90)" % rad_to_deg(wrapper.rotation.y))
	await _shot("4_cast_side_target.png")
	quit(0)

func _aim_and_cast() -> void:
	if comp != null:
		comp.play_cast_anim("Cast_1H_Magic_01")
	var aim: Vector3 = sc._aim_dir_point(player, 30.0)
	player.face_aim_target(aim, 2.0)
	for i in 60:
		await physics_frame

func _shot(file: String) -> void:
	for i in 6:
		await process_frame
	var img := root.get_viewport().get_texture().get_image()
	if img == null:
		print("  SHOT FAIL (нужен оконный режим)")
		return
	print("  shot %-24s err=%d" % [file,
		img.save_png(ProjectSettings.globalize_path(OUT + file))])

func _setup_world() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.15, 0.17, 0.2)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.6, 0.62, 0.7)
	env.environment = e
	root.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45, 30, 0)
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
	mat.albedo_color = Color(0.35, 0.38, 0.32)
	mi.material_override = mat
	body.add_child(mi)
	root.add_child(body)
	body.global_position = Vector3(0, -0.5, 0)
