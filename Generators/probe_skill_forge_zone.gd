extends SceneTree

## Зонд Шага 2 Q36 «Кузница скиллов»: зона SkillForge у стола зачарований.
## (1) в MainArena стол имеет ребёнка SkillForge со скриптом; (2) подход
## фейкового «Player» -> подсказка видна; (3) Z открывает /root/SkillForgeWindow
## (мок с duck-typed контрактом — реальный автолоад появится в Шаге 3);
## (4) повторный Z закрывает; (5) уход с открытым окном — авто-закрытие,
## подсказка скрыта. Запуск headless (рендер не нужен):
## & "D:\Programs\Godot\Godot_v4.8-beta3\Godot_v4.8-beta3_win64_console.exe" --headless -s res://Generators/probe_skill_forge_zone.gd

const MOCK := preload("res://Generators/mock_forge_window.gd")

var _fails := 0
var _count := 0


func _ck(cond: bool, label: String) -> void:
    _count += 1
    if cond:
        print("  PASS: %s" % label)
    else:
        _fails += 1
        print("  FAIL: %s" % label)


func _init() -> void:
    print("=== PROBE SKILL FORGE ZONE (Q36 Шаг 2) ===")
    _run()


func _run() -> void:
    var arena = load("res://Scenes/MainArena.tscn").instantiate()
    root.add_child(arena)
    # Имя узла стола = имя корня префаба ("Enchant Table"), не ключ prop_paths.
    var forge = _find_node(arena, "SkillForge")
    _ck(forge != null, "SkillForge в арене (pack сериализовал)")
    if forge == null:
        _finish()
        return
    _ck(forge.get_parent() != null and forge.get_parent().name == "Enchant Table",
        "зона — ребёнок стола (Enchant Table)")
    _ck(forge.get_script() != null
        and str(forge.get_script().resource_path).ends_with("Logic/SkillForge.gd"),
        "скрипт зоны — Logic/SkillForge.gd")

    # Окно-мок на легальном автолоад-пути.
    var mock = MOCK.new()
    mock.name = "SkillForgeWindow"
    root.add_child(mock)

    # Фейковый «Player» (имя важно: зона триггерится по body.name == "Player").
    var player := CharacterBody3D.new()
    player.name = "Player"
    var cs := CollisionShape3D.new()
    var cap := CapsuleShape3D.new()
    cap.radius = 0.4
    cap.height = 1.8
    cs.shape = cap
    cs.position = Vector3(0, 0.9, 0)
    player.add_child(cs)
    player.position = Vector3(20, 1, 20)
    root.add_child(player)
    await _wait(5)
    _ck(forge._prompt.visible == false, "вдали подсказка скрыта")

    # Подход к столу (южная грань, дистанция до центра 1.6 < зоны ~2.7).
    player.position = Vector3(35.5, 1, 33.9)
    await _wait(8)
    _ck(forge._player_near == true, "подход зарегистрирован (body_entered)")
    _ck(forge._prompt.visible == true, "у стола подсказка видна")

    # Z открывает окно.
    _z(true)
    await _wait(3)
    _z(false)
    await _wait(3)
    _ck(mock.open_count == 1, "Z открыл окно")
    _ck(mock.is_open == true, "окно-мок is_open=true")

    # Повторный Z закрывает (release уже был — новый edge).
    _z(true)
    await _wait(3)
    _z(false)
    await _wait(3)
    _ck(mock.close_count == 1, "повторный Z закрыл окно")

    # Уход от стола с открытым окном — авто-закрытие.
    mock.is_open = true
    mock.close_count = 0
    player.position = Vector3(10, 1, 10)
    await _wait(8)
    _ck(mock.close_count == 1, "уход от стола закрыл открытое окно")
    _ck(forge._prompt.visible == false, "уход скрыл подсказку")
    _finish()


func _finish() -> void:
    if _fails == 0 and _count > 0:
        print("SKILL FORGE ZONE GATE ALL PASS (%d чеков)" % _count)
        quit(0)
    else:
        print("SKILL FORGE ZONE GATE FAILED (%d/%d)" % [_fails, _count])
        quit(1)


func _find_node(n: Node, nm: String) -> Node:
    if n.name == nm:
        return n
    for c in n.get_children():
        var r = _find_node(c, nm)
        if r != null:
            return r
    return null


func _wait(n: int) -> void:
    for i in n:
        await physics_frame


func _z(down: bool) -> void:
    var ev := InputEventKey.new()
    ev.keycode = KEY_Z
    ev.physical_keycode = KEY_Z
    ev.pressed = down
    Input.parse_input_event(ev)
