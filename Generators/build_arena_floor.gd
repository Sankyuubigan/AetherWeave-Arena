extends SceneTree
## Пол MainArena (19.11.26, план «Пол — реалистичная поверхность»): BoxMesh
## 50×1×50 в Scenes/arena.tscn был однотонным серым (верб. юзера «пол сплошной
## однородный цвет — исправить»). Вешаем бесшовный forrest_ground_01
## (PolyHaven, CC0, сетка dl.polyhaven.org): альбедо + normal + roughness + AO,
## тайлинг uv1_scale=10 → плитка 5 м на полу 50×50 м.
## Каналы: rough/AO — грейскейл jpg, дефолтные каналы RED (доки BaseMaterial3D),
## texture_repeat=true по умолчанию. Нормаль nor_gl (OpenGL-конвенция Godot).
## Правило: .tscn руками не правим — только генератором (AGENTS.md §1).

const TEX_DIR := "res://Graphics/Environment/Textures/forrest_ground_01/"

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var scene: PackedScene = load("res://Scenes/arena.tscn")
	if scene == null:
		print("AF ОШИБКА: arena.tscn не загрузился")
		quit(1)
		return
	var arena: Node = scene.instantiate()
	var mis := arena.find_children("*", "MeshInstance3D", true, false)
	if mis.is_empty():
		print("AF ОШИБКА: MeshInstance3D пола не найден")
		quit(1)
		return
	var mi := mis[0] as MeshInstance3D

	var mat := StandardMaterial3D.new()
	var diff := load(TEX_DIR + "forrest_ground_01_diff_1k.jpg")
	if diff == null:
		print("AF ОШИБКА: альбедо не загрузилось (нужен --import перед генератором)")
		quit(1)
		return
	mat.albedo_texture = diff
	mat.normal_enabled = true
	mat.normal_texture = load(TEX_DIR + "forrest_ground_01_nor_gl_1k.jpg")
	mat.roughness_texture = load(TEX_DIR + "forrest_ground_01_rough_1k.jpg")
	mat.ao_enabled = true
	mat.ao_texture = load(TEX_DIR + "forrest_ground_01_ao_1k.jpg")
	# 50 м / 10 повторов = плитка 5 м. detail-trip для repeat/каналов — в лог.
	mat.uv1_scale = Vector3(10, 10, 10)
	mi.material_override = mat

	print("AF repeat=%s rough_ch=%d ao_ch=%d uv1=%s" % [
		mat.get("texture_repeat"), mat.roughness_texture_channel,
		mat.ao_texture_channel, mat.uv1_scale])
	for t in [mat.albedo_texture, mat.normal_texture, mat.roughness_texture, mat.ao_texture]:
		print("AF TEX %s [%s]" % [(t as Texture2D).resource_path.get_file(), t.get_class()])

	var packed := PackedScene.new()
	packed.pack(arena)
	var err := ResourceSaver.save(packed, "res://Scenes/arena.tscn")
	print("AF SAVE res://Scenes/arena.tscn: %s" % error_string(err))
	quit(0)
