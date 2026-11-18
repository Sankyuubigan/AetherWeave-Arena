extends Node3D
## Энергетический клинок (Q19, «Материализация» — план спец-батча 19.11.26,
## одобрен юзером: «как в Elden Ring / Devil May Cry»). Кристалл-клинок
## на BoneAttachment3D mixamorig_RightHand: rim (Fresnel) + emission
## (StandardMaterial3D), появление — рост от рукояти 0.1 с + искры в ладони,
## авто-растворение через LIFETIME + рассыпание искрами. Взмах — slash-дуга
## VFX + конусный урон. Анимации играет SpawnBladeEffect, не каст-флоу:
## у скилла cast_anim="" и одно действие на кнопке — материализация/взмах.

const EffectDB = preload("res://Logic/Skills/Effect.gd")

const BLADE_COLOR := Color(0.35, 0.85, 1.0)  # аркан; под будущие варианты — огонь/лёд
const LIFETIME := 8.0
const SWING_RANGE := 2.6
const SWING_DAMAGE := 35
const SWING_HALF_ANGLE_DEG := 55.0
const SWING_VERTICAL := 2.2

var _attach: BoneAttachment3D
var _blade: Node3D          # рукоять+клинок, скейл при материализации (пивот = запястье)
var _light: OmniLight3D
var _idle_particles: GPUParticles3D
var _active := false
var _lifetime_left := 0.0

func _ready() -> void:
	# Скелет ищем от РОДИТЕЛЯ (игрока): компонент — ребёнок, как у
	# SpellCasterComponent._ready (путь от компонента не существует).
	var skel := EffectDB.find_skeleton(get_parent().get_node_or_null("GraphicsWrapper/PlayerModel"))
	if skel == null:
		return
	_attach = BoneAttachment3D.new()
	_attach.bone_name = "mixamorig_RightHand"
	skel.add_child(_attach)
	_blade = _build_blade()
	_attach.add_child(_blade)
	_blade.visible = false
	_light = OmniLight3D.new()
	_light.light_color = BLADE_COLOR
	_light.omni_range = 3.0
	_light.omni_attenuation = 1.5
	_attach.add_child(_light)
	_idle_particles = _make_sparks(false)
	_attach.add_child(_idle_particles)

func _process(delta: float) -> void:
	if not _active:
		return
	_lifetime_left -= delta
	if _lifetime_left <= 0.0:
		dissolve()

## Клинок активен (повторный каст скилла = взмах).
func is_active() -> bool:
	return _active

func materialize() -> void:
	if _blade == null:
		return
	if _active:
		_lifetime_left = LIFETIME  # перекаст продлевает время
		return
	_active = true
	_lifetime_left = LIFETIME
	_blade.visible = true
	_light.visible = true
	_idle_particles.emitting = true
	# Рост от рукояти 0.1 с (пивот скейла в запястье — origin _blade).
	_blade.scale = Vector3(0.06, 0.05, 0.06)
	var tw := create_tween()
	tw.tween_property(_blade, "scale", Vector3.ONE, 0.1) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_burst_sparks()

func dissolve() -> void:
	if not _active:
		return
	_active = false
	_burst_sparks()
	_light.visible = false
	_idle_particles.emitting = false
	var tw := create_tween()
	tw.tween_property(_blade, "scale", Vector3(0.06, 0.02, 0.06), 0.15) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tw.tween_callback(func() -> void: _blade.visible = false)

## Взмах: slash-дуга VFX + конусный урон (враги aim_targets перед игроком).
## Возвращает число поражённых (для теста).
func swing(context: Dictionary) -> int:
	if _blade == null or not _active:
		return 0
	var fwd: Vector3 = context.get("forward_dir", -global_transform.basis.z)
	fwd.y = 0.0
	fwd = fwd.normalized() if fwd.length_squared() > 0.001 else Vector3.FORWARD
	_spawn_arc(fwd)
	var hits := 0
	var self_body := get_parent() as CollisionObject3D
	var cos_half := cos(deg_to_rad(SWING_HALF_ANGLE_DEG))
	var origin := global_position + Vector3(0, 1.2, 0)
	for node in get_tree().get_nodes_in_group("aim_targets"):
		if node == self_body or not is_instance_valid(node):
			continue
		if node.get("is_dead"):
			continue
		var target := node as Node3D
		if target == null:
			continue
		# Враг = не дружественный хиловый (та же логика, что у AimAssist).
		if "is_friendly" in node and node.is_friendly:
			continue
		if not node.has_method("take_damage"):
			continue
		var to := target.global_position + Vector3(0, 1.0, 0) - origin
		if absf(to.y) > SWING_VERTICAL:
			continue
		var flat := Vector3(to.x, 0.0, to.z)
		if flat.length() > SWING_RANGE:
			continue
		if flat.normalized().dot(fwd) < cos_half:
			continue
		node.take_damage(SWING_DAMAGE, flat.normalized())
		hits += 1
	return hits

