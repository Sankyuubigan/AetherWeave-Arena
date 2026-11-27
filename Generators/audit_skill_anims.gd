extends SceneTree
## АУДИТ МАТРИЦЫ «СКИЛЛ × АНИМАЦИЯ × КАНДИДАТ» (27.11.26, Шаг 5 плана
## tasks/261125_1509-02207363).
##
## Зачем: проводка «скилл → клип» живёт в ТРЁХ источниках — SkillDB (что играет),
## ual_casts_test.res (что реально есть), admin/candidates.json (что предлагаем на
## замену). Рассогласование не ломает запуск: скилл молча играет не то или не
## играет вовсе — ровно так жил баг «у wings вообще ничего не стоит». Аудит
## сводит три источника в одну таблицу и делает дыры видимыми.
##
## ВАЖНО (урок 27.11.26): скиллы читаются ЖИВЬЁМ из SkillDB, а НЕ из
## temp/skills_dump.json. Дамп регенерит только admin/start_admin.bat — после
## правки SkillDB он врал (heart_heal показывался со старым Spell_Cast). Аудит
## по устаревшему дампу хуже отсутствия аудита.
##
## Кандидат проверяется по ДВУМ независимым признакам:
##   file   — существует ли файл-превью на диске (src: glb/raw/mixamo/lib/neuro);
##   in_lib — есть ли клип в каст-библиотеке: под именем кандидата ИЛИ под именем
##            из манифеста, чей файл-источник совпадает (Flying.fbx → Wings_Fly).
## «Файла нет» ≠ «анимации нет»: Blade_Swing_A собран из UAL2 и лежит в
## библиотеке, но отдельного файла-превью у него нет — это флаг no_preview,
## а не провал. Провал — когда клипа нет НИ в файлах, НИ в библиотеке.
##
## Запуск: --headless -s res://Generators/audit_skill_anims.gd
## Выход: temp/skill_anim_audit.json + таблица в stdout.
## EXIT: 0 — рассогласований нет; 1 — есть (список в stdout).
##
## ДВА КЛАССА ПРОБЛЕМ — не путать (иначе гейт воет на нормальное):
##   FAIL  — НАША ошибка данных: скилл объявил клип, которого нет в библиотеке;
##           у кандидата битая ссылка на файл. Это всегда баг, чинится сразу.
##   WARN  — анимация НЕ ЗАДАНА там, где могла бы быть (мана-ветка, стойка
##           концентрации). Это решение геймдизайнера, а не регресс: гейт
##           показывает дыру, но не падает. Список WARN — в отчёте и в stdout.
## Гейт падает только на FAIL. «Нет анимации» без клипа — WARN.

const SDB := preload("res://Logic/Skills/SkillDB.gd")
const LIB := "res://Graphics/Animations/ual_casts_test.res"
const MANIFEST := "res://Data/animations_manifest.json"
const CANDS := "res://admin/candidates.json"
const OUT := "res://temp/skill_anim_audit.json"

## src кандидата → каталог, где лежит файл-превью (lib/neuro — особые случаи).
const SRC_DIRS := {
	"glb": "res://tools/candidates_models/",
	"raw": "res://Graphics/Animations/raw/mixamo/",
	"mixamo": "res://Graphics/mixamo-lib/fbx/",
}
const NEURO_DIR := "res://Graphics/Animations/neuro_soma/"

## Вердикты-ПРОВАЛЫ: только наши ошибки (клип объявлен, но его нет / битая
## ссылка на файл кандидата). «Анимация не задана» — WARN, решение юзера.
const HOLE := ["MISSING"]

var fails: Array[String] = []
var warns: Array[String] = []

func _init() -> void:
	var lib = load(LIB)
	if lib == null or not (lib is AnimationLibrary):
		print("AUDIT FAIL: нет библиотеки ", LIB)
		quit(1)
		return
	var manifest := _read_json(MANIFEST)
	var cands := _read_json(CANDS)
	if manifest.is_empty() or cands.is_empty():
		print("AUDIT FAIL: не читаются манифест/кандидаты")
		quit(1)
		return

	# stem файла-источника → имена клипов в игре (Flying.fbx → Wings_Fly).
	var by_stem := _by_source_stem(manifest)
	var by_id := _cands_by_id(cands)
	var parents := _sub_parents(SDB.get_skills())
	var lib_names := {}
	for n in lib.get_animation_list():
		lib_names[String(n)] = true

	var rows: Array = []
	var table: Array[String] = []
	for sid in SDB.get_skills():
		var sk = SDB.get_skills()[sid]
		var cand: Dictionary = by_id.get(str(sid), {})
		var row := _audit_skill(sk, cand, lib_names, by_stem, parents)
		rows.append(row)
		table.append(_table_line(row))
		_check_row(row)

	var report := {
		"generated": Time.get_datetime_string_from_system(),
		"library": LIB,
		"skills_count": rows.size(),
		"rows": rows,
		"fails": fails,
		"warns": warns,
	}
	DirAccess.make_dir_recursive_absolute(OUT.get_base_dir())
	var f := FileAccess.open(OUT, FileAccess.WRITE)
	if f == null:
		print("AUDIT FAIL: не записать ", OUT)
		quit(1)
		return
	f.store_string(JSON.stringify(report, "\t"))
	f.close()

	for t in table:
		print(t)
	print("")
	print("AUDIT: записей %d, отчёт %s" % [rows.size(), OUT])
	if rows.size() < 20:
		fails.append("в отчёте %d записей — SkillDB читается не полностью" % rows.size())
	if not warns.is_empty():
		print("AUDIT: WARN — анимация не задана (%d), решение геймдизайнера:" % warns.size())
		for w in warns:
			print("  * ", w)
	if fails.is_empty():
		print("AUDIT: PASS (FAIL=0, WARN=%d)" % warns.size())
		quit(0)
	else:
		print("AUDIT: FAIL (%d)" % fails.size())
		for x in fails:
			print("  - ", x)
		quit(1)

