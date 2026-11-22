extends SceneTree

## Parse-чек раунда стойки bard_groove (22.11.26): загрузка всех тронутых
## скриптов. SCRIPT ERROR / null / can_instantiate()==false → EXIT 1.
## Гейт ПЕРЕД механикой-пробой (новые файлы ещё ни разу не парсились).

const PATHS := [
	"res://Logic/BardGrooveComponent.gd",
	"res://Logic/SpellCasterComponent.gd",
	"res://Logic/PlayerController.gd",
	"res://Logic/Skills/SkillDB.gd",
	"res://Logic/Skills/EnterStanceEffect.gd",
	"res://Logic/Skills/GroovePulseEffect.gd",
	"res://Logic/Skills/GrooveStepEffect.gd",
	"res://Logic/Skills/GrooveCrescendoEffect.gd",
	"res://Graphics/BardGrooveUI.gd",
	"res://Graphics/AcousticBarrierVFX.gd",
]

func _init() -> void:
	var fails: Array = []
	for p in PATHS:
		var s: Script = load(p)
		if s == null or not s.can_instantiate():
			fails.append(p)
	if fails.is_empty():
		print("PARSE_OK %d скриптов" % PATHS.size())
		quit(0)
	else:
		print("PARSE_FAIL: ", fails)
		quit(1)
