extends Node
# Профайлер карты (Шаг 4 плана «Апгрейд второй карты»): раз в 2 секунды пишет
# в лог ключевые метрики — FPS, тайминги process/physics, draw calls, память.
# Факты для таблицы до/после берём из консольного лога живой сессии.

var _frames := 0
var _accum := 0.0

func _process(delta: float) -> void:
	_frames += 1
	_accum += delta
	if _accum < 2.0:
		return
	print("[MapProfiler] fps=%.1f proc=%.2fms phys=%.2fms draw_calls=%d prims=%d vram=%.0fMB static=%.0fMB obj=%d" % [
		_frames / _accum,
		Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
		Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0,
		Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME),
		Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0,
		Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0,
		Performance.get_monitor(Performance.OBJECT_COUNT),
	])
	_frames = 0
	_accum = 0.0