func _build_blade() -> Node3D:
	var root := Node3D.new()
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.04, 0.07, 0.12)
	mat.emission_enabled = true
	mat.emission = BLADE_COLOR
	mat.emission_energy_multiplier = 2.4
	mat.roughness = 0.25
	mat.metallic = 0.0
	mat.rim_enabled = true          # Fresnel-кромка (план Q19)
	mat.rim = 1.0
	mat.rim_tint = 0.3

	var handle := MeshInstance3D.new()
	var hm := CylinderMesh.new()
	hm.top_radius = 0.022
	hm.bottom_radius = 0.028
	hm.height = 0.18
	hm.material = mat
	handle.mesh = hm
	handle.position = Vector3(0, 0.1, 0)
	root.add_child(handle)

	var guard := MeshInstance3D.new()
	var gm := BoxMesh.new()
	gm.size = Vector3(0.1, 0.02, 0.024)
	gm.material = mat
	guard.mesh = gm
	guard.position = Vector3(0, 0.19, 0)
	root.add_child(guard)

	var crystal := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.0     # остриё — кристалл-конус (энергетический вид)
	cm.bottom_radius = 0.032
	cm.height = 1.0
	cm.radial_segments = 6
	cm.material = mat
	crystal.mesh = cm
	crystal.position = Vector3(0, 0.69, 0)
	root.add_child(crystal)
	return root

## Slash-дуга: веер из квадов перед игроком, эмиссия, фейд 0.25 с.
## В мировом пространстве (current_scene) — компонент крутится с игроком,
## а дуга должна оставаться в плоскости взмаха.
func _spawn_arc(fwd: Vector3) -> void:
	var scene := get_tree().current_scene as Node3D
	if scene == null:
		return
	var arc := MeshInstance3D.new()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var r0 := 0.55
	var r1 := 1.9
	var segments := 8
	var half := deg_to_rad(SWING_HALF_ANGLE_DEG)
	var up := Vector3.UP
	var right := up.cross(fwd).normalized()
	var base_fwd := fwd
	for i in segments:
		var a0 := -half + (2.0 * half) * float(i) / float(segments)
		var a1 := -half + (2.0 * half) * float(i + 1) / float(segments)
		var d0 := (base_fwd + right * tan(a0)).normalized()
		var d1 := (base_fwd + right * tan(a1)).normalized()
		var p0 := d0 * r0
		var p1 := d0 * r1
		var p2 := d1 * r1
		var p3 := d1 * r0
		for p in [p0, p1, p2, p0, p2, p3]:
			st.set_normal(up)
			st.add_vertex(p)
	var am := StandardMaterial3D.new()
	am.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	am.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	am.albedo_color = Color(BLADE_COLOR, 0.75)
	am.emission_enabled = true
	am.emission = BLADE_COLOR
	am.emission_energy_multiplier = 1.6
	am.disable_receive_shadows = true
	arc.mesh = st.commit()
	arc.material_override = am
	arc.global_transform = Transform3D(Basis(), global_position + Vector3(0, 1.25, 0))
	arc.basis = Basis(Vector3.UP, atan2(fwd.x, fwd.z)) * arc.basis
	scene.add_child(arc)
	var tw := arc.create_tween()
	tw.set_parallel(true)
	tw.tween_property(am, "albedo_color:a", 0.0, 0.25)
	tw.tween_property(arc, "scale", Vector3(1.25, 1.0, 1.25), 0.25)
	tw.chain().tween_callback(arc.queue_free)

## Разовые искры (материализация/растворение) и мягкий фейд при жизни.
func _make_sparks(idle: bool) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = 10 if idle else 26
	p.lifetime = 0.5
	p.one_shot = not idle
	p.emitting = false
	p.explosiveness = 0.9 if not idle else 0.0
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 80.0
	pm.initial_velocity_min = 0.6
	pm.initial_velocity_max = 1.8
	pm.gravity = Vector3(0, 0.6, 0)
	pm.scale_min = 0.5
	pm.scale_max = 1.4
	pm.color = BLADE_COLOR
	p.process_material = pm
	var quad := QuadMesh.new()
	quad.size = Vector2(0.045, 0.045)
	var qm := StandardMaterial3D.new()
	qm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	qm.emission_enabled = true
	qm.emission = BLADE_COLOR
	qm.emission_energy_multiplier = 2.0
	qm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	quad.material = qm
	p.draw_pass_1 = quad
	p.position = Vector3(0, 0.45, 0)
	return p

func _burst_sparks() -> void:
	var burst := _make_sparks(false)
	_attach.add_child(burst)
	burst.emitting = true
	get_tree().create_timer(0.7).timeout.connect(burst.queue_free)
