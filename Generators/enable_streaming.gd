extends SceneTree

# Включает mip-level texture streaming (Godot 4.8). Фича целиком управляется
# настройками проекта (модуль modules/texture_streaming): текстуры начинают
# подгружаться по мере надобности — VRAM экономится на фотограмметрии.
#
# Запуск:
# & "<движок 4.8>" --headless -s res://Generators/enable_streaming.gd

func _init() -> void:
	ProjectSettings.set_setting("rendering/textures/streaming/enabled", true)
	# Остальные ручки (memory_budget_mb, min_lod/max_lod, max_ops_per_second)
	# оставлены дефолтными — крутить только по факту замеров VRAM.
	var err := ProjectSettings.save()
	print("[Streaming] enabled=true, ProjectSettings.save() -> ", error_string(err))
	quit()
