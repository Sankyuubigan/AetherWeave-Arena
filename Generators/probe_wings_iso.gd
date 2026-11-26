extends SceneTree
## ISO-проба геометрии крыла (Q20): три меша на одной камере со спины —
## A: v7-геометрия + v6-цвет (RGB, alpha=1 — как в компоненте), B: v7 +
## старый цвет (alpha-гейт), C: v7 без vertex color, D: v5-геометрия
## (контроль, рендерился в 02:15). Разделяет геометрию/цвет.

const WING_COLOR := Color(0.45, 0.55, 1.0)
const SEG := 14
const ROWS := 5

func _wing_v5(t: float, u: float) -> Vector3:
	var phi := lerpf(0.1, 0.85, t)
	var r := 2.05 * (0.12 + 0.88 * t)
	var lead := Vector3(cos(phi), sin(phi) * 0.85, -0.2 - 0.45 * sin(phi)) * r
	var cd := Vector3(0.0, -1.0, -0.35).normalized()
	var cl := (0.35 + 0.55 * t) * 0.95
	var pp := lead + cd * (cl * u)
	pp.y -= 0.14 * u * t
	return pp

func _wing_v7(t: float, u: float) -> Vector3:
	var lead := Vector3(0.25 + 1.85 * t, 0.30 * sin(t * 2.2) - 0.08 * t, -0.15 - 0.5 * t)
	var chord_dir := Vector3(0.0, -0.78, -0.63).normalized()
	var taper := clampf(1.0 - pow(maxf(0.0, (t - 0.65) / 0.35), 1.4), 0.12, 1.0)
	var chord_len := (0.4 + 0.75 * t) * taper
	var p := lead + chord_dir * (chord_len * u)
	p.y -= 0.18 * u * t
	return p

## Мутации v7 для поиска «убийцы рендера»: mode=1 без taper, mode=2 с
## v5-хордой, mode=3 без droop.
func _wing_v7m(t: float, u: float, mode: int) -> Vector3:
	var lead := Vector3(0.25 + 1.85 * t, 0.30 * sin(t * 2.2) - 0.08 * t, -0.15 - 0.5 * t)
	var chord_len: float
	var chord_dir: Vector3
	if mode == 2:
		chord_dir = Vector3(0.0, -1.0, -0.35).normalized()
		chord_len = 0.35 + 0.55 * t
	else:
		chord_dir = Vector3(0.0, -0.78, -0.63).normalized()
		chord_len = 0.4 + 0.75 * t if mode == 1 else (0.4 + 0.75 * t) * clampf(
			1.0 - pow(maxf(0.0, (t - 0.65) / 0.35), 1.4), 0.12, 1.0)
	var p := lead + chord_dir * (chord_len * u)
	if mode != 3:
		p.y -= 0.18 * u * t
	return p

func _build_wing(geo: int, col: int, mode: int = 0) -> MeshInstance3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	if col == 2:
		mat.albedo_color = Color(WING_COLOR.r * 1.5, WING_COLOR.g * 1.5, WING_COLOR.b * 1.5, 1.0)
	else:
		mat.vertex_color_use_as_albedo = true
		mat.albedo_color = Color(1, 1, 1, 1)
	mat.emission_enabled = true
	mat.emission = WING_COLOR
	mat.emission_energy_multiplier = 1.8
	mat.no_shadow = true
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for seg in SEG:
		var t0 := float(seg) / SEG
		var t1 := float(seg + 1) / SEG
		for row in ROWS - 1:
			var u0 := float(row) / (ROWS - 1)
			var u1 := float(row + 1) / (ROWS - 1)
			var quad: Array
			if mode == 9:
				quad = [_wing_v5(t0, u0), _wing_v5(t1, u0), _wing_v5(t1, u1), _wing_v5(t0, u1)]
				for k in quad.size():
					var q: Vector3 = quad[k]
					var cd7 := Vector3(0.0, -0.78, -0.63).normalized()
					# Мёртвая `tp` удалена (не читалась нигде) — в ней был
					# maxf() с 3 аргументами, скрипт не компилировался.
					# Найдено гейтом check_parse.gd 27.11.26.
					quad[k] = q
			elif geo == 5:
				quad = [_wing_v5(t0, u0), _wing_v5(t1, u0), _wing_v5(t1, u1), _wing_v5(t0, u1)]
			else:
				quad = [_wing_v7m(t0, u0, mode), _wing_v7m(t1, u0, mode),
					_wing_v7m(t1, u1, mode), _wing_v7m(t0, u1, mode)]
			for v in [quad[0], quad[1], quad[2], quad[0], quad[2], quad[3]]:
				var t: float = (v as Vector3).length() / 2.05
				if col == 1:
					var c2 := WING_COLOR * (1.0 + 0.6 * (1.0 - u0))
					c2.a = clampf(1.0 - 0.55 * t, 0.25, 1.0)
					st.set_color(c2)
				elif col == 0:
					var c := WING_COLOR * (2.4 - 0.7 * t - 0.35 * u0)
					c.a = 1.0
					st.set_color(c)
				st.add_vertex(v)
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	return mi

func _init() -> void:
	await process_frame
	await process_frame
	root.size = Vector2i(1280, 720)
	var floor_m := StandardMaterial3D.new()
	floor_m.albedo_color = Color(0.6, 0.6, 0.65)
	var fl := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(24, 24)
	fl.mesh = plane
	fl.material_override = floor_m
	root.add_child(fl)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(-0.9, 0.4, 0)
	root.add_child(sun)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.12, 0.14, 0.2)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.6, 0.6, 0.6)
	env.ambient_light_energy = 0.7
	var we := WorldEnvironment.new()
	we.environment = env
	root.add_child(we)
	var cam := Camera3D.new()
	cam.fov = 60
	root.add_child(cam)
	cam.global_transform = Transform3D(Basis(), Vector3(3.2, 2.6, -3.2))
	cam.look_at(Vector3(0, 1.4, 0))
	cam.current = true

	var holder := Node3D.new()
	holder.position = Vector3(0, 1.5, 0)
	root.add_child(holder)

	# РЕШАЮЩИЙ: (1) v5-lead+v7-хорда ЦЕНТР, (2) v5 полный правый-мир,
	# (3) v7 полный левый-мир, (4) v5 контроль x-1.4 (над полом).
	var b := _build_wing(5, 1, 9)  # mode=9: v5-lead + v7-хорда
	holder.add_child(b)
	var c := _build_wing(5, 1)
	c.position = Vector3(2.8, 0, 0)
	holder.add_child(c)
	var d := _build_wing(7, 1)
	d.position = Vector3(-2.8, 0, 0)
	holder.add_child(d)
	var e := _build_wing(5, 1)
	e.position = Vector3(-1.4, -0.4, 0)
	holder.add_child(e)

	await create_timer(0.5).timeout
	await process_frame
	root.get_texture().get_image().save_png("res://_tmp_probe/q_wings_iso.png")
	var arrays: Array = (b.mesh as ArrayMesh).surface_get_arrays(0)
	var vv: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	for i in mini(12, vv.size()):
		print("[ISO] v7 vert[", i, "]=", vv[i])
	for x in [[b, "B v5lead+v7chord"], [c, "C v5 full"], [d, "D v7 full"], [e, "E v5 ctrl"]]:
		print("[ISO] ", x[1], " aabb=", (x[0] as MeshInstance3D).get_aabb())
	quit(0)
