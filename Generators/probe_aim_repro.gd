extends SceneTree
## РЕПРО бага «разворот в камеру» (26.11.26): где на самом деле точка прицела.
## Перс стоит спиной к камере (wrapper.yaw = π, как после бега). Крутим наклон
## камеры и смотрим, КУДА попадает луч _aim_point и какой yaw получается.
## Запуск: --headless -s res://Generators/probe_aim_repro.gd

const PLAYER_SCENE := "res://Scenes/player.tscn"

var player: Node3D
var wrapper: Node3D

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	player = load(PLAYER_SCENE).instantiate()
	root.add_child(player)
	player.global_position = Vector3(0, 1.0, 0)
	_make_floor()
	for i in 30:
		await physics_frame
	wrapper = player.get_node_or_null("GraphicsWrapper")
	var sc = player.get_node_or_null("SpellCasterComponent")
	var cam: Camera3D = player.get_node_or_null("SpringArm3D/Camera3D")
	if wrapper == null or sc == null or cam == null:
		print("REPRO FAIL: нет узлов")
		quit(1)
		return
	wrapper.rotation.y = PI   # спиной к камере (как после бега «вперёд»)
	print("стартовый наклон камеры из сцены: %.1f°" % rad_to_deg(player._cam_pitch))
	print("")
	print("%-8s %-26s %-22s %-10s %s" % ["pitch", "точка прицела", "d (от игрока)", "yaw", "ВЕРДИКТ"])
	for pitch_deg in [0, -15, -30, -40, -50, -60]:
		player._cam_pitch = deg_to_rad(float(pitch_deg))
		for i in 4:
			await physics_frame
		var aim: Vector3 = sc._aim_point(player, 30.0)
		var d: Vector3 = aim - player.global_position
		d.y = 0.0
		var yaw := 0.0
		if d.length() > 0.01:
			yaw = rad_to_deg(atan2(d.x, d.z))
		var cam_pos := cam.global_position
		var verdict := "OK (впереди)"
		if d.length() <= 0.01:
			verdict = "ВЫРОЖДЕНА (d≈0)"
		elif d.z > 0.0:
			verdict = "ЗА СПИНОЙ -> разворот в камеру!"
		print("%-8.0f (%.1f,%.1f,%.1f)%-12s (%.1f,%.1f,%.1f)%-6s %+8.1f° %s" % [
			float(pitch_deg), aim.x, aim.y, aim.z, "",
			d.x, d.y, d.z, "", yaw, verdict])
		print("         камера=%.2f,%.2f,%.2f  (высота над полом %.2f)" % [
			cam_pos.x, cam_pos.y, cam_pos.z, cam_pos.y - 1.0])
	print("")
	print("ВЫВОД: если при взгляде вниз луч бьёт в пол МЕЖДУ камерой и игроком,")
	print("точка оказывается ЗА спиной -> face_aim_target крутит перса в камеру.")
	quit(0)

func _make_floor() -> void:
	var body := StaticBody3D.new()
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(200, 1, 200)
	col.shape = shape
	body.add_child(col)
	root.add_child(body)
	body.global_position = Vector3(0, -0.5, 0)
