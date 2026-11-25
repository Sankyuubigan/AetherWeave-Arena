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

## FFA-боты (Q10) глушат полоску каста — она игроковая (CanvasLayer поверх HUD).
@export var show_cast_bar: bool = true

## Множитель урона кастуемых скиллов (Q38 элитные боты ада): прокидывается в
## context (_aim_context) → Spawn*ProjectileEffect умножает damage компонента
## снаряда. Игрок — 1.0; элита ставит 2.5 (урон «повышенный» — заказ юзера).
@export var damage_mult: float = 1.0

## Отказ каста (вердикт спеца В.6.3: никаких тихих отказов — тост в HUD):
## «Идёт другой каст» / «Откат: N с». Слушает ActionBar.show_toast.
signal cast_rejected(text: String)

var _cd_until := {}  # skill_id → msec-граница конца отката

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

## Остаток отката скилла, с (для цифр на слоте ActionBar, В.6.4).
func cd_left(skill_id: String) -> float:
	if not _cd_until.has(skill_id):
		return 0.0
	return maxf(float(int(_cd_until[skill_id]) - Time.get_ticks_msec()) / 1000.0, 0.0)

func cast_skill(skill_id: String, extra_context: Dictionary = {}):
	var all_skills = SkillDB.get_skills()
	if not all_skills.has(skill_id):
		return

	var skill = all_skills[skill_id]
	if skill.is_passive:
		return
	# Кулдаун (вердикт спеца В.6.4): отказ с тостом; цифры отката на слоте
	# ActionBar рисуются по cd_left().
	if skill.cooldown > 0.0:
		var until := int(_cd_until.get(skill_id, 0))
		var now := Time.get_ticks_msec()
		if now < until:
			cast_rejected.emit("Откат: %.1f с" % (float(until - now) / 1000.0))
			return
	if _channeling:
		cast_rejected.emit("Идёт другой каст")
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
	if not extra_context.is_empty():
		context.merge(extra_context, true)  # stance_power и пр. (Q16 Шаг 1)
	_groove_judge(player, skill_id, context)

	var anim_comp = player.get_node_or_null("PlayerAnimationComponent")

	# Отсчёт кулдауна от НАЧАЛА каста (и канала, и инсты).
	if skill.cooldown > 0.0:
		_cd_until[skill_id] = Time.get_ticks_msec() + int(skill.cooldown * 1000.0)

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
		if not extra_context.is_empty():
			context.merge(extra_context, true)
		_groove_judge(player, skill_id, context)
		skill.execute(player, context)
	else:
		if cast_anim_name != "" and anim_comp and anim_comp.has_method("play_cast_anim"):
			anim_comp.play_cast_anim(cast_anim_name)
			# IK-доводка на длину UB-клипа (окно = сам каст).
			if anim_comp.has_method("cast_clip_length"):
				_ik_begin(player, hand, skill, anim_comp.cast_clip_length(cast_anim_name))
		skill.execute(player, context)

## «Пульс Битвы» (спец 11-ответ, 22.11.26): при активной стойке bard_groove
## КАЖДЫЙ каст судится ритмом (BardGrooveComponent.evaluate_action): саб —
## source "sub" (спам-штраф мимо бита), остальное — "skill". perfect/good →
## урон ×TIER_DAMAGE_MULT[tier] (1.0/1.15/1.25/1.35), offbeat → без множителя.
## Скилл НИКОГДА не блокируется вердиктом (ТЗ Блок 2.3) — только масштаб.
func _groove_judge(player: Node, skill_id: String, context: Dictionary) -> void:
	var groove = player.get_node_or_null("BardGrooveComponent")
	if groove == null or not bool(groove.is_active):
		return
	var skill = SkillDB.get_skills().get(skill_id)
	var source := "sub" if skill != null and "is_sub_skill" in skill \
			and bool(skill.is_sub_skill) else "skill"
	var verdict: String = groove.evaluate_action(source)
	context["groove_verdict"] = verdict  # для эффектов (pulse ×1.25/×0.4 и пр.)
	if verdict == "perfect" or verdict == "good":
		var mult := float(groove.TIER_DAMAGE_MULT[groove.tier])
		context["damage_mult"] = float(context.get("damage_mult", 1.0)) * mult

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
		# AIM ASSIST (Q29): сначала ПОМЕЧЕННАЯ ассистом цель — наведение рядом
		# с целью (угол от F2-ползунка), помеченная честно получает каст.
		# Точное попадание прицела (рейкаст) — валидация ниже по-старому.
		var assist = player.get_node_or_null("AimAssist")
		var marked = assist.get_marked(skill.target_type) if assist else null
		if marked:
			target_node = marked
			target_point = marked.global_position + Vector3(0, 1.0, 0)
			hit_normal = Vector3.UP
			valid_target = true
		elif target_node:
			var is_target_friendly = target_node.get("is_friendly") if "is_friendly" in target_node else false
			# Дружественность ОТНОСИТЕЛЬНА к кастеру: enemy-скилл не бьёт только
			# «своих» (и кастер friendly, и цель friendly). Регресс Q35 (19.11.26,
			# репорт юзера «боты меня не трогают, только друг друга»): после
			# добавления is_friendly ИГРОКУ (сердечки) боты и мобы ада теряли
			# валидацию enemy-цели в игроке — casts в игрока молча отменялись.
			var caster_friendly: bool = player.get("is_friendly") == true

			if skill.target_type == "friendly" and is_target_friendly and target_node.has_method("heal"):
				valid_target = true
			elif skill.target_type == "enemy" and target_node.has_method("take_damage") \
					and not (caster_friendly and is_target_friendly):
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
		"damage_mult": damage_mult,  # элитные боты ада ×2.5 (Q38)
	}

## Окно IK-доводки: инста — длина UB-клипа; канал — cast_time + выброс.
## Провайдер — лямбда: каждый кадр окна свежая точка прицела.
func _ik_begin(player: Node, hand: String, skill, duration: float) -> void:
	if duration <= 0.0:
		return
	# Авторазворот к прицелу (спец 23.11.26): корпус доворачивается к цели.
	var aim := _aim_point(player, skill.max_range)
	if player.has_method("face_aim_target"):
		player.face_aim_target(aim, duration)
	var comp = player.get_node_or_null("PlayerAnimationComponent")
	if comp != null and comp.has_method("set_aim"):
		comp.set_aim(aim, duration)  # мягкий прицел позвоночником (AimSpine)
	var ik := get_node_or_null("CastIK")
	if ik == null:
		return
	# 2-bone IK ТОЛЬКО для физ-контакта в пределах руки (захват троса
	# ether_tether). Дальние касты/лучи — IK ВЫКЛ: иначе 2-bone выпрямляет
	# локоть в палку и выворачивает плечо — «кукольные руки» (баг спеца).
	var sid: String = str(skill.get("id"))
	ik.ik_mode = "aim_hand" if sid == "ether_tether" else "none"
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
	if not show_cast_bar:
		return
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
