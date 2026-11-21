extends SceneTree
## Q25-B «желе падает под землю сразу при спавне» (вердикт юзера 21.11.26):
## репро на ЖИВОЙ арене + изоляция базы. Режимы (--floor=..., после `--`):
##   arena — живая MainArena.tscn (желе уже в сцене, ищем по группе);
##   box   — только arena.tscn × scale(2,1,2) (пол-бокс 100×100, толщина 1 м);
##   boxb  — бокс пола + глубокая подложка (как генератор), БЕЗ дюны/манекенов;
##   mono4 — ОДИН бокс 100×4×100 (монолит, как у JELLY4), без сэндвича —
##           контроль гипотезы «сэндвич из двух боксов выдавливает вбок»;
##   hm    — только soft_ground.tscn (heightmap-дюна Q32) без пола.
## Гейт: тело исчезло, покой глубже −0.9 или продолжает тонуть (ползучесть)
## = FAIL. Оседание до ~−0.5 м с остановкой = одобренный покой JELLY4, PASS.
## Аргументы: --floor=arena|box|hm  --frames=N (дефолт 600)

const JellyScript = preload("res://Logic/JellyMonster.gd")

var _fails := 0

func _aabb(jelly: Node) -> Dictionary:
	var lo := Vector3(1e9, 1e9, 1e9)
	var hi := Vector3(-1e9, -1e9, -1e9)
	for i in jelly.get_point_count():
		var p: Vector3 = jelly.get_point_transform(i)
		lo = lo.min(p)
		hi = hi.max(p)
	return {"lo": lo, "hi": hi}

func _spawn_jelly(spawn: Vector3 = Vector3(7, 1.95, -6)) -> SoftBody3D:
	# Спавн-параметры живой арены: меш ДО add_child (грабля 4.8).
	if spawn_arg != Vector3.ZERO:
		spawn = spawn_arg
	var jelly = JellyScript.new()
	var mesh_amp := 0.04
	if jnoise_arg != 0.04:
		mesh_amp = jnoise_arg
	jelly.mesh = JellyScript.build_blob_mesh(2.6, mesh_amp)
	jelly.position = spawn
	root.add_child(jelly)
	# Оверрайды СТРОГО после add_child: _ready→_setup_physics перетирает
	# значения, заданные до входа в дерево (поймано: дефолты 1.35/18).
	if jp_arg > 0.0:
		jelly.pressure_coefficient = jp_arg
	if jpr_arg > 0:
		jelly.simulation_precision = jpr_arg
	if jm_arg > 0.0:
		jelly.total_mass = jm_arg
	if jd_arg >= 0.0:
		jelly.damping_coefficient = jd_arg
	if js_arg >= 0.0:
		jelly.linear_stiffness = js_arg
	if jdrag_arg >= 0.0:
		jelly.drag_coefficient = jdrag_arg
	if jmg_arg > 0.0:
		for pi in ClassDB.class_get_property_list("SoftBody3D"):
			if pi.name == "collision_margin":
				jelly.set("collision_margin", jmg_arg)
				break
	return jelly

var spawn_arg := Vector3.ZERO
var jp_arg := 0.0 # --jp=X: pressure_coefficient (0 = дефолт 1.35)
var jpr_arg := 0  # --jpr=Y: simulation_precision (0 = дефолт 18)
var jm_arg := 0.0 # --jm=X: total_mass (0 = дефолт 40)
var jmg_arg := 0.0 # --margin=X: collision_margin (0 = не трогать)
var jd_arg := -1.0 # --jd=X: damping_coefficient (−1 = дефолт 0.02)
var js_arg := -1.0 # --js=X: linear_stiffness (−1 = дефолт)
var jdrag_arg := -1.0 # --jdrag=X: drag_coefficient (−1 = дефолт)
var jfric_arg := -1.0 # --jfric=X: friction PhysicsMaterial НА ПОЛ (−1 = не ставить)
var jnoise_arg := 0.04 # --jnoise=X: амплитуда шума меша блоба (0.04 = одобренный вид)

