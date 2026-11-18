extends Node

## Касты скиллов (план 17.11.26): инста — анимация + execute сразу; канал
## (cast_time > 0) — Cast_Enter → Cast_Loop, по истечении Cast_Shoot + execute.
## Прицел канала берётся ЗАНОВО в конце каста: метеор/гром ложатся по месту
## прицела в момент выброса, а не в момент старта (запрос юзера 17.11.26).
## Во время канала: повторные касты заблокированы, движение/прыжок гасит
## PlayerController через is_channeling(). Полоска каста — свой CanvasLayer.
## Снаряды берут context.cast_origin — позиция кисти (правой; при
## alternate_hands — попеременно лево/право, вердикт юзера по сердечку).

const SkillDB = preload("res://Logic/Skills/SkillDB.gd")

var _channeling := false
var _alt_left := false  # чередование рук для alternate_hands-скиллов
var _bar_layer: CanvasLayer
var _bar: ProgressBar
var _bar_label: Label
var _bar_tween: Tween

func _ready():
	# Полоска длительного каста (минимум: имя скилла + прогресс).
	_bar_layer = CanvasLayer.new()
	_bar_layer.layer = 30
	add_child(_bar_layer)
	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	box.offset_left = -120
	box.offset_right = 120
	box.offset_top = -150
	box.offset_bottom = -110
	_bar_layer.add_child(box)
	_bar_label = Label.new()
	_bar_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_bar_label)
	_bar = ProgressBar.new()
	_bar.show_percentage = false
	_bar.custom_minimum_size = Vector2(240, 12)
	box.add_child(_bar)
	_bar_layer.visible = false

	# IK-доводка кастов (заказ юзера 18.11.26): Graphics-компонент создаётся
	# рантайм, скелет задаём свойством (без регена player.tscn и без цикла preload).
	var ik := Node.new()
	ik.name = "CastIK"
	ik.set_script(load("res://Graphics/CastIKComponent.gd"))
	ik.set("skeleton", _find_skeleton(get_parent().get_node_or_null("GraphicsWrapper/PlayerModel")))
	add_child(ik)

func is_channeling() -> bool:
	return _channeling

func cast_skill(skill_id: String):
	var all_skills = SkillDB.get_skills()
	if not all_skills.has(skill_id):
		return

	var skill = all_skills[skill_id]
	if skill.is_passive:
		return
	if _channeling:
		return  # канал идёт — новые касты заблокированы

	var player = get_parent()

	# Рука каста: из скилла (cast_hand — должна совпадать с рукой cast_anim);
	# alternate_hands перекрывает — попеременно Л/П.
	var hand: String = skill.cast_hand
	var cast_anim_name: String = skill.cast_anim
	if skill.alternate_hands:
		_alt_left = not _alt_left
		hand = "Left" if _alt_left else "Right"
		if _alt_left:
			var anim_comp = player.get_node_or_null("PlayerAnimationComponent")
			if anim_comp and anim_comp.has_method("has_cast_anim") \
					and anim_comp.has_cast_anim(skill.cast_anim + "_L"):
				cast_anim_name = skill.cast_anim + "_L"

	var context = _aim_context(player, skill_id, skill, hand)
	if context.is_empty():
		return

	var anim_comp = player.get_node_or_null("PlayerAnimationComponent")

	if skill.cast_time > 0.0:
		# Канал: Enter → Loop (заморозка автомата), по таймеру Shoot + execute.
		_channeling = true
		if anim_comp and anim_comp.has_method("play_channel"):
			anim_comp.play_channel()
			# IK-доводка на всё окно канала + выброс (длина Cast_Shoot_UB).
			var shoot_len: float = 0.0
			if anim_comp.has_method("cast_clip_length"):
				shoot_len = anim_comp.cast_clip_length("Cast_Shoot")
			_ik_begin(player, hand, skill, skill.cast_time + shoot_len + 0.15)
		_cast_bar_start(skill.cast_time, skill.skill_name)
		await get_tree().create_timer(skill.cast_time).timeout
		_channeling = false
		_cast_bar_stop()
		# Сцена могла смениться/игрок умереть — объект освобождён, корутина
		# здесь просто не дожила; на живом игроке проверяем валидность.
		if not is_instance_valid(player) or not player.is_inside_tree():
			return
		if anim_comp and anim_comp.has_method("end_channel"):
			anim_comp.end_channel()
		# Прицел берётся ЗАНОВО в момент конца каста (запрос юзера): метеор
		# и гром должны попадать туда, куда смотришь при выбросе, а не туда,
		# куда смотрел при старте канала.
		context = _aim_context(player, skill_id, skill, hand)
		if context.is_empty():
			return
		skill.execute(player, context)
	else:
		if cast_anim_name != "" and anim_comp and anim_comp.has_method("play_cast_anim"):
			anim_comp.play_cast_anim(cast_anim_name)
			# IK-доводка на длину UB-клипа (окно = сам каст).
			if anim_comp.has_method("cast_clip_length"):
				_ik_begin(player, hand, skill, anim_comp.cast_clip_length(cast_anim_name))
		skill.execute(player, context)

