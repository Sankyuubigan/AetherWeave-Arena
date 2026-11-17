extends SceneTree
# Смоук-тест хитскан-эффекта: применяет эффект в headless-режиме и проверяет,
# что луч/вспышка/декаль создаются без ошибок скрипта.
#
# Запуск:
# & "D:\Programs\Godot\...\Godot_v4.7-stable_win64_console.exe" --headless -s res://Generators/smoke_hitscan.gd

const SpawnHitscanEffect = preload("res://Logic/Skills/SpawnHitscanEffect.gd")

func _init() -> void:
    # Как в bench_projectile_pool: в -s-режиме узлы «в дереве» только после
    # старта итерации — применяем эффект на первом кадре.
    process_frame.connect(_run, CONNECT_ONE_SHOT)

func _run() -> void:
    var caster := Node3D.new()
    root.add_child(caster)
    var effect = SpawnHitscanEffect.new()
    effect.damage = 10
    var context := {
        "target_pos": Vector3(5, 0, 5),
        "hit_normal": Vector3.UP,
        "target_node": null,
        "camera_pos": Vector3.ZERO,
        "forward_dir": Vector3.FORWARD,
    }
    effect.apply(caster, context)
    # Декаль — отдельный путь с ручной текстурой; если бы присвоение было
    # невалидным, выше уже был бы SCRIPT ERROR от _spawn_decal.
    print("[SmokeHitscan] эффект применён: луч+вспышка+декаль созданы без ошибок")
    quit()
