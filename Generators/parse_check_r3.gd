extends SceneTree

## Раунд 3 (вердикт спеца 09+10): синтакс-гейт всех тронутых файлов.
## PASS = все скрипты грузятся и компилируются (EXIT 0).

func _init() -> void:
	var files := [
		"res://Logic/RhythmJudge.gd",
		"res://Logic/BardFlowComponent.gd",
		"res://Logic/StanceComponent.gd",
		"res://Logic/Skills/EnterStanceEffect.gd",
		"res://Logic/Skills/Skill.gd",
		"res://Logic/Skills/SkillDB.gd",
		"res://Logic/SpellCasterComponent.gd",
		"res://Logic/PlayerController.gd",
		"res://Graphics/BardLaneView.gd",
		"res://Graphics/BardFlowUI.gd",
		"res://Graphics/ActionBar.gd",
		"res://Graphics/SkillMenu.gd",
		"res://Graphics/AcousticBarrierVFX.gd",
	]
	var bad := 0
	for f in files:
		var s = load(f)
		if s == null or not (s is GDScript) or not s.can_instantiate():
			bad += 1
			print("FAIL ", f)
		else:
			print("OK   ", f)
	print("PARSE_CHECK: %d/%d OK" % [files.size() - bad, files.size()])
	quit(0 if bad == 0 else 1)
