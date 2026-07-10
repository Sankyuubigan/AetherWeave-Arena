extends SceneTree

# СКРИПТ АНАЛИЗА ПОЛИГОНАЖА (Треугольников)
# Запуск: & "путь_к_godot.exe" --headless -s res://Generators/check_polycount.gd

func _init():
    print("\n=========================================================")
    print("      3D MODEL POLYCOUNT SCANNER (Triangle Count)")
    print("=========================================================\n")
    
    # Сканируем основные папки, где могут быть исходники
    scan_dir("res://Graphics/Environment/")
    scan_dir("res://Graphics/PlayerModel/")
    
    print("\n=========================================================")
    print("                     SCAN COMPLETE                       ")
    print("=========================================================\n")
    quit()

func scan_dir(path: String):
    var dir = DirAccess.open(path)
    if not dir:
        return
        
    dir.list_dir_begin()
    var file_name = dir.get_next()
    
    while file_name != "":
        var full_path = path.path_join(file_name)
        
        if dir.current_is_dir():
            # Пропускаем скрытые папки вроде .godot
            if not file_name.begins_with("."):
                scan_dir(full_path)
        else:
            if file_name.ends_with(".glb") or file_name.ends_with(".gltf"):
                check_gltf(full_path)
            elif file_name.ends_with(".fbx"):
                check_fbx(full_path)
                
        file_name = dir.get_next()

func check_gltf(path: String):
    var doc = GLTFDocument.new()
    var state = GLTFState.new()
    if doc.append_from_file(path, state) == OK:
        var root = doc.generate_scene(state)
        if root:
            var count = count_triangles(root)
            print_result(path, count)
            root.queue_free()

func check_fbx(path: String):
    var doc = FBXDocument.new()
    var state = FBXState.new()
    if doc.append_from_file(path, state) == OK:
        var root = doc.generate_scene(state)
        if root:
            var count = count_triangles(root)
            print_result(path, count)
            root.queue_free()

func count_triangles(node: Node) -> int:
    var count = 0
    if node is MeshInstance3D and node.mesh:
        # Функция get_faces() возвращает массив вершин треугольников. 
        # Каждые 3 вершины = 1 треугольник.
        count += node.mesh.get_faces().size() / 3
        
    for child in node.get_children():
        count += count_triangles(child)
        
    return count

func print_result(path: String, count: int):
    var rating = ""
    var color = ""
    
    if count < 5000:
        rating = "[LOW-POLY]   " # Идеально для мобилок и массовки
    elif count < 30000:
        rating = "[GAME-READY]" # Стандарт для инди ПК/Консолей
    elif count < 100000:
        rating = "[HEAVY]      " # Использовать осторожно (герои, боссы)
    else:
        rating = "[CRITICAL]   " # УБИТЬ НЕМЕДЛЕННО (или использовать только для рендера)
        
    # Форматируем строку для красоты
    var formatted_count = str(count)
    while formatted_count.length() < 9:
        formatted_count = " " + formatted_count
    print("%s | Tris: %s | File: %s" % [rating, formatted_count, path])