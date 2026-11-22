extends SceneTree
## Рендер-проба Q50 Шаг 2: Книга Навыков с секциями веток (не headless:
## null viewport, кадр не снимается). PNG: _tmp_probe/skill_branches_ui.png.

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var stub := GDScript.new()
	stub.source_code = "extends CharacterBody3D\nvar unlocked_skills := {}\nvar skill_points := 12\nvar SP_MAX := 20\nfunc update_hud():\n\tpass\n"
	stub.reload()
	var pl := CharacterBody3D.new()
	pl.set_script(stub)
	root.add_child(pl)
	var menu = load("res://Graphics/SkillMenu.gd").new()
	menu.name = "SkillMenu"
	pl.add_child(menu)
	await process_frame
	menu.panel.show()
	menu.is_open = true
	menu.refresh_sp()
	for i in 20:
		await process_frame
	DirAccess.make_dir_recursive_absolute("res://_tmp_probe")
	var img: Image = root.get_viewport().get_texture().get_image()
	img.save_png("res://_tmp_probe/skill_branches_ui.png")
	print("RB-branches: кадр сохранён (_tmp_probe/skill_branches_ui.png)")
	quit(0)
