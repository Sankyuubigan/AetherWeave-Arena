extends SceneTree

## Execute-гейт Шага 4 Q36: пользовательский скилл «снаряд+взрыв», созданный
## полным конвейером Кузницы (JSON → UserSkillDB → SkillDB.register), реально
## бьёт манекен: AoE-эффект наносит урон сразу (intersect_shape → take_damage),
## fireball из spawn_projectile спавнится из пула и летит к цели.
## Запуск headless:
## & "D:\Programs\Godot\Godot_v4.8-beta3\Godot_v4.8-beta3_win64_console.exe" --headless -s res://Generators/probe_skill_forge_execute.gd

const USDB := preload("res://Logic/Skills/UserSkillDB.gd")
const SDB := preload("res://Logic/Skills/SkillDB.gd")
const SER := preload("res://Logic/Skills/SkillSerializer.gd")

const DUMMY_POS := Vector3(0, 1, 6)
const AOE_DAMAGE := 40

var _fails := 0
var _count := 0
var _dummy: Node = null
var _player: Node = null


func _ck(cond: bool, label: String) -> void:
    _count += 1
    if cond:
        print("  PASS: %s" % label)
    else:
        _fails += 1
        print("  FAIL: %s" % label)


func _init() -> void:
    print("=== PROBE SKILL FORGE EXECUTE (Q36 Шаг 4) ===")
    _run()


func _run() -> void:
    var gpath := ProjectSettings.globalize_path(USDB.SAVE_PATH)
    if FileAccess.file_exists(USDB.SAVE_PATH):
        DirAccess.remove_absolute(gpath)

    await process_frame

    # 1. Скилл «снаряд+взрыв» через полный конвейер (как его пишет окно)
    var skill_dict := {
        "id": "user_forge_test",
        "name": "Кузнец-бомба",
        "description": "Тестовый снаряд со взрывом",
        "icon": "💥",
        "price": 3,
        "max_range": 60.0,
        "requires_target": false,
        "target_type": "enemy",
        "cast_anim": "Throw",
        "cast_time": 0.0,
        "cast_hand": "Right",
        "alternate_hands": false,
        "shake": 0.2,
        "effects": [
            {
                "type": "spawn_projectile",
                "scene": "res://Scenes/fireball.tscn",
                "spawn_from_hand": false,
                "spawn_delay": 0.0,
                "offset_y": 1.2,
                "impact_shake": 0.0,
                "impact_sound": "",
                "decal_scale": 1.0,
                "lava_pool": false,
            },
            {
                "type": "aoe",
                "radius": 6.0,
                "damage": AOE_DAMAGE,
                "vfx": "",
            },
        ],
    }
    _ck(USDB.save_skill(skill_dict) == true, "save_skill принял скилл снаряд+взрыв")
    var skill = SER.skill_from_dict(skill_dict)
    _ck(skill != null and skill.effects.size() == 2, "два эффекта прошли сериализацию")
    _ck(SDB.register(skill.id, skill) == true, "register в SkillDB")

    var reg = SDB.get_skills()
    _ck(reg.has("user_forge_test"), "скилл жив в реестре get_skills()")

    # 2. Арена-мини: реальный игрок + реальный манекен (CollisionShape обязателен —
    #    грабля test_bot_cast: цель без коллизии не ловится физзапросами)
    var player_scene = load("res://Scenes/player.tscn")
    var dummy_scene = load("res://Scenes/dummy.tscn")
    _ck(player_scene != null and dummy_scene != null, "player.tscn + dummy.tscn загрузились")
    if player_scene == null or dummy_scene == null:
        _finish()
        return
    _player = player_scene.instantiate()
    root.add_child(_player)
    _player.global_position = Vector3(0, 1, 0)
    _dummy = dummy_scene.instantiate()
    root.add_child(_dummy)
    _dummy.global_position = DUMMY_POS
    await physics_frame
    await physics_frame

    var hp0: int = int(_dummy.current_health)
    _ck(hp0 > AOE_DAMAGE, "манекен жив, HP=%d больше урона AoE=%d" % [hp0, AOE_DAMAGE])

    # 3. Каст: skill.execute с контекстом как из _aim_context (без камеры —
    #    execute эффекты берут из контекста только target_pos/cast_origin/hand)
    var context := {
        "target_pos": DUMMY_POS + Vector3(0, 1.0, 0),
        "hit_normal": Vector3.UP,
        "target_node": _dummy,
        "cast_origin": _player.global_position + Vector3(0, 1.2, 0),
        "hand": "Right",
    }
    skill.execute(_player, context)
    await physics_frame
    await physics_frame

    # 4. AoE: урон пришёл сразу (intersect_shape ловит StaticBody манекена)
    var hp1: int = int(_dummy.current_health)
    _ck(hp1 == hp0 - AOE_DAMAGE, "AoE снял ровно %d HP (%d -> %d)" % [AOE_DAMAGE, hp0, hp1])

    # 5. Fireball: спавн из пула + полёт к манекену
    var proj: Node = null
    for child in root.get_children():
        if child is Node3D and str(child.get("scene_file_path")) == "res://Scenes/fireball.tscn":
            proj = child
    _ck(proj != null, "fireball из user-скилла заспавнен в дереве")
    if proj != null:
        var d0: Vector3 = proj.global_position
        var hit := false
        var moved := false
        for i in 300:  # до 5 с физики
            await physics_frame
            if not is_instance_valid(proj) or not proj.is_inside_tree():
                hit = true  # пул вернул снаряд после попадания
                break
            var d1: Vector3 = proj.global_position
            if d1.distance_to(d0) > 0.5:
                moved = true
            if _dummy.is_inside_tree() and d1.distance_to(DUMMY_POS + Vector3(0, 1, 0)) < 1.2:
                hit = true
                break
        _ck(moved, "fireball летит (позиция сместилась)")
        _ck(hit, "fireball долетел до манекена/исчез из дерева")
        # Дополнительный урон от прямого попадания (если манекен ещё жив)
        var hp2: int = int(_dummy.current_health)
        _ck(hp2 <= hp1, "после полёта HP не выросла (%d <= %d)" % [hp2, hp1])

    # 6. Cleanup — тестовый скилл не должен остаться реальной игре
    SDB.unregister("user_forge_test")
    USDB.delete_skill("user_forge_test")
    DirAccess.remove_absolute(gpath)
    _ck(not SDB.get_skills().has("user_forge_test"), "реестр чист после теста")
    _ck(not FileAccess.file_exists(USDB.SAVE_PATH), "файл user:// удалён")
    _finish()


func _finish() -> void:
    if _fails == 0 and _count > 0:
        print("SKILL FORGE EXECUTE GATE ALL PASS (%d чеков)" % _count)
        quit(0)
    else:
        print("SKILL FORGE EXECUTE GATE FAILED (%d/%d)" % [_fails, _count])
        quit(1)
