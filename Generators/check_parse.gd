extends SceneTree
## ГЕЙТ: все скрипты проекта ПАРСЯТСЯ (грузятся и компилируются).
##
## Зачем: после правки нескольких файлов разом ошибка парсинга в одном из них
## обнаруживается только при запуске игры — юзер видит «игра не стартует» без
## причины. Этот гейт ловит такое ДО передачи.
##
## ВАЖНО: список файлов НЕ хардкодится — обход дерева. Хардкод-версия
## (parse_check_r3.gd) не видит новые файлы, то есть защищает только от
## регресса в старых (осознанное решение 27.11.26: один гейт, обход дерева).
##
## Запуск: --headless -s res://Generators/check_parse.gd
## EXIT: 0 — все ОК; 1 — есть провалы (список в stdout).

const ROOTS := ["res://Logic", "res://Graphics", "res://Generators"]
const SKIP_PREFIX := ["res://Generators/_tmp_"]

func _init() -> void:
	var files: Array[String] = []
	for r in ROOTS:
		_collect(r, files)
	files.sort()
	var bad: Array[String] = []
	for f in files:
		var s = load(f)
		if s == null:
			bad.append("%s — НЕ ЗАГРУЖАЕТСЯ" % f)
		elif s is GDScript and not s.can_instantiate():
			# can_instantiate() == false означает ошибку компиляции (не парсинга):
			# скрипт прочитан, но не скомпилирован.
			bad.append("%s — НЕ КОМПИЛИРУЕТСЯ" % f)
	print("=== проверено скриптов: %d ===" % files.size())
	if bad.is_empty():
		print("PARSE: ALL PASS")
		quit(0)
	else:
		for b in bad:
			print("PARSE FAIL: ", b)
		quit(1)

func _collect(dir_path: String, out: Array[String]) -> void:
	var d := DirAccess.open(dir_path)
	if d == null:
		return
	d.list_dir_begin()
	var name := d.get_next()
	while name != "":
		if name.begins_with("."):
			name = d.get_next()
			continue
		var full := dir_path.path_join(name)
		if d.current_is_dir():
			_collect(full, out)
		elif name.ends_with(".gd"):
			var skip := false
			for p in SKIP_PREFIX:
				if full.begins_with(p):
					skip = true
					break
			if not skip:
				out.append(full)
		name = d.get_next()
	d.list_dir_end()
