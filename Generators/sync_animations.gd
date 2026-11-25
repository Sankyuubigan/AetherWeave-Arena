extends SceneTree
## Оркестратор пайплайна анимаций (вердикт спеца 23.11.26, Ф3.1).
## Читает Data/animations_manifest.json (ССОТ), репортит статус источников
## (missing mixamo = юзер качает FBX), запускает генераторы цепочки и 3 гейта.
## Запуск: --headless -s res://Generators/sync_animations.gd
## EXIT≠0 при провале гейта/генератора.

const MANIFEST := "res://Data/animations_manifest.json"
var GODOT := OS.get_executable_path()

## [скрипт, описание] — порядок цепочки (retarget → heart → UB).
const GENERATORS := [
	["res://Generators/retarget_ual_anims.gd", "retarget UAL"],
	["res://Generators/retarget_soma_anims.gd", "retarget SOMA"],
	["res://Generators/build_heart_cast.gd", "heart cast"],
	["res://Generators/build_cast_ub.gd", "UB bake"],
]
const GATE := ["res://temp/probe_gates_anim.gd", "3 гейта"]

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var txt := FileAccess.get_file_as_string(MANIFEST)
	if txt == "":
		print("SYNC FAIL: манифест не прочитан ", MANIFEST)
		quit(1)
		return
	var data = JSON.parse_string(txt)
	if typeof(data) != TYPE_DICTIONARY or not data.has("entries"):
		print("SYNC FAIL: битый манифест")
		quit(1)
		return
	var entries: Array = data["entries"]
	var present := 0
	var missing := 0
	for e in entries:
		var src: String = e.get("source", "")
		if src.begins_with("mixamo://"):
			var f := "res://Graphics/Animations/raw/mixamo/" + src.substr(9)
			if FileAccess.file_exists(f):
				present += 1
			else:
				missing += 1
				print("SYNC WARN: missing ", e.get("name", "?"), " → ", src, " (юзер качает)")
		print("  entry ", e.get("name", "?"), " [", src, "] layer=", e.get("layer", "?"))
	print("SYNC manifest: ", entries.size(), " entries, mixamo present=", present, " missing=", missing)
	var failed := 0
	for g in GENERATORS:
		print("SYNC → ", g[1], " ...")
		var code := OS.execute(GODOT, ["--headless", "-s", g[0]])
		if code != 0:
			failed += 1
			print("SYNC FAIL: ", g[1], " EXIT=", code)
	print("SYNC → ", GATE[1], " ...")
	var gcode := OS.execute(GODOT, ["--headless", "-s", GATE[0]])
	if gcode != 0:
		failed += 1
	print("SYNC ", "PASS" if failed == 0 else "FAIL",
			" (generators_failed=%d, entries=%d, mixamo_missing=%d)" % [failed, entries.size(), missing])
	quit(0 if failed == 0 else 1)
