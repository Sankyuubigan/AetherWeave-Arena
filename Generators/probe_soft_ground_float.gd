extends SceneTree

## Q32-FIX гейт «персонаж висит над дюной» (баг-репорт юзера 20.11.26):
## 1) convex-коллизия совпадает с базовым мешом (топ = BASE_H 0.32) —
##    create_convex_shape(simplify=true) ДУЛА hull (0.476/-0.095), заменён
##    на фрустум 12 точек;
## 2) рейкаст в центр дюны бьёт в ту же высоту;
## 3) болванка стоит на коллизии, не парит;
## 4) насыщенный промин визуально ≤ 0.08 м (dent_scale SSOT = компонент,
##    0.07 — было 0.30: след 13.5 см + воронка 30 см = «бежит по воздуху»).
## Запуск: powershell -File _tmp_probe/run_godot.ps1 res://Generators/probe_soft_ground_float.gd

const SG := "res://Graphics/Environment/Props/soft_ground/soft_ground.tscn"
const BASE_H := 0.32
const CAP_MAX := 0.08

func _init() -> void:
	var wd := create_timer(30.0)
	wd.timeout.connect(func() -> void:
		printerr("[SGF] TIMEOUT")
		quit(1))
	_run()

func _run() -> void:
	# Пол (за краями патча болванка может свалиться — пусть стоит на дюне)
	var ground := StaticBody3D.new()
	var fcs := CollisionShape3D.new()
	var fbox := BoxShape3D.new()
	fbox.size = Vector3(80, 1, 80)
	fcs.shape = fbox
	fcs.position = Vector3(0, -0.5, 0)
	ground.add_child(fcs)
	root.add_child(ground)

	var sg: Node3D = (load(SG) as PackedScene).instantiate()
	root.add_child(sg)
	await physics_frame
	await physics_frame

	# 1) Коллизия = HeightMapShape3D 25×25, scale 0.5 (фикс 20.11.26: convex
	#    хулл не деформировался проминами; heightmap мутируется компонентом)
	var body_node := sg.find_child("GroundBody", true, false)
	if body_node == null:
		printerr("[SGF] FAIL: нет GroundBody в префабе")
		quit(1)
		return
	var cs := body_node.get_child(0) as CollisionShape3D
	var hmsh := cs.shape as HeightMapShape3D
	var chk_a: bool = hmsh != null and hmsh.map_width == 25 and hmsh.map_depth == 25 \
			and absf(cs.scale.x - 0.5) < 0.001
	if hmsh == null:
		printerr("[SGF] FAIL: коллизия не HeightMapShape3D")
	else:
		print("[SGF] heightmap %dx%d scale=%.2f (центр shape=%.3f = %.2f/0.5)" % [
			hmsh.map_width, hmsh.map_depth, cs.scale.x,
			hmsh.map_data[12 * 25 + 12], BASE_H])

	# 2) Рейкаст в центр дюны
	var space := root.get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(Vector3(0, 5, 0), Vector3(0, -1, 0))
	var hit := space.intersect_ray(q)
	var chk_b: bool = false
	if hit:
		print("[SGF] ray центр: y=%.3f" % hit.position.y)
		chk_b = absf(hit.position.y - BASE_H) < 0.02
	else:
		printerr("[SGF] FAIL: рейкаст в центр дюны НЕ попал (нет коллизии?)")

	# 3) Болванка стоит на дюне в центре (капсула 0.35/1.7 встаёт с h/2)
	var body := CharacterBody3D.new()
	var bcs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.35
	cap.height = 1.7
	bcs.shape = cap
	body.add_child(bcs)
	body.add_to_group("player")
	body.set_script(load("res://Generators/test_walk_body.gd"))
	body.move_dir = Vector2(0, 0)
	body.position = Vector3(0, 2.5, 0)
	root.add_child(body)
	await create_timer(1.5).timeout
	# Опора болванки: компонент ЛЕГИТИМНО штампует промин стоя под ней
	# (синк коллизии) — высота опоры уходит вниз до dent_scale. Парение =
	# выше базового плато, провал = ниже капа промина.
	var feet: float = body.position.y - 0.85
	print("[SGF] болванка: pos.y=%.3f (опора %.3f) on_floor=%s vel=%.2f" % [
		body.position.y, feet, body.is_on_floor(),
		Vector2(body.velocity.x, body.velocity.z).length()])
	var chk_c: bool = body.is_on_floor() \
			and feet <= BASE_H + 0.02 and feet >= BASE_H - 0.07 - 0.02 \
			and Vector2(body.velocity.x, body.velocity.z).length() < 0.01

	# 4) Насыщенный промин: кап dent_scale (SSOT = компонент)
	sg._stamp(Vector2(0, 0), 5.0, 1.0)
	sg._stamp(Vector2(0.2, 0.1), 5.0, 1.0)
	var sat: int = sg.count_dented_pixels(0.99)
	var gap: float = sg.dent_scale * 1.0
	print("[SGF] dent_scale=%.3f насыщенных px=%d → макс визуальный промин %.3f м" % [sg.dent_scale, sat, gap])
	var chk_d: bool = sat > 0 and gap <= CAP_MAX

	# 5) СЕТКА по юбке и ЗА кромкой (баг 20.11.26 «висит в воздухе»: хулл был
	# вдвое шире меша — плато коллизии ±9 м при видимой дюне ±6 м, за кромкой
	# стояло невидимое плато 0.32 м). Рейкаст-грид: на видимой дюне hit.y =
	# высоте меша (±5 см), ЗА кромкой (r ≥ 1) коллизии выше пола быть не должно.
	var worst := 0.0
	var worst_at := ""
	var beyond_ok := true
	var beyond_at := ""
	for pt: Vector2 in [Vector2(4.5, 0), Vector2(4.875, 0), Vector2(5.25, 0),
			Vector2(5.625, 0), Vector2(6.0, 0), Vector2(5.0, 5.0),
			Vector2(-4.875, 0), Vector2(0, -5.625), Vector2(6.5, 0), Vector2(7.5, 0),
			Vector2(0, 6.5), Vector2(8.0, 8.0)]:
		var q2 := PhysicsRayQueryParameters3D.create(Vector3(pt.x, 5, pt.y), Vector3(pt.x, -1, pt.y))
		var h2 := space.intersect_ray(q2)
		var rr: float = maxf(absf(pt.x), absf(pt.y)) / 6.0
		if rr > 1.001:
			# За видимой кромкой: допустимо только попадание в пол (y=0).
			if h2 and h2.position.y > 0.02:
				beyond_ok = false
				beyond_at = "%.1f,%.1f y=%.3f" % [pt.x, pt.y, h2.position.y]
		elif not h2:
			beyond_ok = false
			beyond_at = "%.2f,%.2f нет коллизии" % [pt.x, pt.y]
		else:
			var dv: float = absf(h2.position.y \
					- BASE_H * smoothstep(1.0, 0.75, rr))
			if dv > worst:
				worst = dv
				worst_at = "%.2f,%.2f" % [pt.x, pt.y]
	var chk_e: bool = beyond_ok and worst <= 0.05
	print("[SGF] юбка: макс отклонение %.3f м (%s); за кромкой: %s" % [
		worst, worst_at, "OK" if beyond_ok else "FAIL " + beyond_at])

	# 6) Коллизия следует за промином (ядро фикса «висит над песком» 20.11.26):
	#    насыщенные стемпы секции 4 в центре обязаны просадить и heightmap —
	#    рейкаст в центр = BASE_H − dent_scale (±1 см), а не плоские 0.32.
	await physics_frame
	await physics_frame
	var q3 := PhysicsRayQueryParameters3D.create(Vector3(0, 5, 0), Vector3(0, -1, 0))
	q3.exclude = [body.get_rid()]  # болванка стоит в центре — не перехватывать
	var h3 := space.intersect_ray(q3)
	var chk_f: bool = false
	if h3:
		print("[SGF] ray центр после промина: y=%.3f (ожидание %.3f)" % [
			h3.position.y, BASE_H - sg.dent_scale])
		chk_f = absf(h3.position.y - (BASE_H - sg.dent_scale)) < 0.01
	else:
		printerr("[SGF] FAIL: рейкаст после промина не попал")

	if chk_a and chk_b and chk_c and chk_d and chk_e and chk_f:
		print("[SGF] GATE PASS")
		quit(0)
	else:
		printerr("[SGF] GATE FAIL: a=%s b=%s c=%s d=%s e=%s f=%s" % [
			chk_a, chk_b, chk_c, chk_d, chk_e, chk_f])
		quit(1)
