extends SceneTree
## Гейты IK-доводки кастов (план «18.11.26 Рэгдолл и ИИ-мобы Ада.md», D):
##  D0) CastIK создан SpellCaster'ом: цели прицела Right/Left на скелете игрока
##  D1) кисть с IK тянется к точке прицела — заметно ближе, чем в позе клипа
##  D2) после снятия IK кисть возвращается под контроль анимации
## Ожидания — create_timer: physics_frame в режиме -s НЕ эмитится (см. test_hell_ai).

var _fails := 0

func _init() -> void:
	_run()

func _run() -> void:
	var world := Node3D.new()
	root.add_child(world)

	var floor_body := StaticBody3D.new()
	world.add_child(floor_body)
	var fcs := CollisionShape3D.new()
	var fsh := BoxShape3D.new()
	fsh.size = Vector3(30, 1, 30)
	fcs.shape = fsh
	fcs.transform = Transform3D(Basis.IDENTITY, Vector3(0, -0.5, 0))
	floor_body.add_child(fcs)

	var player: CharacterBody3D = load("res://Scenes/player.tscn").instantiate()
	player.position = Vector3(0, 1.0, 0)
	world.add_child(player)

	await wait(0.4)

	var caster: Node = null
	for c in player.get_children():
		if c.get_script() == load("res://Logic/SpellCasterComponent.gd"):
			caster = c
	check("D0 SpellCasterComponent найден", caster != null)
	if caster == null:
		return _finish()

	var ik: Node = caster.get_node_or_null("CastIK")
	check("D0 CastIK создан", ik != null)
	var skel: Skeleton3D = _find_skeleton(player.get_node_or_null("GraphicsWrapper/PlayerModel"))
	check("D0 скелет найден", skel != null)
	if ik == null or skel == null:
		return _finish()

	var ik_count := 0
	for c in skel.get_children():
		if c.name.begins_with("CastIKTarget_"):
			ik_count += 1
	check("D0 цели прицела CastIK ×2 на скелете (%d)" % ik_count, ik_count == 2)

	var hand_i := skel.find_bone("mixamorig_RightHand")
	check("D0 кость RightHand есть", hand_i >= 0)
	if hand_i < 0:
		return _finish()

	# ── D1: с IK кисть тянется к точке прицела (впереди-справа от игрока) ──
	var aim: Vector3 = player.global_position + Vector3(0.3, 1.3, -1.0)
	skel.force_update_all_bone_transforms()  # headless: скелет без draw-прохода
	var d0 := _hand_dist(skel, hand_i, aim)
	ik.begin("Right", func() -> Vector3: return aim, 5.0)
	await wait(0.7)
	skel.force_update_all_bone_transforms()
	var d1 := _hand_dist(skel, hand_i, aim)
	check("D1 кисть с IK ближе к цели: %.2f → %.2f м" % [d0, d1],
			d1 < d0 * 0.7 and d1 < d0 - 0.15)

	# ── D2: сняли IK — кисть вернулась в позу клипа ──
	ik.end_now()
	await wait(0.5)
	skel.force_update_all_bone_transforms()
	var d2 := _hand_dist(skel, hand_i, aim)
	check("D2 после снятия кисть вернулась в клип: %.2f м" % d2, d2 > d1 + 0.1)

	_finish()

func _hand_dist(skel: Skeleton3D, bone_i: int, point: Vector3) -> float:
	var hp: Vector3 = (skel.global_transform * skel.get_bone_global_pose(bone_i)).origin
	return hp.distance_to(point)

func _find_skeleton(node: Node) -> Skeleton3D:
	if not node:
		return null
	if node is Skeleton3D:
		return node
	for c in node.get_children():
		var r := _find_skeleton(c)
		if r:
			return r
	return null

func check(name: String, ok: bool) -> void:
	if ok:
		print("CAST-IK: PASS — " + name)
	else:
		_fails += 1
		print("CAST-IK: FAIL — " + name)

func _finish() -> void:
	if _fails == 0:
		print("CAST-IK ALL PASS")
		quit(0)
	else:
		print("CAST-IK FAILED: %d" % _fails)
		quit(1)

func wait(sec: float) -> void:
	await create_timer(sec).timeout