# ─────────────────────────── одна строка матрицы ───────────────────────────

func _audit_skill(sk, cand: Dictionary, lib_names: Dictionary, by_stem: Dictionary,
		parents: Dictionary) -> Dictionary:
	var sid := str(sk.id)
	var owned := str(cand.get("anim_owned_by", ""))
	var clips: Array = []
	for pair in [["cast", str(sk.cast_anim)], ["next", str(sk.next_cast_anim)],
			["stance", str(sk.stance_loop_anim)]]:
		if pair[1] != "":
			clips.append({"role": pair[0], "name": pair[1],
					"in_lib": _in_lib(pair[1], lib_names)})

	var cand_rows: Array = []
	for c in cand.get("cands", []):
		cand_rows.append(_audit_cand(c, lib_names, by_stem))

	var arche := _archetype(sk)
	var verdict := "OK"
	var notes: Array[String] = []
	var need: String = _required_clip(sk, arche)
	if need != "":
		if not _in_lib(need, lib_names):
			verdict = "MISSING"
			notes.append("клип «%s» не найден в каст-библиотеке — каст не заиграет" % need)
	elif arche == "sub":
		# Под-приём играет позу стойки-родителя: своей анимации у него нет.
		var pid := str(parents.get(sid, ""))
		if pid == "":
			verdict = "NO_ANIM"
			notes.append("под-приём не привязан ни к одной стойке (stance_sub_skills)")
		else:
			var pl: String = str(SDB.get_skills()[pid].stance_loop_anim)
			if pl == "":
				verdict = "NO_ANIM"
				notes.append("у стойки-родителя «%s» нет stance_loop_anim" % pid)
			elif not _in_lib(pl, lib_names):
				verdict = "MISSING"
				notes.append("поза стойки «%s» (родитель %s) не в библиотеке" % [pl, pid])
			else:
				verdict = "OK_SUB"
				notes.append("играет позу стойки «%s» (родитель %s)" % [pl, pid])
	elif arche == "stance":
		# Стойка обязана иметь posture-луп: без него стойка выглядит как
		# «перс замер в idle». У концентрации маны лупа нет — это WARN.
		verdict = "NO_ANIM"
		notes.append("стойка без stance_loop_anim — перс стоит в idle")
	elif owned != "":
		if owned.contains("не нужна"):
			verdict = "NOT_NEEDED"
		else:
			verdict = "OK_OWNED"
		notes.append("анимацией владеет: " + owned)
	else:
		# Мгновенный скилл без жеста: легально (телепорт/порталы = VFX), но
		# проверить глазами стоит — поэтому WARN, а не FAIL.
		verdict = "NO_ANIM"
		notes.append("мгновенный скилл без жеста — VFX или клип?")

	for c in cand_rows:
		if not bool(c["file_exists"]) and not bool(c["no_preview"]):
			notes.append("кандидат «%s»: файла-превью нет (%s)" % [c["clip"], c["path"]])

	return {
		"id": sid,
		"name": str(sk.skill_name),
		"branch": str(sk.branch),
		"archetype": arche,
		"cast_anim": str(sk.cast_anim),
		"next_cast_anim": str(sk.next_cast_anim),
		"stance_loop_anim": str(sk.stance_loop_anim),
		"cast_time": float(sk.cast_time),
		"cast_anim_loop": bool(sk.cast_anim_loop),
		"is_sub_skill": bool(sk.is_sub_skill),
		"clips": clips,
		"candidates": cand_rows,
		"verdict": verdict,
		"notes": notes,
	}

## Какой клип скилл ОБЯЗАН иметь ("" — проверять нечего, решает ветка ниже).
func _required_clip(sk, arche: String) -> String:
	if str(sk.cast_anim) != "":
		return str(sk.cast_anim)
	if arche == "stance":
		return str(sk.stance_loop_anim)
	return ""

