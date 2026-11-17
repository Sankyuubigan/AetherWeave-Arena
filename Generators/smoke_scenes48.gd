extends SceneTree
# Смоук 4.8: пересобранные снарядные сцены грузятся, TrailRibbon на месте.
func _init() -> void:
	var ok := true
	for path in ["res://Scenes/fireball.tscn", "res://Scenes/ball_lightning.tscn", "res://Scenes/heart_projectile.tscn"]:
		var ps: PackedScene = load(path)
		if ps == null:
			print("[Smoke48] FAIL загрузки: ", path)
			ok = false
			continue
		var node := ps.instantiate()
		var ribbon := node.find_child("TrailRibbon", true, false)
		print("[Smoke48] ", path, " -> Ribbon=", ribbon != null)
		ok = ok and ribbon != null
		node.free()
	print("[Smoke48] ИТОГ: ", "OK" if ok else "ПРОВАЛ")
	quit()
