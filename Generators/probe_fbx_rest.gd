extends SceneTree
## Диагностика (26.11.26): совпадает ли rest-ориентация таза в Mixamo-FBX и в
## скине игрока. Гипотеза: Wings_Fly даёт twist 105° (гейт probe_cast_facing)
## потому, что rest таза в этом FBX повёрнут относительно rest скина — тогда
## локальные ротации из FBX садятся «повёрнутым» телом (все прочие клипы — 0–4°).
## Контроль: Standing_1H_Magic_Attack_01.fbx (Cast_1H_Magic_01, twist ≈ 0).
## Запуск: --headless -s res://Generators/probe_fbx_rest.gd

const PLAYER_SCENE := "res://Scenes/player.tscn"
const FILES := [
	"res://Graphics/Animations/raw/mixamo/Flying.fbx",
	"res://Graphics/Animations/raw/mixamo/Standing_1H_Magic_Attack_01.fbx",
	"res://Graphics/Animations/raw/mixamo/Spell_Cast.fbx",
]
const HIPS := "mixamorig_Hips"

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var skin := await _skin_hips_rest()
	print("СКИН rest таза: euler(YXZ)=%s" % _fmt(skin))
	for f in FILES:
		var fbx := _fbx_hips_rest(f)
		if fbx.is_empty():
			print("%s — не загрузился" % f.get_file())
			continue
		print("%s: euler(YXZ)=%s" % [f.get_file(), _fmt(fbx)])
		# Дельта: сколько нужно домножить, чтобы локальная ротация FBX легла на скин
		var q_skin: Quaternion = skin["q"]
		var q_fbx: Quaternion = fbx["q"]
		var d := (q_skin * q_fbx.inverse()).normalized()
		if d.w < 0.0:
			d = -d
		var e := Basis(d).get_euler()
		print("   дельта skin·fbx⁻¹: yaw=%.1f° pitch=%.1f° roll=%.1f° | общий угол=%.1f°" % [
			rad_to_deg(e.y), rad_to_deg(e.x), rad_to_deg(e.z),
			rad_to_deg(absf(2.0 * acos(clampf(d.w, -1.0, 1.0))))])
		if fbx.has("bones"):
			print("   костей в FBX-скелете: %d, таз найден: %s" % [fbx["bones"], fbx["found"]])
	quit(0)

func _fmt(d: Dictionary) -> String:
	var e: Vector3 = Basis(d["q"]).get_euler()
	return "yaw=%.1f° pitch=%.1f° roll=%.1f°" % [rad_to_deg(e.y), rad_to_deg(e.x), rad_to_deg(e.z)]

func _skin_hips_rest() -> Dictionary:
	var player: Node = load(PLAYER_SCENE).instantiate()
	_strip_scripts(player)
	root.add_child(player)
	await process_frame
	var skel := _find_skel(player)
	if skel == null:
		return {"q": Quaternion.IDENTITY}
	var i := skel.find_bone(HIPS)
	return {"q": skel.get_bone_rest(i).basis.get_rotation_quaternion()}

func _fbx_hips_rest(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var doc := FBXDocument.new()
	var state := FBXState.new()
	state.base_path = ProjectSettings.globalize_path(path.get_base_dir())
	if doc.append_from_file(path, state) != OK:
		return {}
	var scene := doc.generate_scene(state)
	if scene == null:
		return {}
	var skel := _find_skel(scene)
	var out := {}
	if skel != null:
		var i := skel.find_bone(HIPS)
		out = {"q": skel.get_bone_rest(i).basis.get_rotation_quaternion(),
			"bones": skel.get_bone_count(), "found": i >= 0}
	scene.free()
	return out

func _find_skel(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node
	for c in node.get_children():
		var r := _find_skel(c)
		if r != null:
			return r
	return null

func _strip_scripts(n: Node) -> void:
	if n.get_script() != null:
		n.set_script(null)
	for c in n.get_children():
		_strip_scripts(c)
