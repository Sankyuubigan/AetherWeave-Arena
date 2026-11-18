extends Node
## AIM ASSIST (QUEUE Q29): «увеличенный хитбокс наведения» — скан группы
## aim_targets с угловой толерантностью от центра прицела; лучшая по углу
## цель помечается маркером (кольцо + клавиша). requires_target-скиллы
## кастуют В ПОМЕЧЕННУЮ цель (assist-first в SpellCasterComponent).
## Лего: любой скилл с requires_target + target_type ("friendly"/"enemy").
## Толерантность — F2-ползунок SettingsMenu.aim_assist_deg (персист [input]
## settings.cfg), фолбэк 4.0° для -s-проб без автолоада.

const AimMarkerScript := preload("res://Graphics/AimMarker.gd")
const SkillDB := preload("res://Logic/Skills/SkillDB.gd")

const MARKER_TYPES := ["friendly", "enemy"]
const SCAN_EVERY_FRAMES := 2
const MAX_RANGE := 100.0
const DEFAULT_TOLERANCE_DEG := 4.0
const TARGET_LIFT := 1.0 # точка прицеливания = origin цели +1м вверх (торс)

var _camera: Camera3D
var _markers := {} # type -> AimMarker
var _marked := {} # type -> Node3D
var _best_angle := {} # type -> float радианы (кто ближе к центру прицела)
var _frame := 0

func _ready() -> void:
	var layer := CanvasLayer.new()
	layer.name = "AimMarkers"
	layer.layer = 3 # под HUD (5) и окнами (50), над миром
	add_child(layer)
	for t in MARKER_TYPES:
		var m := Control.new()
		m.set_script(AimMarkerScript)
		m.set("color", _color_for(t))
		layer.add_child(m)
		_markers[t] = m

func _color_for(t: String) -> Color:
	if t == "friendly":
		return Color(0.55, 1.0, 0.62) # розово-зелёный (сердечко)
	return Color(0.0, 0.9, 1.0) # электрик-циан (шаровая молния)

func get_marked(type: String) -> Node3D:
	var n = _marked.get(type)
	if n != null and is_instance_valid(n):
		return n
	return null

func _physics_process(_delta: float) -> void:
	_frame += 1
	if _frame % SCAN_EVERY_FRAMES != 0:
		return
	_marked.clear()
	_best_angle = {"friendly": 1e9, "enemy": 1e9}
	var cam := _get_camera()
	if cam == null:
		return
	var cos_tol := cos(deg_to_rad(_tolerance_deg()))
	var cam_pos := cam.global_position
	var fwd := -cam.global_transform.basis.z
	for node in get_tree().get_nodes_in_group("aim_targets"):
		if not is_instance_valid(node) or not (node is Node3D):
			continue
		var ntype := _node_type(node)
		if ntype == "":
			continue
		var center: Vector3 = node.global_position + Vector3(0, TARGET_LIFT, 0)
		var to := center - cam_pos
		var dist := to.length()
		if dist > MAX_RANGE or dist < 1.0:
			continue
		var dir := to / dist
		var dot := fwd.dot(dir)
		if dot < cos_tol:
			continue
		if not _has_los(cam_pos, center, node):
			continue
		var angle := acos(clampf(dot, -1.0, 1.0))
		if angle < _best_angle.get(ntype, 1e9):
			_best_angle[ntype] = angle
			_marked[ntype] = node

func _process(_delta: float) -> void:
	var cam := _get_camera()
	for t in MARKER_TYPES:
		var m: Control = _markers.get(t)
		var node = _marked.get(t)
		if node == null or not is_instance_valid(node) or cam == null:
			m.set("active", false)
			continue
		var center: Vector3 = node.global_position + Vector3(0, TARGET_LIFT, 0)
		if cam.is_position_behind(center):
			m.set("active", false)
			continue
		m.set("screen_pos", cam.unproject_position(center))
		m.set("key_text", _key_for(t))
		m.set("active", true)

func _node_type(node: Node3D) -> String:
	var friendly: bool = node.get("is_friendly") == true
	if friendly and node.has_method("heal"):
		return "friendly"
	if not friendly and node.has_method("take_damage"):
		return "enemy"
	return ""

func _has_los(from: Vector3, to: Vector3, target: Node3D) -> bool:
	var space := get_viewport().get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(from, to)
	var parent := get_parent()
	if parent is CollisionObject3D:
		q.exclude = [parent.get_rid()]
	var hit := space.intersect_ray(q)
	return hit.is_empty() or hit.get("collider") == target

func _key_for(type: String) -> String:
	var player := get_parent()
	if player == null:
		return ""
	var bar := player.get_node_or_null("ActionBar")
	if bar == null:
		return ""
	var unlocked = player.get("unlocked_skills")
	if unlocked == null:
		return ""
	var db: Dictionary = SkillDB.get_skills()
	for sid in db:
		var sk = db[sid]
		var rt = sk.get("requires_target")
		var tt = sk.get("target_type")
		if rt == null or not rt or tt == null or tt != type:
			continue
		if not unlocked.get(sid, false):
			continue
		return bar.call("key_label_for_skill", sid)
	return ""

func _tolerance_deg() -> float:
	var sm := get_node_or_null("/root/SettingsMenu")
	if sm and sm.get("aim_assist_deg") != null:
		return float(sm.get("aim_assist_deg"))
	return DEFAULT_TOLERANCE_DEG

func _get_camera() -> Camera3D:
	if _camera and is_instance_valid(_camera):
		return _camera
	var player := get_parent()
	if player:
		_camera = player.get_node_or_null("SpringArm3D/Camera3D")
	return _camera
