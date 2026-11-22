extends SceneTree

## Probe Q50 Шаг 2 (PRP tasks/q50_q51_admin_branches.md): группировка магазина
## по веткам. Гейт: секции в порядке order, «Разное» последняя, все shop-скиллы
## распределены, под-приёмы отсутствуют; SkillMenu строит заголовки = секции,
## слоты = карточки, прокрутка на месте. EXIT 0 = PASS.

const SMG := preload("res://Graphics/SkillBranchGrouping.gd")
const SDB := preload("res://Logic/Skills/SkillDB.gd")
const SKILLMENU := preload("res://Graphics/SkillMenu.gd")
const BRDB := preload("res://Logic/Skills/SkillBranchDB.gd")

var _pass := 0
var _fail := 0

func _ck(cond: bool, label: String) -> void:
	if cond:
		_pass += 1
		print("  PASS  %s" % label)
	else:
		_fail += 1
		print("  FAIL  %s" % label)

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	print("=== PROBE: Q50 Шаг 2 — группировка магазина по веткам ===")
	await process_frame

	print("--- секция 1: хелпер группировки ---")
	var shop := SDB.get_shop_skills()
	var groups: Array = SMG.grouped(shop)
	var total := 0
	var no_subs := true
	for g in groups:
		total += g["skills"].size()
		for s in g["skills"]:
			if s.is_sub_skill:
				no_subs = false
	_ck(total == shop.size(), "все %d shop-скиллов распределены по секциям" % shop.size())
	_ck(no_subs, "под-приёмы не попали в магазин")
	var order_ids := []
	for g in groups:
		order_ids.append(g["id"])
	_ck(order_ids[order_ids.size() - 1] == "", "«Разное» последняя секция")
	_ck(order_ids.find("elemental") != -1 and order_ids.find("elemental") < order_ids.find("bard"),
		"elemental раньше bard (порядок order)")
	var misc_last: Dictionary = groups[groups.size() - 1]
	var misc_ids := []
	for s in misc_last["skills"]:
		misc_ids.append(s.id)
	_ck(misc_ids.has("double_jump") and misc_ids.has("ether_tether"), "double_jump/ether_tether в «Разном»")
	_ck(not misc_ids.has("fireball"), "fireball НЕ в «Разном»")
	_ck(misc_last["name"] == BRDB.load_data()["misc"].get("name", "Разное"),
		"заголовок «Разного» берётся из misc-меты JSON (переименуемая)")

	print("--- секция 2: сборка SkillMenu (стаб игрока) ---")
	var stub := GDScript.new()
	stub.source_code = """
extends CharacterBody3D
var unlocked_skills := {}
var skill_points := 12
var SP_MAX := 20
func update_hud():
	pass
"""
	stub.reload()
	var pl := CharacterBody3D.new()
	pl.set_script(stub)
	root.add_child(pl)
	var menu = SKILLMENU.new()
	menu.name = "SkillMenu"
	pl.add_child(menu)
	await process_frame
	_ck(menu.panel != null, "панель книги построена")
	_ck(menu.scroll != null and menu.grid != null, "прокрутка + vbox секций на месте")
	var heads := 0
	var slots := 0
	# Заголовки секций — ТОЛЬКО прямые дети vbox (в карточках свои Label'ы).
	for c in menu.grid.get_children():
		if c is Label:
			heads += 1
	var stack := [menu.grid]
	while not stack.is_empty():
		var n = stack.pop_back()
		for c in n.get_children():
			stack.push_back(c)
			if c.get("skill_data") != null:
				slots += 1
	_ck(heads == groups.size(), "заголовков %d = секций %d" % [heads, groups.size()])
	_ck(slots == shop.size(), "карточек %d = shop-скиллов %d" % [slots, shop.size()])
	var row_grids := 0
	for c in menu.grid.get_children():
		if c is GridContainer:
			row_grids += 1
	_ck(row_grids == groups.size(), "гридов-секций %d = секций" % row_grids)

	print("=== ИТОГ: %d PASS / %d FAIL ===" % [_pass, _fail])
	quit(0 if _fail == 0 else 1)
