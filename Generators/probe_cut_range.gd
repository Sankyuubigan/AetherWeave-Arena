extends SceneTree
## Зонд-доказательство (18.11.26): Jump_Launch бит — 6 ключей вместо ~28.
## Гипотеза: track_set_key_time пересортировывает трек → цикл по индексам
## в _cut_from сбивается (ключи дважды сдвигаются/теряются).
## Метод: raw Jump из НЕ добавленного в дерево player.tscn (_ready не гонял
## нормализацию), старый алгоритм vs безопасный (собрать → очистить → вставить).
## Headless: timeout 60 Godot --headless -s res://Generators/probe_cut_range.gd

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var ps = load("res://Scenes/player.tscn")
	if ps == null:
		print("CUT FAIL: нет player.tscn")
		quit(1)
		return
	var player = ps.instantiate()  # НЕ добавляем в дерево — _ready молчит
	var ap: AnimationPlayer = player.get_node("GraphicsWrapper/AnimationPlayer")
	var lib = ap.get_animation_library("")
	var jump: Animation = lib.get_animation("Jump")
	var hips_i := _hips_track(jump)
	print("RAW Jump: tracks=%d Hips keys=%d len=%.2f" % [jump.get_track_count(), jump.track_get_key_count(hips_i), jump.length])

	# Старый алгоритм (копия из PlayerAnimationComponent._cut_from/_cut_range)
	var old := _cut_range_old(jump, 0.33, 0.75)
	var oi := _hips_track(old)
	var s := PackedStringArray()
	for k in old.track_get_key_count(oi):
		var v: Vector3 = old.track_get_key_value(oi, k)
		s.append("%.2f:%.2f" % [old.track_get_key_time(oi, k), v.y])
	print("OLD _cut_range (%d Hips keys, len=%.2f): %s" % [old.track_get_key_count(oi), old.length, " ".join(s)])

	# Безопасный алгоритм: collect-then-rebuild
	var safe := _cut_range_safe(jump, 0.33, 0.75)
	var si := _hips_track(safe)
	var s2 := PackedStringArray()
	for k in safe.track_get_key_count(si):
		var v: Vector3 = safe.track_get_key_value(si, k)
		s2.append("%.2f:%.2f" % [safe.track_get_key_time(si, k), v.y])
	print("SAFE _cut_range (%d Hips keys, len=%.2f): %s" % [safe.track_get_key_count(si), safe.length, " ".join(s2)])
	quit(0)

func _hips_track(a: Animation) -> int:
	for i in a.get_track_count():
		if String(a.track_get_path(i)).contains("Hips") and a.track_get_type(i) == Animation.TYPE_POSITION_3D:
			return i
	return 0

## Дословная копия текущего _cut_from + _cut_range (для сравнения)
func _cut_from_old(src: Animation, off: float) -> Animation:
	var a: Animation = src.duplicate(true)
	for i in a.get_track_count():
		for k in range(a.track_get_key_count(i) - 1, -1, -1):
			if a.track_get_key_time(i, k) < off:
				a.track_remove_key(i, k)
			else:
				a.track_set_key_time(i, k, a.track_get_key_time(i, k) - off)
	a.length = maxf(a.length - off, 0.01)
	return a

func _cut_range_old(src: Animation, start: float, end: float) -> Animation:
	var a := _cut_from_old(src, start)
	var seg := minf(end, src.length) - start
	for i in a.get_track_count():
		for k in range(a.track_get_key_count(i) - 1, -1, -1):
			if a.track_get_key_time(i, k) > seg:
				a.track_remove_key(i, k)
	a.length = maxf(seg, 0.01)
	return a

## Кандидат фикса: времена/значения собираются ДО изменений, ключи
## вставляются после полной очистки трека (порядок отсортирован заранее)
func _cut_from_safe(src: Animation, off: float) -> Animation:
	var a: Animation = src.duplicate(true)
	for i in a.get_track_count():
		var times: Array = []
		var payloads: Array = []
		for k in a.track_get_key_count(i):
			var t: float = a.track_get_key_time(i, k)
			if t < off:
				continue
			times.append(t - off)
			payloads.append([a.track_get_key_value(i, k), a.track_get_key_transition(i, k)])
		for k in range(a.track_get_key_count(i) - 1, -1, -1):
			a.track_remove_key(i, k)
		for j in times.size():
			a.track_insert_key(i, times[j], payloads[j][0], payloads[j][1])
	a.length = maxf(a.length - off, 0.01)
	return a

func _cut_range_safe(src: Animation, start: float, end: float) -> Animation:
	var a := _cut_from_safe(src, start)
	var seg := minf(end, src.length) - start
	for i in a.get_track_count():
		for k in range(a.track_get_key_count(i) - 1, -1, -1):
			if a.track_get_key_time(i, k) > seg:
				a.track_remove_key(i, k)
	a.length = maxf(seg, 0.01)
	return a
