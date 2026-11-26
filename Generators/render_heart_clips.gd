extends SceneTree
## РЕНДЕР (26.11.26): что видит ЮЗЕР при касте сердечка — камера СЗАДИ, как в игре.
## Сравниваем клипы-кандидаты на одном кадре пика, чтобы выбрать «рука вперёд,
## а не в стороны». Запуск ОКОННЫЙ (headless не рендерит):
##   Godot -s res://Generators/render_heart_clips.gd

const PLAYER_SCENE := "res://Scenes/player.tscn"
const OUT := "res://tasks/261125_1509-02207363/shots_heart/"
## [клип, доля длины для кадра]
const SHOTS := [
	["Spell_Cast", 0.38],
	["Pistol_Shoot", 0.75],
	["Cast_1H_Magic_01", 0.58],
	["Beam_Push", 0.26],
	["Throw", 0.95],
	["Cast_2H_Magic_01", 0.58],
]

var player: Node3D
var comp
var cam: Camera3D

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	_setup_world()
	player = load(PLAYER_SCENE).instantiate()
	root.add_child(player)
	player.global_position = Vector3(0, 1.0, 0)
	player.rotation.y = 0.0
	for i in 40:
		await physics_frame
	var wrapper: Node3D = player.get_node_or_null("GraphicsWrapper")
	wrapper.rotation.y = PI          # как в игре: спиной к камере
	comp = player.get_node_or_null("PlayerAnimationComponent")
	cam = player.get_node_or_null("SpringArm3D/Camera3D")
	if comp == null or cam == null:
		print("RENDER FAIL: нет компонента/камеры")
		quit(1)
		return
	# Камера как в игре: сзади и чуть сверху, смотрит на спину.
	cam.global_position = player.global_position + Vector3(0.8, 2.4, 4.2)
	cam.look_at(player.global_position + Vector3(0, 1.3, 0), Vector3.UP)

	for item in SHOTS:
		var clip: String = item[0]
		var frac: float = item[1]
		if not comp.has_cast_anim(clip):
			print("  нет клипа ", clip)
			continue
		comp.play_cast_anim(clip)
		var len: float = comp.cast_last_len()
		var target_t: float = len * frac
		var t := 0.0
		while t < target_t:
			await process_frame
			t += get_root().get_process_delta_time()
		for i in 3:
			await process_frame
		var img := root.get_viewport().get_texture().get_image()
		if img == null:
			print("  SHOT FAIL (нужен оконный режим)")
			continue
		var f := "%s_%s.png" % [clip, String.num(frac, 2)]
		print("  shot %-28s err=%d" % [f,
			img.save_png(ProjectSettings.globalize_path(OUT + f))])
		await process_frame
	print("RENDER: готово → ", OUT)
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
