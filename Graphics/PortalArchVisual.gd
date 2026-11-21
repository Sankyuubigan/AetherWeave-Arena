class_name PortalArchVisual
extends Node3D
## Q47 (21.11.26): самодостаточный визуал нейро-портала «каменная арка + магическая мембрана».
## SSOT сборки портального визуала: билдер и NPCTeleporter только инстанцируют и задают экспорты.
## Урок проп-пайплайна: origin trellis-префаба НЕ в подошве — мембрана/свет ставятся
## по объединённому AABB префаба. Маска шейдера обязана совпадать с формой проёма.

const SHADER := preload("res://Graphics/portal_membrane.gdshader")

## Форма проёма: 0 = круг (кольцо B), 1 = стрельчатая готика (арка A)
@export_enum("Circle", "Gothic") var mask_type: int = 1

@export var arch_prefab: PackedScene
@export var arch_scale := 3.2

## Центр и размер мембраны как доли AABB префаба (адаптивно к выходу trellis)
@export var membrane_center_frac := Vector2(0.5, 0.42)
@export var membrane_size_frac := Vector2(0.70, 0.80)
## Глубина мембраны внутри проёма (доля глубины AABB)
@export var membrane_z_frac := 0.5

@export var color_a := Color(0.32, 0.14, 1.0)
@export var color_b := Color(0.05, 0.55, 1.0)
@export var color_core := Color(0.85, 0.92, 1.0)
@export var intensity := 1.3
@export var speed := 1.0
@export var seed_off := 0.0

@export var spark_count := 24
@export var light_energy := 1.6

## Путь к эмбиент-звуку (.res); пусто = без звука. Loop включается автоматически.
@export var ambient_path := ""

var _mat: ShaderMaterial
var _sparks: GPUParticles3D
var _light: OmniLight3D

func _ready() -> void:
	_build()

func _build() -> void:
	if arch_prefab == null:
		push_error("PortalArchVisual: arch_prefab не задан")
		return
	var holder := Node3D.new()
	holder.name = "ArchHolder"
	holder.scale = Vector3.ONE * arch_scale
	add_child(holder)
	var arch: Node = arch_prefab.instantiate()
	holder.add_child(arch)
	var aabb := _merged_aabb(arch)
	# Q47-F (гоу юзера 21.11.26): контракт подошвы — низ AABB префаба = y=0
	# enforced в build_env_prop.gd (единственная точка сборки), поэтому holder
	# НЕ сдвигаем: проп ставится в точку пола как есть. Урок «провалились в
	# пол» (21.11.26) закрыт на уровне данных, костыль-лифт удалён.
	var w := aabb.size.x * membrane_size_frac.x
	var h := aabb.size.y * membrane_size_frac.y
	var center := Vector3(
		aabb.position.x + aabb.size.x * membrane_center_frac.x,
		aabb.position.y + aabb.size.y * membrane_center_frac.y,
		aabb.position.z + aabb.size.z * membrane_z_frac
	)
	_add_membrane(holder, center, w, h)
	_add_sparks(holder, center, w, h)
	_light = OmniLight3D.new()
	_light.light_color = color_b.lerp(Color(1, 1, 1), 0.25)
	_light.light_energy = light_energy
	_light.omni_range = arch_scale * 2.8
	_light.position = center * arch_scale
	add_child(_light)
	if ambient_path != "" and ResourceLoader.exists(ambient_path):
		_add_ambient(center * arch_scale)
	_apply_low_quality()

func _add_membrane(holder: Node3D, center: Vector3, w: float, h: float) -> void:
	var quad := QuadMesh.new()
	quad.size = Vector2(w, h)
	_mat = ShaderMaterial.new()
	_mat.shader = SHADER
	_mat.set_shader_parameter("mask_type", mask_type)
	_mat.set_shader_parameter("color_a", color_a)
	_mat.set_shader_parameter("color_b", color_b)
	_mat.set_shader_parameter("color_core", color_core)
	_mat.set_shader_parameter("intensity", intensity)
	_mat.set_shader_parameter("speed", speed)
	_mat.set_shader_parameter("seed_off", seed_off)
	quad.material = _mat
	var mi := MeshInstance3D.new()
	mi.name = "Membrane"
	mi.mesh = quad
	mi.position = center
	holder.add_child(mi)

func _add_sparks(holder: Node3D, center: Vector3, w: float, h: float) -> void:
	_sparks = GPUParticles3D.new()
	_sparks.name = "Sparks"
	_sparks.amount = spark_count
	_sparks.lifetime = 3.5
	_sparks.local_coords = true
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(w * 0.45, h * 0.45, 0.04)
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 80.0
	pm.gravity = Vector3(0, 0.08, 0)
	pm.initial_velocity_min = 0.02
	pm.initial_velocity_max = 0.07
	pm.scale_min = 0.6
	pm.scale_max = 1.5
	pm.color = Color(0.75, 0.85, 1.0)
	_sparks.process_material = pm
	var spark_mesh := QuadMesh.new()
	spark_mesh.size = Vector2(0.045, 0.045)
	var smat := StandardMaterial3D.new()
	smat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	smat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	smat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	smat.albedo_color = Color(0.75, 0.85, 1.0)
	smat.disable_receive_shadows = true
	spark_mesh.material = smat
	_sparks.draw_pass_1 = spark_mesh
	_sparks.position = center
	holder.add_child(_sparks)

func _add_ambient(pos: Vector3) -> void:
	var asp := AudioStreamPlayer3D.new()
	asp.name = "Ambient"
	var stream: AudioStream = load(ambient_path)
	_enable_loop(stream)
	asp.stream = stream
	asp.unit_size = 10.0
	asp.max_distance = 40.0
	asp.volume_db = -6.0
	asp.autoplay = true
	asp.position = pos
	add_child(asp)

## Нейро-SFX идёт одним куском — эмбиенту нужен бесконечный loop по всему файлу.
func _enable_loop(stream: AudioStream) -> void:
	var wav := stream as AudioStreamWAV
	if wav == null or wav.loop_mode != AudioStreamWAV.LOOP_DISABLED:
		return
	var bytes_per_frame := 2 if wav.format == AudioStreamWAV.FORMAT_16_BITS else 1
	if wav.stereo:
		bytes_per_frame *= 2
	wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
	wav.loop_begin = 0
	if bytes_per_frame > 0:
		wav.loop_end = int(wav.data.size() / bytes_per_frame)

## LOW-графика: непрозрачная мембрана, без искр, свет слабее (паттерн PortalRing.gd).
func _apply_low_quality() -> void:
	var gq = get_node_or_null("/root/GraphicsQuality")
	if gq == null or gq.quality != 0:
		return
	if _mat != null:
		_mat.set_shader_parameter("opaque_mode", 1.0)
	if _sparks != null:
		_sparks.visible = false
	if _light != null:
		_light.light_energy *= 0.5

func _merged_aabb(root_node: Node3D) -> AABB:
	var result := AABB()
	var first := true
	var stack: Array = [[root_node, Transform3D.IDENTITY]]
	while not stack.is_empty():
		var entry: Array = stack.pop_back()
		var nd: Node = entry[0]
		var xf: Transform3D = entry[1]
		var next_xf := xf
		if nd is Node3D:
			next_xf = xf * (nd as Node3D).transform
		if nd is VisualInstance3D:
			var ta: AABB = next_xf * (nd as VisualInstance3D).get_aabb()
			result = ta if first else result.merge(ta)
			first = false
		for c in nd.get_children():
			stack.append([c, next_xf])
	return result
