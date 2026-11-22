extends "res://Logic/Skills/Effect.gd"

## Атомарный эффект входа в стойку (Q16, ТЗ спеца). Находит StanceComponent
## у кастера и входит с конфигом. Под-приёмы берутся у Skill-сборки стойки
## из SkillDB (Skill.stance_sub_skills) — скилл-родитель регистрирует эффект.

## id Skill-сборки стойки (в SkillDB, с заполненными stance_sub_skills).
@export var stance_id: String = ""
## Длительность стойки (с). Мана-стойка — 4.0 (ТЗ спеца).
@export var duration: float = 4.0

func apply(caster: Node, _context: Dictionary) -> void:
	if stance_id == "":
		push_warning("EnterStanceEffect: stance_id пуст — вход отклонён")
		return
	var stance = caster.get_node_or_null("StanceComponent")
	if stance == null:
		push_warning("EnterStanceEffect: у «%s» нет StanceComponent" % caster.name)
		return
	var subs: Array = []
	# load() в рантайме (не preload): SkillDB в Шаге 2 пре-лоадит этот эффект —
	# цикл preload SkillDB↔EnterStanceEffect в Godot ломается.
	var sk = load("res://Logic/Skills/SkillDB.gd").get_skills().get(stance_id)
	if sk != null and not sk.stance_sub_skills.is_empty():
		subs = sk.stance_sub_skills
	stance.enter_stance({
		"stance_id": stance_id,
		"stance_skill_id": stance_id,
		"duration": duration,
		"sub_skills": subs,
		# Вердикт юзера 22.11.26: мана-стойка — приём = разряд (закрывает стойку).
		"exit_on_sub": bool(sk.get("stance_exit_on_sub")) if sk != null else false,
	})
