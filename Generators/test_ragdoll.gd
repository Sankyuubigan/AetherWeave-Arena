extends SceneTree
## Тест рэгдолл-смерти (PRP «18.11.26 Рэгдолл и ИИ-мобы Ада», PhysicalBones3D).
## Запуск: engine --headless -s res://Generators/test_ragdoll.gd
## Гейты:
##   1) структура куклы: 13 костей/13 PhysicalBone3D, 12 ConeTwist-джойнтов;
##   2) кости в физике: грудь получает скорость залёта;
##   3) смерть манекена спавнит куклу-труп, меш скрывается;
##   4) масштаб импульса ∝ урону (формула BASE + урон*3);
##   5) кукла удаляется после lifetime (утоп);
##   6) dummy.tscn содержит Ragdoll-компонент.

const RagdollComponent = preload("res://Graphics/RagdollComponent.gd")
const DOLL_SCENE = "res://Scenes/ragdoll_dummy.tscn"

var _fail := false

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var scene := Node3D.new()
	scene.name = "TestScene"
	root.add_child(scene)
	current_scene = scene

	# ── Гейт 1: структура куклы ────────────────────────────────────────
	var doll_scene: PackedScene = load(DOLL_SCENE)
	_check(doll_scene != null, "гейт 1: ragdoll_dummy.tscn загружается")
	if doll_scene:
		var probe := doll_scene.instantiate()
		var skel := _find_skel(probe)
		_check(skel != null, "гейт 1: Skeleton3D в кукле")
		if skel:
			_check(skel.get_bone_count() == 13, "гейт 1: 13 костей, получено %d" % skel.get_bone_count())
		var sim := _find_sim(probe)
		_check(sim != null, "гейт 1: PhysicalBoneSimulator3D на месте")
		if sim:
			var pbs := sim.get_children().filter(func(c): return c is PhysicalBone3D)
			_check(pbs.size() == 13, "гейт 1: 13 PhysicalBone3D, получено %d" % pbs.size())
			var joints := pbs.filter(func(c): return (c as PhysicalBone3D).joint_type == 2)
			_check(joints.size() == 12, "гейт 1: 12 ConeTwist-джойнтов, получено %d" % joints.size())
		probe.free()

	# ── Гейт 4: масштаб импульса ∝ урону ──────────────────────────────
	var comp = RagdollComponent.new()
	_check(comp.impulse_magnitude(60) > comp.impulse_magnitude(10),
		"гейт 4: импульс(60) > импульс(10)")
	_check(is_equal_approx(comp.impulse_magnitude(10), 70.0),
		"гейт 4: формула 40 + урон*3, получено %.1f" % comp.impulse_magnitude(10))
	comp.free()

	# ── Гейт 6 + 3: dummy.tscn содержит компонент; смерть спавнит куклу ─
	var dummy_scene: PackedScene = load("res://Scenes/dummy.tscn")
	_check(dummy_scene != null, "гейт 6: dummy.tscn загружается")
	var dummy = dummy_scene.instantiate()
	scene.add_child(dummy)
	await process_frame
	var rag = dummy.get_node_or_null("Ragdoll")
	_check(rag != null, "гейт 6: в dummy.tscn есть Ragdoll-компонент")
	dummy.take_damage(200, Vector3(0, 0, -1))
	await process_frame
	_check(dummy.is_dead, "гейт 3: манекен мёртв")
	_check(not dummy.get_node("MeshInstance3D").visible, "гейт 3: меш манекена скрыт")
	var dolls := scene.find_children("*", "Node3D", true, false).filter(
		func(n): return String(n.name).begins_with("RagdollDummy"))
	_check(dolls.size() == 1, "гейт 3: кукла-труп спавнится в сцену (найдено %d)" % dolls.size())
	if dolls.size() == 1:
		var doll: Node3D = dolls[0]
		# ── Гейт 2: кости в физике — грудь получила залёт ──────────────
		var chest := doll.get_node_or_null("Skeleton3D/PhysicalBoneSimulator3D/PB_Chest") as PhysicalBone3D
		_check(chest != null, "гейт 2: PB_Chest найден")
		if chest:
			await create_timer(0.1).timeout
			_check(chest.linear_velocity.length() > 0.3,
				"гейт 2: кость движется в физике (v=%.2f м/с)" % chest.linear_velocity.length())
		doll.queue_free()
		await process_frame

	# ── Гейт 5: cleanup — отдельная кукла с коротким lifetime ─────────
	var corpse = doll_scene.instantiate()
	corpse.set("lifetime", 0.4)
	corpse.set("sink_time", 0.2)
	scene.add_child(corpse)
	await create_timer(0.8).timeout
	_check(not is_instance_valid(corpse), "гейт 5: кукла удалена после lifetime")

	if _fail:
		print("RAGDOLL: FAIL")
		quit(1)
	else:
		print("RAGDOLL: ALL PASS")
		quit(0)

func _check(cond: bool, what: String) -> void:
	if not cond:
		_fail = true
		print("RAGDOLL: FAIL — ", what)

func _find_skel(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node
	for c in node.get_children():
		var f := _find_skel(c)
		if f:
			return f
	return null

func _find_sim(node: Node) -> PhysicalBoneSimulator3D:
	if node is PhysicalBoneSimulator3D:
		return node
	for c in node.get_children():
		var f := _find_sim(c)
		if f:
			return f
	return null

func _make_dummy() -> StaticBody3D:
	var root := StaticBody3D.new()
	var mesh := MeshInstance3D.new()
	mesh.name = "MeshInstance3D"
	var cap := CapsuleMesh.new()
	cap.radius = 0.5
	cap.height = 2.0
	mesh.mesh = cap
	root.add_child(mesh)
	var col := CollisionShape3D.new()
	col.name = "CollisionShape3D"
	var shape := CapsuleShape3D.new()
	shape.radius = 0.5
	shape.height = 2.0
	col.shape = shape
	root.add_child(col)
	root.set_script(load("res://Logic/HealthComponent.gd"))
	var rag := Node.new()
	rag.name = "Ragdoll"
	rag.set_script(RagdollComponent)
	root.add_child(rag)
	return root
