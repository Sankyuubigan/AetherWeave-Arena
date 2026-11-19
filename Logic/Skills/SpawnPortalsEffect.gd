extends "res://Logic/Skills/Effect.gd"
## Порталы (Q21, заказ юзера 19.11.26: «после нажатия на скилл выбираем точку
## на карте где будет стоять второй портал на выход. а первый рядом с
## персонажем ставится всегда. и это будет типа туннель между ними проход»):
## первый портал — ВСЕГДА за спиной кастера, второй — точка прицела
## (context.target_pos, штатный рейкаст _aim_context). Повторный каст
## переносит пару (старая сносится). Точки ставятся на пол вниз-рейкастом
## (прицел мог уйти в стену/небо).

const PORTAL_SCRIPT := preload("res://Logic/PortalNode.gd")
const CAST_GESTURE := "Cast_Enter"
const BEHIND_DIST := 1.7
const GROUND_LIFT := 1.45   # центр кольца: радиус 1.15 + зазор + грань коллизии 0.25 над полом
const RING_R := 1.15        # внешний радиус кольца/мембраны (PortalNode.build)
const COLOR_IN := Color(0.4, 0.6, 1.0)
const COLOR_OUT := Color(1.0, 0.55, 0.25)

func apply(caster: Node, context: Dictionary) -> void:
	# Жест материализации (паттерн SpawnWingsEffect: cast_anim пуст —
	# жест играет эффект, IK-доводка руки не вешается).
	var anim_comp = caster.get_node_or_null("PlayerAnimationComponent")
	if anim_comp and anim_comp.has_method("play_cast_anim") \
			and anim_comp.has_method("has_cast_anim") \
			and anim_comp.has_cast_anim(CAST_GESTURE):
		anim_comp.play_cast_anim(CAST_GESTURE)

	var tree := caster.get_tree()
	var world: Node = tree.current_scene if tree else null
	if world == null:
		world = caster  # -s-тесты: current_scene null (грабля Q19)
	# Ссылка через meta (не по имени): add_child с дублирующим именем молча
	# даёт "...2", а queue_free старой пары срабатывает в конце кадра —
	# поиск по имени ловил умирающий узел (тест 19.11).
	var old = caster.get_meta("portal_pair", null)
	if old and is_instance_valid(old):
		old.queue_free()
	var pair := Node3D.new()
	pair.name = "PortalPair"
	world.add_child(pair)
	caster.set_meta("portal_pair", pair)

	var fwd := Vector3.FORWARD
	var gw := caster.get_node_or_null("GraphicsWrapper") as Node3D
	if gw:
		fwd = gw.global_basis.z.normalized()
		fwd.y = 0.0
		fwd = fwd.normalized() if fwd.length() > 0.01 else Vector3.FORWARD

	var p_a := _ground(caster, caster.global_position - fwd * BEHIND_DIST)
	var p_b := _ground(caster, context.get("target_pos",
			caster.global_position + fwd * 6.0))
	# Склон (вердикт юзера «порталы наполовину утопают в полу»): кольцо
	# ВЕРТИКАЛЬНО (нормаль = fwd), низ кромки 0.30 над полом под ЦЕНТРОМ —
	# но на поперечном склоне земля под краем кольца выше точки прицела →
	# край врезается в рельеф. Сэмплируем пол по оси ширины кольца и
	# поднимаем центр над самым высоким краем (на плоскости — без изменений).
	p_a = _slope_lift(caster, p_a, fwd)
	p_b = _slope_lift(caster, p_b, fwd)

	var a := _portal(pair, "PortalA", p_a + Vector3.UP * GROUND_LIFT, fwd,
			COLOR_IN, 0.0)
	var b := _portal(pair, "PortalB", p_b + Vector3.UP * GROUND_LIFT, fwd,
			COLOR_OUT, 3.1)
	a.partner = b
	b.partner = a

## Пол под точкой: прицел в небо/стену → портал на земле под ней.
func _ground(caster: Node, p: Vector3) -> Vector3:
	# caster: Node — get_world_3d()/get_rid() динамические (:= не выводит тип).
	var space = caster.get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(
		p + Vector3.UP * 3.0, p + Vector3.DOWN * 14.0)
	q.exclude = [caster.get_rid()]
	var r = space.intersect_ray(q)
	if r and r.has("position"):
		return r["position"]
	return p

## Земля под краями вертикального кольца выше, чем под центром (поперечный
## склон/бугор) → поднять центр на эту разницу. Ось ширины = UP×fwd; сэмплы
## по двум краям (для планарного склона достаточно крайних точек).
func _slope_lift(caster: Node, p: Vector3, fwd: Vector3) -> Vector3:
	var axis := Vector3.UP.cross(fwd).normalized()
	var h := p.y
	for s in [-1.0, 1.0]:
		var q: Vector3 = _ground(caster, p + axis * RING_R * s)
		h = maxf(h, q.y)
	return p + Vector3.UP * maxf(0.0, h - p.y)

func _portal(pair: Node3D, pname: String, pos: Vector3, normal: Vector3,
		col: Color, seed_off: float) -> Area3D:
	var p := Area3D.new()
	p.name = pname
	p.set_script(PORTAL_SCRIPT)
	pair.add_child(p)
	# Ориентация: локальный +Z наружу по нормали (выход по global_basis.z).
	var x := Vector3.UP.cross(normal).normalized()
	var y := normal.cross(x).normalized()
	p.global_transform = Transform3D(Basis(x, y, normal).orthonormalized(), pos)
	p.call("build", col, seed_off)
	return p
