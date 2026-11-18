extends Node3D
## Труп-кукла на PhysicalBones3D (паттерн демо 3d/ragdoll_physics, Godot 4.8):
## PhysicalBone3D под PhysicalBoneSimulator3D, кости сразу уходят в физику —
## персонаж падает «мешком картошки». Импульс смертельного удара раскидывает
## тело пропорционально массам костей (целиком, без разрыва суставов), добивочный
## импульс + случайный торк в грудь дают кувырок. Чем больше урон — тем дальше
## отлетит (масштаб считает RagdollComponent).
## Слои: layer 0 / mask 1 — труп сталкивается только с миром: игрока и живых
## сущностей не толкает, трупы не пушат друг друга.

const IMPULSE_BONE := "PB_Chest"
const CHARGE_SHARE := 0.35  # доля импульса, добиваемая в грудь сверх залёта

## Задаётся спавнером ДО add_child (в _ready кости уже в физике).
@export var initial_impulse: Vector3 = Vector3.ZERO
## Сколько труп лежит до утопления; утопление — стандартный дешёвый уход.
@export var lifetime := 12.0
@export var sink_time := 1.5

func _ready() -> void:
	var sim := _find_simulator(self)
	if sim == null:
		queue_free()
		return
	sim.physical_bones_start_simulation()
	reset_physics_interpolation()
	if not initial_impulse.is_zero_approx():
		_launch_bones(sim)
	_schedule_cleanup()

## Залёт: каждому PB импульс, пропорциональный его массе (одинаковая скорость
## всего тела — суставы не рвутся), плюс добивочный импульс и торк в грудь.
func _launch_bones(sim: PhysicalBoneSimulator3D) -> void:
	var pbs: Array[PhysicalBone3D] = []
	var total := 0.0
	for c in sim.get_children():
		if c is PhysicalBone3D:
			pbs.append(c)
			total += c.mass
	if pbs.is_empty() or total <= 0.0:
		return
	var j := initial_impulse.length()
	var dir := initial_impulse / j
	for pb in pbs:
		pb.apply_central_impulse(dir * (j * pb.mass / total))
	var chest := sim.get_node_or_null(NodePath(IMPULSE_BONE)) as PhysicalBone3D
	if chest:
		chest.apply_central_impulse(initial_impulse * CHARGE_SHARE)
		# Torque API у PhysicalBone3D в 4.8 нет (ClassDB: apply_torque_impulse ->
		# false) — кувырок получаем импульсом с боковым смещением от центра масс.
		var off := Vector3(randf_range(0.08, 0.15), randf_range(-0.05, 0.05), randf_range(-0.05, 0.05))
		chest.apply_impulse(initial_impulse * (CHARGE_SHARE * 0.5), off)

## Перекраска куклы под цвет сущности (вызывает RagdollComponent после спавна).
func set_tint(color: Color) -> void:
	for mi in find_children("*", "MeshInstance3D", true, false):
		if mi.mesh == null or mi.mesh.surface_get_material(0) == null:
			continue
		var m := mi.mesh.surface_get_material(0).duplicate() as Material
		if m is BaseMaterial3D:
			(m as BaseMaterial3D).albedo_color = color
			mi.material_override = m

func _find_simulator(node: Node) -> PhysicalBoneSimulator3D:
	if node is PhysicalBoneSimulator3D:
		return node
	for c in node.get_children():
		var f := _find_simulator(c)
		if f:
			return f
	return null

func _schedule_cleanup() -> void:
	var tw := create_tween()
	tw.tween_interval(maxf(0.1, lifetime - sink_time))
	tw.tween_property(self, "position:y", position.y - 2.5, sink_time)
	tw.tween_callback(queue_free)
