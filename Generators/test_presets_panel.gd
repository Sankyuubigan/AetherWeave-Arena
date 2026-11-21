extends SceneTree

## Тест панели пресетов (регресс: player=null падал в _on_add на «+»).
## Собирает минимальный стаб игрока (PlayerController сам добавляет
## SkillMenu + ActionBar), дёргает _on_add/_on_load/_on_delete напрямую
## и проверяет JSON-файл. Запуск:
##   Godot --headless -s res://Generators/test_presets_panel.gd

const SAVE_PATH := "user://skill_presets.json"

func _init():
	# ВАЖНО (-s-кварк): в _init узлы ещё не «в дереве», _ready не звался.
	# Строим стаб, ждём один кадр — только потом проверки.
	_run()

func _run():
	await process_frame
	var errors: Array[String] = []

	# --- стаб игрока: узлы, которые требует PlayerController._ready ---
	var world := Node3D.new()
	root.add_child(world)

	var player := CharacterBody3D.new()
	player.set_script(load("res://Logic/PlayerController.gd"))
	var arm := SpringArm3D.new()
	arm.name = "SpringArm3D"
	var cam := Camera3D.new()
	cam.name = "Camera3D"
	arm.add_child(cam)
	player.add_child(arm)
	var gfx := Node3D.new()
	gfx.name = "GraphicsWrapper"
	player.add_child(gfx)
	var caster := Node.new()
	caster.name = "SpellCasterComponent"
	player.add_child(caster)
	world.add_child(player)

	var menu = player.get_node_or_null("SkillMenu")
	if menu == null:
		errors.append("SkillMenu не добавился в _ready игрока")
	else:
		var panel = menu.presets_panel
		if panel == null:
			errors.append("presets_panel не создан")
		else:
			if panel.player == null:
				errors.append("panel.player = null (регресс!)")
			else:
				# Чистый прогон: покупаем навык, расставляем в слот.
				var db = load("res://Logic/Skills/SkillDB.gd").get_skills()
				var first_id: String = db.keys()[0]
				menu.buy_skill(first_id, db[first_id].price)
				player.get_node("ActionBar").slots[0].set_skill(first_id)

				# Снапшот «до» для сравнения.
				var file_before := FileAccess.file_exists(SAVE_PATH)

				panel._name_input.text = "Тест Пресет"
				panel._on_add()
				var presets: Array = panel._load_file()
				if presets.is_empty():
					errors.append("_on_add: файл пуст или не записан")
				else:
					var p: Dictionary = presets[-1]
					if p.get("name") != "Тест Пресет":
						errors.append("имя пресета не сохранилось: " + str(p.get("name")))
					if not first_id in p.get("skills", []):
						errors.append("купленный навык не попал в снапшот")
					if p.get("bar", []).size() != 14:
						errors.append("bar != 14 слотов")
					elif p["bar"][0] != first_id:
						errors.append("слот 0 не сохранил навык")

					# Видимость списка (регресс: высота ScrollContainer 0px —
					# строки строились, но не отображались; лог чистый).
					await process_frame
					if panel._rows_box.get_child_count() < 1:
						errors.append("refresh: строки списка не созданы")
					else:
						var row = panel._rows_box.get_child(panel._rows_box.get_child_count() - 1)
						if row.get_global_rect().size.y <= 0.0:
							errors.append("строка пресета с нулевой высотой — список невидим (лэйаут!)")

					# Q42: 💾-пересохранение с подтверждением. Меняем состояние
					# (покупаем второй навык, второй слот), дёргаем _on_save —
					# диалог должен открыться, запись НЕ меняться; «Да» —
					# запись перезаписана, имя сохранено.
					var second_id: String = db.keys()[1] if db.keys().size() > 1 else first_id
					menu.buy_skill(second_id, db[second_id].price)
					if not player.unlocked_skills.get(second_id, false):
						errors.append("тест некорректен: второй навык не купился (SP?)")
					player.get_node("ActionBar").slots[1].set_skill(second_id)
					var skills_before: int = presets[-1].get("skills", []).size()
					panel._on_save(presets.size() - 1)
					if panel._confirm == null or not panel._confirm.visible:
						errors.append("💾: подтверждение не открылось")
					if panel._pending_save != presets.size() - 1:
						errors.append("💾: pending index не выставлен")
					if panel._load_file()[-1].get("skills", []).size() != skills_before:
						errors.append("💾: запись изменилась ДО подтверждения (должна ждать «да»)")
					panel._on_confirm_save()
					var p2: Dictionary = panel._load_file()[-1]
					if p2.get("name") != "Тест Пресет":
						errors.append("💾: имя пресета затёрлось: " + str(p2.get("name")))
					if not second_id in p2.get("skills", []):
						errors.append("💾: новое состояние не пересохранилось")
					if p2.get("bar", [])[1] != second_id:
						errors.append("💾: слот 1 не попал в пересохранение")
					if panel._pending_save != -1:
						errors.append("💾: pending не сброшен после пересохранения")
					if panel._confirm != null and panel._confirm.visible:
						errors.append("💾: диалог не закрылся после «да»")
					presets = panel._load_file()  # после пересохранения записи обновились
					p = presets[-1]  # и p тоже (SP-чек ниже сравнивает с файлом)
					panel._on_load(presets.size() - 1)

					# Загрузка: продать и перезагрузить пресет.
					menu.sell_skill(first_id, db[first_id].price)
					if player.unlocked_skills.get(first_id, false):
						errors.append("sell_skill не сработал (тест некорректен)")
					panel._on_load(presets.size() - 1)
					if not player.unlocked_skills.get(first_id, false):
						errors.append("_on_load не восстановил навык")
					if player.get_node("ActionBar").slots[0].skill_id != first_id:
						errors.append("_on_load не восстановил слот 0")
					if player.skill_points != int(p.get("sp", -1)):
						errors.append("_on_load не восстановил SP")

					# Удаление.
					panel._on_delete(presets.size() - 1)
					if panel._load_file().size() != presets.size() - 1:
						errors.append("_on_delete не удалил запись")

				# Если файла до теста не было — не оставляем мусор.
				if not file_before and FileAccess.file_exists(SAVE_PATH):
					DirAccess.remove_absolute(SAVE_PATH)

	if errors.is_empty():
		print("TEST PRESETS: PASS")
		quit(0)
	else:
		for e in errors:
			printerr("TEST PRESETS FAIL: " + e)
		quit(1)
