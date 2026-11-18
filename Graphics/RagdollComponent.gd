extends Node
## Рэгдолл-смерть через PhysicalBones3D (заказ юзера 18.11.26: «отключаем
## анимации вообще, включаем физику костей, персонаж падает как мешок картошки,
## реалистично отлетая от удара»; чем больше смертельный урон — тем сильнее
## кинетический удар). Компонент — ребёнок сущности, вешается генератором сцены.
##
## Два пути activate():
##  1. У сущности есть Skeleton3D + PhysicalBoneSimulator3D с костями — оживляем
##     их (глушим AnimationPlayer/AnimationTree, стартуем симуляцию, импульс).
##  2. Капсульный манекен (скелета нет) — спавним куклу-труп ragdoll_dummy.tscn
##     в current_scene (не ребёнком сущности: MovingDummy движется, труп остаётся).

const IMPULSE_BASE := 15.0        # Н·с — база кинетического удара
const IMPULSE_PER_DAMAGE := 0.4   # Н·с за единицу урона (∝ смертельный урон)
# (рендер-проба 19.11.26: 40+3×дамаг при массе костей ~2.5 кг = 75 м/с —
# труп улетал на 7+ м от места смерти, «исчезал»; 15+0.4x = дуга 2–4 м)
const IMPULSE_CAP := 60.0         # потолок урона в формуле (гигантский AoE не улетает на Луну)
const UP_BIAS := 0.45             # подъёмная доля импульса — дуга, не в пол

@export var doll_scene: PackedScene = preload("res://Scenes/ragdoll_dummy.tscn")
## Цвет куклы-трупа = цвет сущности (у манекенов красный, у ада — body_color).
@export var tint := Color(1.0, 0.0, 0.0)

## amount — смертельный урон, hit_dir — направление удара (снаряда/взрыва/удара).
func activate(amount: int, hit_dir: Vector3) -> void:
	var body := get_parent() as Node3D
	if body == null:
		return
	var sim := _find_simulator(body)
	# Пустой симулятор (без PhysicalBone3D) — путь в никуда: визуал скрыт, а
	# кукла не спавнится, сущность «просто исчезает» (фидбэк юзера 19.11.26).
	if sim != null and _sim_has_bones(sim):
		_activate_physical_bones(body, sim, amount, hit_dir)
	else:
		_spawn_doll(body, amount, hit_dir)

## Модуль импульса от смертельного урона: больше урон — сильнее отброс.
func impulse_magnitude(amount: int) -> float:
	return IMPULSE_BASE + clampf(float(amount), 1.0, IMPULSE_CAP) * IMPULSE_PER_DAMAGE

## Вектор залёта: направление удара с подъёмной долей (кукла летит по дуге).
func launch_impulse(amount: int, hit_dir: Vector3) -> Vector3:
	var dir := hit_dir
	if dir.length_squared() < 0.001:
		dir = Vector3.UP
	var lifted := Vector3(dir.x, absf(dir.y) * 0.5 + UP_BIAS, dir.z)
	return lifted.normalized() * impulse_magnitude(amount)

## Только симулятор с реальными PhysicalBone3D-детьми годится для скелетного
## пути (см. activate — пустой симулятор съедал смерть).
func _sim_has_bones(sim: PhysicalBoneSimulator3D) -> bool:
	for c in sim.get_children():
		if c is PhysicalBone3D:
			return true
	return false

## Скелетный путь (будущие мобы со скинами): анимации выкл, физика костей вкл.
func _activate_physical_bones(body: Node3D, sim: PhysicalBoneSimulator3D, amount: int, hit_dir: Vector3) -> void:
	for ap in body.find_children("*", "AnimationPlayer", true, false):
		ap.stop()
	for at in body.find_children("*", "AnimationTree", true, false):
		at.active = false
	sim.physical_bones_start_simulation()
	sim.reset_physics_interpolation()
	var imp := launch_impulse(amount, hit_dir)
	for c in sim.get_children():
		if c is PhysicalBone3D:
			(c as PhysicalBone3D).apply_central_impulse(imp)

## Путь манекенов: кукла-труп в current_scene на месте смерти.
func _spawn_doll(body: Node3D, amount: int, hit_dir: Vector3) -> void:
	var tree := get_tree()
	if doll_scene == null or tree == null or tree.current_scene == null:
		return
	var doll := doll_scene.instantiate()
	doll.set("initial_impulse", launch_impulse(amount, hit_dir))
	# ПОЗИЦИЯ ДО add_child (грабля как у SoftBody3D, фидбэк юзера 19.11.26
	# «трупы просто исчезают»): в _ready кости уходят в физику — динамические
	# PhysicalBone3D живут в глобальном пространстве и НЕ следуют за корнем
	# после старта симуляции. Спавн в origin + перенос «на место смерти»
	# после add_child оставлял кости лежать у (0,0,0) карты.
	var scene_root := tree.current_scene as Node3D
	if scene_root:
		doll.position = scene_root.global_transform.affine_inverse() \
				* _ground_position(body)
	tree.current_scene.add_child(doll)
	doll.reset_physics_interpolation()
	doll.set_tint(tint)

## Земля под сущностью: манекен = капсула, origin в центре → низ = origin − h/2
## (учитывая offset коллайдера: у адских ближников капсула поднята на 0.9).
func _ground_position(body: Node3D) -> Vector3:
	var cols := body.find_children("*", "CollisionShape3D", true, false)
	if not cols.is_empty():
		var cs := cols[0] as CollisionShape3D
		if cs.shape is CapsuleShape3D:
			var cap := cs.shape as CapsuleShape3D
			return body.global_position + Vector3(0.0, cs.position.y - cap.height * 0.5, 0.0)
	return body.global_position

func _find_simulator(node: Node) -> PhysicalBoneSimulator3D:
	if node is PhysicalBoneSimulator3D:
		return node
	for c in node.get_children():
		var f := _find_simulator(c)
		if f:
			return f
	return null