func _archetype(sk) -> String:
	if bool(sk.is_sub_skill):
		return "sub"
	# Стойка определяется НЕ только заданной позой: у «Концентрации маны»
	# stance_loop_anim пуст, но stance_sub_skills заданы — это стойка без
	# posture-лупа (дыра геймдизайна), а не мгновенный скилл.
	if str(sk.stance_loop_anim) != "" or not sk.stance_sub_skills.is_empty():
		return "stance"
	if bool(sk.cast_anim_loop):
		return "loop_state"
	if float(sk.cast_time) > 0.0:
		return "channel"
	if str(sk.cast_anim) != "":
		return "one_shot"
	return "instant"

func _in_lib(name: String, lib_names: Dictionary) -> bool:
	# В библиотеке лежат И базовый клип, И <name>_UB (бегущий слой). В данных
	# скилла имя всегда базовое — проверяем оба, иначе ложные MISSING.
	return lib_names.has(name) or lib_names.has(name + "_UB")

# ─────────────────────────── кандидат: файл + библиотека ─────────────────────

func _audit_cand(c: Dictionary, lib_names: Dictionary, by_stem: Dictionary) -> Dictionary:
	var clip := str(c.get("clip", ""))
	var src := str(c.get("src", "mixamo"))
	var path := ""
	var exists := false
	var no_preview := false
	if src == "lib":
		# Клип собран в библиотеку, отдельного файла-превью нет (нейро/UAL-паки).
		no_preview = true
	elif src == "neuro":
		# У нейро-клипов файлы называются local_rotations_xyzw.f32 — имя клипа
		# в пути не встречается. Проверяем САМУ ПАПКУ, а не выдуманный файл.
		var d := NEURO_DIR + clip + "/"
		path = d
		exists = DirAccess.dir_exists_absolute(d)
		no_preview = true
	else:
		path = str(SRC_DIRS.get(src, SRC_DIRS["mixamo"])) + clip + _ext(src)
		exists = FileAccess.file_exists(path)

	# Имя клипа в игре: сам кандидат или манифест по файлу-источнику.
	var game_names: Array = by_stem.get(clip, [])
	var in_lib := _in_lib(clip, lib_names)
	if not in_lib:
		for n in game_names:
			if _in_lib(str(n), lib_names):
				in_lib = true
				break
	return {
		"clip": clip,
		"src": src,
		"v": str(c.get("v", "alt")),
		"path": path,
		"file_exists": exists,
		"no_preview": no_preview,
		"in_lib": in_lib,
		"game_names": game_names,
		"note": str(c.get("note", "")),
	}

func _ext(src: String) -> String:
	return ".glb" if src == "glb" else ".fbx"

# ─────────────────────────── источники правды ───────────────────────────

func _read_json(path: String) -> Dictionary:
	var txt := FileAccess.get_file_as_string(path)
	if txt == "":
		return {}
	var v = JSON.parse_string(txt)
	return v if v is Dictionary else {}

## stem файла-источника манифеста → имена клипов (Flying.fbx → [Wings_Fly]).
func _by_source_stem(manifest: Dictionary) -> Dictionary:
	var out := {}
	for e in manifest.get("entries", []):
		var src := str(e.get("source", ""))
		if not src.begins_with("mixamo://"):
			continue
		var stem := src.trim_prefix("mixamo://").get_file().get_basename()
		if not out.has(stem):
			out[stem] = []
		out[stem].append(str(e.get("name", "")))
	return out

func _cands_by_id(cands: Dictionary) -> Dictionary:
	var out := {}
	for s in cands.get("skills", []):
		out[str(s.get("id", ""))] = s
	return out

## id под-приёма → id стойки-родителя (из stance_sub_skills).
func _sub_parents(skills: Dictionary) -> Dictionary:
	var out := {}
	for pid in skills:
		for sub in skills[pid].stance_sub_skills:
			out[str(sub.get("id", ""))] = str(pid)
	return out

# ─────────────────────────── вывод и гейт ───────────────────────────

func _table_line(r: Dictionary) -> String:
	var clip := str(r["cast_anim"])
	if clip == "":
		clip = str(r["stance_loop_anim"])
	var cok := 0
	var cmiss := 0
	for c in r["candidates"]:
		if bool(c["in_lib"]) or bool(c["file_exists"]):
			cok += 1
		else:
			cmiss += 1
	return "%-19s %-10s %-18s %-11s cands %d/%d  %s" % [
		r["id"], r["archetype"], (clip if clip != "" else "—"),
		r["verdict"], cok, cok + cmiss, "; ".join(r["notes"])]

func _check_row(r: Dictionary) -> void:
	if HOLE.has(str(r["verdict"])):
		fails.append("%s: %s — %s" % [r["id"], r["verdict"], "; ".join(r["notes"])])
	elif str(r["verdict"]) == "NO_ANIM":
		warns.append("%s: анимация не задана — %s" % [r["id"], "; ".join(r["notes"])])
	for c in r["candidates"]:
		if not bool(c["file_exists"]) and not bool(c["no_preview"]):
			fails.append("%s: кандидат %s — нет файла %s" % [r["id"], c["clip"], c["path"]])
