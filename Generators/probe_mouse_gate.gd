extends SceneTree

## ГЕЙТ МЫШЬ-ССОТ (docs/ui_input_rules.md, 19.11.26): после регрессии
## «мышь не фокусится в игру» (v1-гейт по gui_get_hovered_control блокировал
## захват ВСЕГДА). Проверяем: 1) все участники компилируются; 2) игрок
## инстанцируется; 3) _gui_blocks_capture() == false при закрытых UI;
## 4) true при открытой скилл-книге; 5) true при группе npc_dialog_open.
## Статический чек «CAPTURED ставится только в PlayerController» — grep
## из Bash (см. доку, раздел «Гейт регрессии»).

func _init() -> void:
	var fails := 0
	for path in [
		"res://Logic/PlayerController.gd",
		"res://Graphics/SkillMenu.gd",
		"res://Graphics/SettingsMenu.gd",
		"res://Logic/NPCTeleporter.gd",
		"res://Logic/SkillForge.gd",
		"res://Logic/Skills/SkillSerializer.gd",
		"res://Logic/Skills/UserSkillDB.gd",
		"res://Graphics/SkillForgeWindow.gd",
		"res://Graphics/SkillForgeList.gd",
	]:
		var s := load(path) as Script
		if s == null or not s.can_instantiate():
			print("FAIL: не компилируется %s" % path)
			fails += 1
		else:
			print("PASS: compile %s" % path)

	await process_frame
	var ps: PackedScene = load("res://Scenes/player.tscn")
	if ps == null:
		print("FAIL: player.tscn не загрузилась")
		quit(1)
		return
	var player: Node = ps.instantiate()
	root.add_child(player)
	await process_frame

	# 3. Гейт при закрытых UI = false (клик по миру должен захватывать мышь).
	var blocked: bool = player.call("_gui_blocks_capture")
	if blocked:
		print("FAIL: гейт блокирует захват при ЗАКРЫТЫХ меню — снова v1-регрессия")
		fails += 1
	else:
		print("PASS: гейт пропускает клик по миру при закрытых UI")

	# 4. Открытая скилл-книга блокирует захват.
	var sm: Node = player.get_node_or_null("SkillMenu")
	if sm == null:
		print("FAIL: у игрока нет SkillMenu")
		fails += 1
	else:
		sm.set("is_open", true)
		if not player.call("_gui_blocks_capture"):
			print("FAIL: открытая скилл-книга НЕ блокирует захват")
			fails += 1
		else:
			print("PASS: открытая скилл-книга блокирует захват")
		sm.set("is_open", false)

	# 5. Группа npc_dialog_open (диалог телепортера) блокирует захват.
	var flag := Node.new()
	root.add_child(flag)
	flag.add_to_group("npc_dialog_open")
	if not player.call("_gui_blocks_capture"):
		print("FAIL: npc_dialog_open НЕ блокирует захват")
		fails += 1
	else:
		print("PASS: npc_dialog_open блокирует захват")
	flag.remove_from_group("npc_dialog_open")  # не портить последующие чеки

	# 6. Кузница скиллов (Q36): открытое окно блокирует захват.
	var fw = root.get_node_or_null("SkillForgeWindow")
	if fw == null:
		print("FAIL: автолоад /root/SkillForgeWindow отсутствует")
		fails += 1
	else:
		fw.set("is_open", true)
		if not player.call("_gui_blocks_capture"):
			print("FAIL: открытое окно Кузницы НЕ блокирует захват")
			fails += 1
		else:
			print("PASS: открытое окно Кузницы блокирует захват")
		fw.set("is_open", false)
		if player.call("_gui_blocks_capture"):
			print("FAIL: закрытое окно Кузницы блокирует захват (лишний гейт)")
			fails += 1
		else:
			print("PASS: закрытое окно Кузницы не блокирует захват")

	if fails == 0:
		print("MOUSE-GATE ALL PASS")
		quit(0)
	else:
		print("MOUSE-GATE FAIL (%d)" % fails)
		quit(1)
