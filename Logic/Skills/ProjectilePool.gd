extends RefCounted
# Пул снарядов (Шаг 3 плана «Хитскан и производительность»).
#
# Прежний жизненный цикл снаряда — instantiate() на выстрел и queue_free() на
# попадание: постоянные аллокации узлов, коллизий и частиц при спаме скиллов.
# Пул прячет отработавший снаряд и возвращает его при следующем выстреле.
#
# ## Почему снаряды НЕ переезжают между родителями
# Снаряд живёт там, где его заспавнили (обычно current_scene), позиция —
# глобальная, поэтому переиспользование не требует reparent: acquire только
# «оживляет» узел. Смена сцены убивает спрятанные снаряды вместе со сценой —
# acquire чистит мёртвые ссылки, это штатный путь, а не утечка.
#
# ## Контракт со скриптами снарядов
# - release() обязана быть безопасна из body_entered (физ-флеш): прямые
#   изменения monitoring/disabled только через set_deferred, видимость и
#   _physics_process можно сразу.
# - Скрипт снаряда реализует pooled_reset() — сброс полёта (направление,
#   цель, таймеры, масштаб): _ready при переиспользовании НЕ вызывается.

static var _pool: Dictionary = {}
static var stats_hits: int = 0
static var stats_misses: int = 0

## Вернуть готовый к полёту снаряд: из пула или новый из сцены.
static func acquire(scene: PackedScene, parent: Node) -> Node3D:
    var key := scene.resource_path
    var proj: Node3D = null
    var remaining: Array = []
    if not key.is_empty() and _pool.has(key):
        for candidate in _pool[key]:
            # Смена сцены убила узел или узел уже не в дереве — пропускаем.
            if proj == null and is_instance_valid(candidate) and candidate.is_inside_tree():
                proj = candidate
            elif is_instance_valid(candidate) and candidate.is_inside_tree():
                remaining.append(candidate)
        _pool[key] = remaining
    if proj == null:
        proj = scene.instantiate()
        parent.add_child(proj)
        stats_misses += 1
        print("[Pool] новый снаряд: ", key, " | создано за сессию: ", stats_misses)
    else:
        stats_hits += 1
        _wake(proj)
    return proj

## Спрятать снаряд и вернуть в пул. Безопасно вызывать из body_entered.
static func release(proj: Node3D) -> void:
    if not is_instance_valid(proj):
        return
    # Встроенные сцены без файла не имеют ключа — пулить нельзя, честно удаляем.
    var key := proj.scene_file_path
    if key.is_empty():
        proj.queue_free()
        return
    proj.visible = false
    proj.set_physics_process(false)
    if proj is Area3D:
        proj.set_deferred("monitoring", false)
        proj.set_deferred("monitorable", false)
    _disable_shapes(proj, true)
    if proj.has_method("pooled_reset"):
        proj.pooled_reset()
    if not _pool.has(key):
        _pool[key] = []
    _pool[key].append(proj)

func _init() -> void:
    # Утилитарный класс: все методы статические, инстансы не создаются.
    push_warning("ProjectilePool — статический класс, инстанс не нужен")

static func _wake(proj: Node3D) -> void:
    proj.visible = true
    proj.set_physics_process(true)
    if proj is Area3D:
        proj.set_deferred("monitoring", true)
        proj.set_deferred("monitorable", true)
    _disable_shapes(proj, false)

static func _disable_shapes(root: Node, disabled: bool) -> void:
    for shape in root.find_children("*", "CollisionShape3D", true, false):
        shape.set_deferred("disabled", disabled)
