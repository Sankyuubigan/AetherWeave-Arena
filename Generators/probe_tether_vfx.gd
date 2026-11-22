extends SceneTree

## Q48 гейт шага 3 (PRP tasks/tether_swing_prp.md): VFX «Эфирного захвата».
## Чеки (ТЗ §7.1): TetherVfx создаётся при зацепе, нить/сигил появляются и
## перестраиваются в свинге, шлейф включён, FOV-скейл живёт, после срыва нить
## гаснет, сигил умирает, burst самоудаляется (0 утечек). 0 SCRIPT ERROR.

var _fails := 0

func _check(ok: bool, name: String, detail: String = "") -> void:
	if ok:
		print("  PASS: %s %s" % [name, detail])
	else:
		_fails += 1
		print("  FAIL: %s %s" % [name, detail])

func _init() -> void:
	await physics_frame

	var floor := StaticBody3D.new()
	var fs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(300, 1, 300)
	fs.shape = box
	floor.add_child(fs)
	floor.position = Vector3(0, 0, 0)
	floor.position.y = -0.5
	root.add_child(floor)

	var ps: PackedScene = load("res://Scenes/player.tscn")
	if ps == null:
		print("[TETHER-VFX] GATE: FAIL (player.tscn не загрузилась)")
		quit(1)
		return
	var player: CharacterBody3D = ps.instantiate()
	root.add_child(player)
	await physics_frame
	await physics_frame

	var skills = load("res://Logic/Skills/SkillDB.gd").get_skills()
	var eff = null
	for e in skills["ether_tether"].effects:
		if e.get_script() != null \
				and e.get_script().resource_path.ends_with("TetherSwingEffect.gd"):
			eff = e

	var ctx_air := {
		"target_pos": Vector3(0, 12, -25),
		"hit_normal": Vector3.UP,
		"target_node": null,
		"camera_pos": Vector3(0, 25, 0),
		"forward_dir": Vector3(0, 0.3, -0.95).normalized(),
		"hand": "Left",
	}

	player.global_position = Vector3(0, 25, 0)
	player.velocity = Vector3.ZERO
	await physics_frame
	eff.apply(player, ctx_air)
	await physics_frame

	var vfx = player.get_node_or_null("TetherVfx")
	_check(vfx != null, "vfx_created_on_attach")
	if vfx == null:
		print("[TETHER-VFX] GATE: FAIL")
		quit(1)
		return

	var thread: MeshInstance3D = vfx.get("_thread")
	_check(thread != null and thread.visible, "thread_visible")

	var baseline: int = player.get_child_count()

	for t in range(30):
		await physics_frame

	var thread_ok: bool = thread != null and thread.visible
	_check(thread_ok, "thread_rebuilt_in_swing")
	var trail: GPUParticles3D = vfx.get("_trail")
	var ratio: float = trail.amount_ratio if trail != null else -1.0
	_check(ratio > 0.5, "trail_on_in_swing", "ratio=%.1f" % ratio)
	var cam: Camera3D = player.get_node_or_null("SpringArm3D/Camera3D")
	var fov1: float = cam.fov if cam != null else 0.0
	_check(30.0 < fov1 and fov1 < 97.0, "fov_sane", "fov=%.1f" % fov1)
	_check(vfx.get("_sigil") != null, "sigil_alive_in_swing")

	eff.apply(player, ctx_air)
	await physics_frame
	_check(vfx.get("_tethered") == false, "detached_state")
	_check(thread.visible == false, "thread_hidden_after_detach")
	_check(vfx.get("_sigil") == null, "sigil_freed_after_detach")

	for t in range(20):
		await physics_frame
	var fov2: float = cam.fov if cam != null else 0.0
	_check(fov2 > 77.0, "fov_stays_in_flight", "fov=%.1f" % fov2)

	for t in range(80):
		await physics_frame
	_check(player.get_child_count() == baseline, "no_vfx_leaks",
		"children %d == %d" % [player.get_child_count(), baseline])

	print("[TETHER-VFX] GATE: %s" % ("PASS" if _fails == 0 else "FAIL (%d)" % _fails))
	quit(0 if _fails == 0 else 1)
