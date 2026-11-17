extends SceneTree
# Бенчмарк пула снарядов (Шаг 3 плана «Хитскан и производительность»).
# Сравнивает прежний жизненный цикл (instantiate + free на каждый выстрел)
# с пулом (acquire + release). Результаты кладутся в отчёт задачи.
#
# Запуск:
# & "D:\Programs\Godot\...\Godot_v4.7-stable_win64_console.exe" --headless -s res://Generators/bench_projectile_pool.gd

const ProjectilePool = preload("res://Logic/Skills/ProjectilePool.gd")

func _init() -> void:
    # Замер — на первом кадре итерации, а не в _init/_initialize: в скриптовом
    # режиме (-s) узлы под корнем не «в дереве» до старта MainLoop, и контракт
    # пула (is_inside_tree) отсекал бы весь прогрев. В реальной игре снаряды
    # живут в current_scene работающего дерева — там контракт выполняется.
    process_frame.connect(_run_bench, CONNECT_ONE_SHOT)

func _run_bench() -> void:
    var scene: PackedScene = load("res://Scenes/fireball.tscn")
    var parent := root
    var cycles := 100
    print("DEBUG scene.resource_path=", scene.resource_path)

    # 1) Прежний цикл: instantiate + add_child + free (queue_free замерён
    #    через free — отложенное удаление короче, что делает сравнение
    #    щадящим к пулу, а не наоборот).
    var t0 := Time.get_ticks_usec()
    for i in cycles:
        var proj = scene.instantiate()
        parent.add_child(proj)
        proj.free()
    var direct_us := Time.get_ticks_usec() - t0

    # 2) Пул: прогрев (создание реального числа снарядов), затем замер
    #    переиспользования — именно это происходит в бою после первых выстрелов.
    var warm: Array = []
    for i in 20:
        warm.append(ProjectilePool.acquire(scene, parent))
    for proj in warm:
        ProjectilePool.release(proj)

    # Диагностика нулевых попаданий: что реально лежит в пуле после прогрева.
    for key in ProjectilePool._pool:
        var stored: Array = ProjectilePool._pool[key]
        print("DEBUG пул[", key, "] size=", stored.size(),
            " valid=", (is_instance_valid(stored[0]) if stored.size() > 0 else "-"),
            " in_tree=", (stored[0].is_inside_tree() if stored.size() > 0 and is_instance_valid(stored[0]) else "-"),
            " scene_file=", (stored[0].scene_file_path if stored.size() > 0 and is_instance_valid(stored[0]) else "-"))

    t0 = Time.get_ticks_usec()
    for i in cycles:
        var proj = ProjectilePool.acquire(scene, parent)
        ProjectilePool.release(proj)
    var pooled_us := Time.get_ticks_usec() - t0

    print("=== Бенчмарк пула снарядов: fireball.tscn, %d циклов ===" % cycles)
    print("Старый цикл (instantiate+free): %d мкс всего, %.1f мкс/выстрел" % [direct_us, direct_us / float(cycles)])
    print("Пул (acquire+release):          %d мкс всего, %.1f мкс/выстрел" % [pooled_us, pooled_us / float(cycles)])
    print("Пул: попаданий=%d промахов=%d (промахи — прогрев, 20 шт.)" % [ProjectilePool.stats_hits, ProjectilePool.stats_misses])
    print("Ускорение: %.1fx" % [(direct_us / float(cycles)) / maxf(pooled_us / float(cycles), 0.001)])
    quit()