func _init() -> void:
	_watchdog()
	var floor_kind := "arena"
	var frames := 600
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--floor="):
			floor_kind = a.get_slice("=", 1)
		elif a.begins_with("--frames="):
			frames = int(a.get_slice("=", 1))
		elif a.begins_with("--spawn="):
			var parts := (a.get_slice("=", 1) as String).split(",")
			spawn_arg = Vector3(float(parts[0]), float(parts[1]), float(parts[2]))
		elif a.begins_with("--jp="):
			jp_arg = float(a.get_slice("=", 1))
		elif a.begins_with("--jpr="):
			jpr_arg = int(a.get_slice("=", 1))
		elif a.begins_with("--jm="):
			jm_arg = float(a.get_slice("=", 1))
		elif a.begins_with("--js="):
			js_arg = float(a.get_slice("=", 1))
		elif a.begins_with("--jdrag="):
			jdrag_arg = float(a.get_slice("=", 1))
		elif a.begins_with("--jnoise="):
			jnoise_arg = float(a.get_slice("=", 1))
		elif a.begins_with("--jfric="):
			jfric_arg = float(a.get_slice("=", 1))
		elif a.begins_with("--jd="):
			jd_arg = float(a.get_slice("=", 1))
		elif a.begins_with("--margin="):
			jmg_arg = float(a.get_slice("=", 1))
	await physics_frame

	var jelly: SoftBody3D = null
	match floor_kind:
		"arena":
			var arena = (load("res://Scenes/MainArena.tscn") as PackedScene).instantiate()
			root.add_child(arena)
			await physics_frame
			# Гейт проверяет ПОКОЙ софтбоди — движковые манекены (DummyTriangle
			# 16 м/с ганяет желе под пол) в пробе только мешают; в живой сцене
			# всё остаётся.
			for pat in ["Dummy*", "FriendlyDummy*", "dummy*"]:
				for d in root.find_children(pat, "Node3D", true, false):
					d.queue_free()
			await physics_frame
			for j in root.find_children("*", "SoftBody3D", true, false):
				jelly = j
				break
		"box":
			var base = (load("res://Scenes/arena.tscn") as PackedScene).instantiate()
			base.scale = Vector3(2, 1, 2)
			root.add_child(base)
			jelly = _spawn_jelly()
		"boxb":
			# Диагностика фикс-пакета: бокс пола 1 м + глубокая подложка,
			# без дюны и манекенов, желе на НОВОМ спавне.
			var base = (load("res://Scenes/arena.tscn") as PackedScene).instantiate()
			base.scale = Vector3(2, 1, 2)
			root.add_child(base)
			var fb = StaticBody3D.new()
			var fcs = CollisionShape3D.new()
			var fbox = BoxShape3D.new()
			fbox.size = Vector3(100, 8, 100)
			fcs.shape = fbox
			fcs.position = Vector3(0, -4, 0)
			root.add_child(fb)
			fb.add_child(fcs)
			jelly = _spawn_jelly(Vector3(7, 1.95, 6))
		"mono4":
			# Контроль: единый монолит 100×4×100 (топ y=0) — ни сэндвича,
			# ни тонкого бокса. Если и тут ползёт — сэндвич не при чём.
			var mono := StaticBody3D.new()
			var mcs := CollisionShape3D.new()
			var mbox := BoxShape3D.new()
			mbox.size = Vector3(100, 4, 100)
			mcs.shape = mbox
			mcs.position = Vector3(0, -2, 0)
			root.add_child(mono)
			mono.add_child(mcs)
			if jfric_arg >= 0.0:
				var pm := PhysicsMaterial.new()
				pm.friction = jfric_arg
				pm.bounce = 0.0
				mono.physics_material_override = pm
			jelly = _spawn_jelly()
		"hm":
			var patch = (load("res://Graphics/Environment/Props/soft_ground/soft_ground.tscn") as PackedScene).instantiate()
			patch.position = Vector3(6, 0, -14)
			root.add_child(patch)
			jelly = _spawn_jelly()
		_:
			printerr("[JARENA] неизвестный --floor=%s" % floor_kind)
			quit(1)
			return
	if jelly == null:
		printerr("[JARENA] желе не найдено (floor=%s)" % floor_kind)
		quit(1)
		return
	var n_pts: int = jelly.get_point_count()
	print("[JARENA] floor=%s points=%d pressure=%.2f precision=%d mass=%.1f margin=%.2f"
			% [floor_kind, n_pts, jelly.pressure_coefficient,
			jelly.simulation_precision, jelly.total_mass,
			jelly.get("collision_margin") if jelly.get("collision_margin") != null else 0.0])

	var ys := PackedFloat32Array()
	var gone := false
	for f in frames:
		await physics_frame
		var bb := _aabb(jelly)
		ys.append(bb.lo.y)
		if bb.lo.y < -2.5 or is_nan(bb.lo.y):
			gone = true
			break
		if f % 30 == 0 or f == frames - 1:
			var lov: Vector3 = bb.lo
			var hiv: Vector3 = bb.hi
			var c := (lov + hiv) * 0.5
			var g_node := jelly.get_node_or_null("SinkGuard")
			var gpos: Vector3 = g_node.global_position if g_node != null else Vector3(1e9, 1e9, 1e9)
			print("[JARENA] t=%4.1fс lo=(%.2f, %.2f, %.2f) hi.y=%.2f центр=(%.1f, %.1f) guard=(%.2f, %.2f, %.2f)"
					% [f / 60.0, bb.lo.x, bb.lo.y, bb.lo.z, bb.hi.y, c.x, c.z,
					gpos.x, gpos.y, gpos.z])
	if gone:
		_fails += 1
		printerr("[JARENA] ПРОВАЛ: тело ушло под базу/исчезло (t=%.1fс)"
				% [frames / 60.0])
	else:
		# Покой = средний lo.y последних 90 кадров; ползучесть = сравнение
		# с окном 150–240 (оседание 2.5–4.0 с должно быть уже завершено).
		var tail := _mean(ys, ys.size() - 90, ys.size())
		var early := _mean(ys, mini(150, ys.size() - 1), mini(240, ys.size()))
		print("[JARENA] покой: tail=%.2f early=%.2f" % [tail, early])
		if tail < -0.9:
			_fails += 1
			printerr("[JARENA] ПРОТЕКАНИЕ: покой min-y %.2f глубже −0.9" % tail)
		elif tail - early < -0.12:
			_fails += 1
			printerr("[JARENA] ПОЛЗУЧЕСТЬ: продолжает тонуть (%.2f → %.2f)"
					% [early, tail])
		else:
			print("[JARENA] покой стабилен (промин ~%.2f м — вид JELLY4)"
					% tail)
	print("JARENA GATE (%s): %s" % [floor_kind, "FAIL" if _fails > 0 else "PASS"])
	quit(0 if _fails == 0 else 1)

func _mean(ys: PackedFloat32Array, a: int, b: int) -> float:
	if ys.size() == 0:
		return 0.0
	var lo := maxi(0, a)
	var hi := mini(ys.size(), b)
	if hi <= lo:
		return ys[lo]
	var s := 0.0
	for i in range(lo, hi):
		s += ys[i]
	return s / float(hi - lo)

func _watchdog() -> void:
	await create_timer(120.0).timeout
	printerr("[WDT] TIMEOUT 120с — проба зависла")
	quit(1)
