extends Node

## Ловец фризов (19.11.26, вердикт юзера: «фриз у валуна по прежнему есть»).
## Зонды (probe_boulder_fps v1–v4) чисты: статика/первый взгляд/старт/аудио —
## все worst < 30ms. Фриз живёт в интерактиве, который зонд не симулирует.
## Этот автолоад ловит его в РЕАЛЬНОЙ сессии: кадр > STALL_MS → строка в
## user://stalls.log (позиция игрока, сцена, DC, VRAM, последние события).
## События вешаются точечно: музыка (switch/combat), телепорт, скилл.
## Стоимость в нормальном кадре — один get_ticks_usec, ничего не пишет.

const STALL_MS := 100.0
const EVENT_KEEP := 12

var _file: FileAccess
var _events: PackedStringArray = []
var _last_us: int = 0
var _warned := 0

func _ready() -> void:
	_last_us = Time.get_ticks_usec()
	_file = FileAccess.open("user://stalls.log", FileAccess.WRITE)
	if _file:
		_file.store_line("=== stalls.log %s ===" % Time.get_datetime_string_from_system())
		_file.flush()
	print("STALL: лог фризов ", ProjectSettings.globalize_path("user://stalls.log"))

## Точечные маркеры из кода (музыка/телепорт/скилл). Дешёвое кольцо на 12.
func event(what: String) -> void:
	_events.append("[%s] %s" % [Time.get_time_string_from_system(), what])
	while _events.size() > EVENT_KEEP:
		_events.remove_at(0)

func _process(_delta: float) -> void:
	var now := Time.get_ticks_usec()
	var ms := (now - _last_us) / 1000.0
	_last_us = now
	if ms < STALL_MS:
		return
	_warned += 1
	var pos := Vector3.ZERO
	var scene := "?"
	var tree := get_tree()
	if tree and tree.current_scene:
		scene = String(tree.current_scene.name)
		var pl: Node = tree.current_scene.get_node_or_null("Player")
		if pl is Node3D:
			pos = (pl as Node3D).global_position
	var dc := RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)
	var vram := RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_VIDEO_MEM_USED)
	var line := "[%s] STALL %.0fms scene=%s pos=%s dc=%d vram=%.0fMB" % [
		Time.get_time_string_from_system(), ms, scene, pos, dc, vram / 1048576.0]
	if not _events.is_empty():
		line += " | " + " ; ".join(_events)
	print(line)
	if _file:
		_file.store_line(line)
		_file.flush()

func _exit_tree() -> void:
	if _file:
		_file.store_line("=== выход, всего стылов: %d ===" % _warned)
		_file.flush()
		_file.close()
