extends Node

## Фикстура зонда probe_skill_forge_zone: мок окна Кузницы с тем же
## duck-typed контрактом (is_open/open/close), что у SkillForgeWindow (Шаг 3).

var is_open := false
var open_count := 0
var close_count := 0


func open() -> void:
	is_open = true
	open_count += 1


func close() -> void:
	is_open = false
	close_count += 1
