extends SceneTree
## ГЕЙТ авто-списка каст-анимаций (26.11.26): список в SkillSerializer больше
## НЕ правится руками — он выводится из каст-библиотеки. Проверяем:
##  1) в списке есть ВСЕ базовые клипы библиотеки (без _UB);
##  2) нет ни одного имени с суффиксом _UB (в данных скилла имя базовое);
##  3) есть пустая строка (скилл без анимации);
##  4) has_cast_anim() согласован со списком, мусор отвергается;
##  5) Кузница получает тот же список (нет своего захардкоженного массива);
##  6) round-trip: скилл с КАЖДЫМ клипом библиотеки переживает save→load.
## Запуск: --headless -s res://Generators/test_cast_anim_whitelist.gd (EXIT=0=PASS)

const SER := preload("res://Logic/Skills/SkillSerializer.gd")
const LIB := "res://Graphics/Animations/ual_casts_test.res"

var fails: Array[String] = []

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var lib = load(LIB)
	if lib == null or not (lib is AnimationLibrary):
		print("WHITELIST FAIL: нет библиотеки ", LIB)
		quit(1)
		return

	# 1) все базовые клипы библиотеки в списке
	var expected: Array[String] = [""]
	for n in lib.get_animation_list():
		var s := String(n)
		if not s.ends_with("_UB"):
			expected.append(s)
	var got: Array = SER.cast_anims()
	var missing: Array[String] = []
	for e in expected:
		if not got.has(e):
			missing.append(e)
	if missing.is_empty():
		print("WHITELIST: все %d базовых клипов библиотеки в списке" % expected.size())
	else:
		fails.append("в списке нет: " + ", ".join(missing))

	# 2) никаких _UB
	var ub_in_list: Array[String] = []
	for g in got:
		if String(g).ends_with("_UB"):
			ub_in_list.append(String(g))
	if ub_in_list.is_empty():
		print("WHITELIST: служебных _UB-имён нет (верно — в данных имя базовое)")
	else:
		fails.append("в списке _UB-имена: " + ", ".join(ub_in_list))

	# 3) пустая строка есть
	if got.has(""):
		print("WHITELIST: пустая строка есть (скилл без анимации)")
	else:
		fails.append("нет пустой строки — нельзя сделать скилл без анимации")

	# 4) has_cast_anim
	var checks := [
		["Throw", true], ["Spell_Cast_L", true], ["Cast_2H_Spell", true],
		["Throw_UB", false], ["Backflip", false], ["../evil", false], ["", true],
	]
	for c in checks:
		var name: String = c[0]
		var want: bool = c[1]
		var res := SER.has_cast_anim(name)
		if res != want:
			fails.append("has_cast_anim('%s') = %s, ожидалось %s" % [name, res, want])
	print("WHITELIST: has_cast_anim согласован (в т.ч. мусор отвергается)")

	# 5) Кузница: ANIMS не константа-хардкод, а из сериализатора
	var forge_src := FileAccess.get_file_as_string("res://Graphics/SkillForgeWindow.gd")
	if forge_src.contains("const ANIMS := [\"\""):
		fails.append("Кузница всё ещё держит свой захардкоженный ANIMS")
	elif not forge_src.contains("SER.cast_anims()"):
		fails.append("Кузница не берёт список из SER.cast_anims()")
	else:
		print("WHITELIST: Кузница берёт список из SER.cast_anims()")

	# 6) round-trip для КАЖДОГО клипа
	var SKILL := preload("res://Logic/Skills/Skill.gd")
	var broken: Array[String] = []
	for name in expected:
		var s = SKILL.new()
		s.id = "wl_test"
		s.cast_anim = name
		var d: Dictionary = SER.skill_to_dict(s)
		if String(d.get("cast_anim", "<нет>")) != name:
			broken.append("%s → в словарь попало '%s'" % [name, d.get("cast_anim", "<нет>")])
			continue
		# минимальный валидный эффект, иначе skill_from_dict отвергнет запись
		d["effects"] = [{"type": "play_sound", "stream": "res://Audio/SFX/neural_fireball.res"}]
		var back = SER.skill_from_dict(d)
		if back == null:
			broken.append("%s → skill_from_dict вернул null" % name)
		elif String(back.cast_anim) != name:
			broken.append("%s → после load стало '%s'" % [name, back.cast_anim])
	if broken.is_empty():
		print("WHITELIST: round-trip save→load сохранил ВСЕ %d имён" % expected.size())
	else:
		fails.append("round-trip: " + "; ".join(broken))

	if fails.is_empty():
		print("WHITELIST: ALL PASS")
		quit(0)
	else:
		print("WHITELIST FAIL: ", "; ".join(fails))
		quit(1)
