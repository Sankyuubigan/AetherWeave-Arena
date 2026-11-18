extends SceneTree
## Зонд №2 фриза у валуна: спам декалей (DecalAtlas-чурн-гипотеза).
## A базлайн → B спам 2 декали/с lifetime 5с → C после смерти всех декалей.

const AnimatedDecal := preload("res://Graphics/AnimatedDecalComponent.gd")
const DecalFrames := preload("res://Graphics/DecalFrames.gd")

var _decals: Array = []

func _init() -> void:
	call_deferred("_run")

func _measure(tag: String) -> Dictionary:
	var frames := 0
	var t0u := Time.get_ticks_usec()
	var worst_ms := 0.0
	while frames < 120 and (Time.get_ticks_usec() - t0u) < 10.0 * 1000000.0:
		var f0 := Time.get_ticks_usec()
		await process_frame
		worst_ms = maxf(worst_ms, (Time.get_ticks_usec() - f0) / 1000.0)
		frames += 1
	var total_s := (Time.get_ticks_usec() - t0u) / 1000000.0
	var dc := RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)
	print("BFP2 %s: fps=%.1f worst=%.1fms DC=%d decals=%d" % [tag, frames / total_s, worst_ms, dc, _decals.size()])
	return {"fps": frames / total_s}

func _spawn_decal(pos: Vector3) -> void:
	var d := AnimatedDecal.new()
	var frames := DecalFrames.heal_pulse(Color(1.0, 0.85, 0.3))
	d.configure(frames, 10.0, 5.0, 1.2)
	root.add_child(d)
	d.place(pos, Vector3.UP)
	_decals.append(d)

func _run() -> void:
	var arena = load("res://Scenes/MainArena.tscn").instantiate()
	root.add_child(arena)
	for i in 30:
		await process_frame

	var boulder: Node3D = null
	var stack: Array = [root]
	while stack:
		var nd = stack.pop_front()
		if nd.name.begins_with("Boulder"):
			boulder = nd
		stack.append_array(nd.get_children())
	if boulder == null:
		print("BFP2 FAIL: boulder не найден")
		quit(1)
		return
	var bpos: Vector3 = boulder.global_position
	print("BFP2 валун в ", bpos)

	var ra := await _measure("A базлайн")
	for i in 10:
		await process_frame

	# Фаза B: 30 секунд спама — 2 декали/с у валуна, lifetime 5 с → постоянный чурн.
	var spawned := 0
	var t0 := Time.get_ticks_msec()
	while (Time.get_ticks_msec() - t0) < 30000:
		if spawned % 30 == 0:
			var ang := randf() * TAU
			_spawn_decal(bpos + Vector3(cos(ang) * 2.0, 0.05, sin(ang) * 2.0))
			spawned += 1
		await process_frame
	# Поддождать, пока последняя декаль доиграет и умрёт
	for i in 300:
		await process_frame

	var rb := await _measure("B спам-декалей")
	var rc := await _measure("C после-всех-смертей")
	print("BFP2 ИТОГ: базлайн %.1f → спам %.1f → после %.1f fps" % [ra.fps, rb.fps, rc.fps])
	quit(0)
