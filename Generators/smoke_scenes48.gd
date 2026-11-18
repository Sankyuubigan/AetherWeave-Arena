extends SceneTree
# Смоук 4.8: пересобранные снарядные сцены грузятся, трейл на месте.
# 19.11.26: трейл теперь TrailParticles (GPUParticles3D) — старый TrailRibbon
# выпилен при переработке снарядов, из-за старого имени смоук ложно ПРОВАЛИВАЛСЯ.
func _init() -> void:
	var ok := true
	for path in ["res://Scenes/fireball.tscn", "res://Scenes/ball_lightning.tscn", "res://Scenes/heart_projectile.tscn"]:
		var ps: PackedScene = load(path)
		if ps == null:
			print("[Smoke48] FAIL загрузки: ", path)
			ok = false
			continue
		var node := ps.instantiate()
		var trail := node.find_child("TrailParticles", true, false)
		print("[Smoke48] ", path, " -> TrailParticles=", trail != null)
		ok = ok and trail != null
		node.free()
	print("[Smoke48] ИТОГ: ", "OK" if ok else "ПРОВАЛ")
	quit()
