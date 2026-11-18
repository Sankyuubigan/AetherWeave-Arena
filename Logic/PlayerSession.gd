extends Node

## Персист состояния скиллов между картами (19.11.26).
## Баг юзера: при телепорте change_scene_to_file пересоздаёт инстанс игрока —
## купленные навыки, SP и раскладка ActionBar сбрасывались в ноль.
## Автолоад живёт на /root всю сессию игры: PlayerController._exit_tree делает
## снапшот, новый инстанс игрока в _ready восстанавливает. Пресеты навыков
## персистятся отдельно сами (user://skill_presets.json, SkillPresetsPanel).

var has_state: bool = false
var unlocked_skills: Dictionary = {}
var skill_points: int = 50
var bar: Array = []  # skill_id по слотам ActionBar

func capture(player: Node) -> void:
	unlocked_skills = player.unlocked_skills.duplicate()
	skill_points = int(player.skill_points)
	bar = []
	var action_bar = player.get_node_or_null("ActionBar")
	if action_bar:
		for slot in action_bar.slots:
			bar.append(slot.skill_id)
	has_state = true

func restore(player: Node) -> void:
	if not has_state:
		return
	for sid in unlocked_skills:
		# Чужие/устаревшие id молча пропускаем — у нового инстанса только
		# ключи SkillDB (заполняются в _ready до вызова restore).
		if player.unlocked_skills.has(sid):
			player.unlocked_skills[sid] = unlocked_skills[sid]
	player.skill_points = skill_points