## Прицел + валидация цели → контекст execute. Пустой Dictionary = каст
## отменён (requires_target не выполнен / нет камеры). Инста вызывает один
## раз; канал — повторно в момент КОНЦА каста, чтобы метеор и гром ложились
## по месту прицела в момент выброса (запрос юзера 17.11.26).
func _aim_context(player: Node, skill_id: String, skill, hand: String) -> Dictionary:
	var camera = player.get_node_or_null("SpringArm3D/Camera3D")
	if not camera:
		return {}

	var space_state = player.get_world_3d().direct_space_state
	var cam_pos = camera.global_position
	var forward = -camera.global_transform.basis.z

	var end_pos = cam_pos + forward * skill.max_range
	var query = PhysicsRayQueryParameters3D.create(cam_pos, end_pos)
	query.exclude = [player.get_rid()]

	var result = space_state.intersect_ray(query)
	var target_point = end_pos
	var hit_normal = Vector3.UP
	var target_node = null

	if result and result.has("position"):
		target_point = result.position
		hit_normal = result.normal
		target_node = result.collider

		if skill_id == "teleport":
			target_point += hit_normal * 1.0

	if skill.requires_target:
		var valid_target = false
		if target_node:
			var is_target_friendly = target_node.get("is_friendly") if "is_friendly" in target_node else false

			if skill.target_type == "friendly" and is_target_friendly and target_node.has_method("heal"):
				valid_target = true
			elif skill.target_type == "enemy" and not is_target_friendly and target_node.has_method("take_damage"):
				valid_target = true

		if not valid_target:
			print("Умение " + skill.skill_name + " требует правильную цель в прицеле!")
			return {}

	return {
		"target_pos": target_point,
		"hit_normal": hit_normal,
		"target_node": target_node,
		"camera_pos": cam_pos,
		"forward_dir": forward,
		"cast_origin": _hand_pos(player, hand),
		"hand": hand,  # для отложенного спавна из живой кисти (spawn_delay)
	}

## Окно IK-доводки: инста — длина UB-клипа; канал — cast_time + выброс.
## Провайдер — лямбда: каждый кадр окна свежая точка прицела.
func _ik_begin(player: Node, hand: String, skill, duration: float) -> void:
	if duration <= 0.0:
		return
	var ik := get_node_or_null("CastIK")
	if ik == null:
		return
	ik.begin(hand, func() -> Vector3: return _aim_point(player, skill.max_range), duration)

## Лёгкий прицел для IK (без валидации цели и принтов): точка под камерой-рейкастом.
func _aim_point(player: Node, max_range: float) -> Vector3:
	var camera = player.get_node_or_null("SpringArm3D/Camera3D")
	if camera == null:
		return player.global_position + Vector3(0, 1.2, 0)
	var forward = -camera.global_transform.basis.z
	var end_pos = camera.global_position + forward * max_range
	var query = PhysicsRayQueryParameters3D.create(camera.global_position, end_pos)
	query.exclude = [player.get_rid()]
	var result = player.get_world_3d().direct_space_state.intersect_ray(query)
	return result.get("position", end_pos)

## Глобальная позиция кости кисти (для спавна снарядов из руки).
func _hand_pos(player: Node, side: String) -> Vector3:
	var skel = _find_skeleton(player.get_node_or_null("GraphicsWrapper/PlayerModel"))
	if skel:
		var bi := skel.find_bone("mixamorig_%sHand" % side)
		if bi >= 0:
			return (skel.global_transform * skel.get_bone_global_pose(bi)).origin
	return player.global_position + Vector3(0, 1.2, 0)  # фолбэк — центр тела

static func _find_skeleton(node: Node) -> Skeleton3D:
	if not node:
		return null
	if node is Skeleton3D:
		return node
	for c in node.get_children():
		var r = _find_skeleton(c)
		if r:
			return r
	return null

func _cast_bar_start(duration: float, skill_name: String) -> void:
	_bar_label.text = skill_name
	_bar.max_value = duration
	_bar.value = duration
	_bar_layer.visible = true
	if _bar_tween:
		_bar_tween.kill()
	_bar_tween = create_tween()
	_bar_tween.tween_property(_bar, "value", 0.0, duration)

func _cast_bar_stop() -> void:
	if _bar_tween:
		_bar_tween.kill()
		_bar_tween = null
	_bar_layer.visible = false
