extends Area3D

## Q49: слой 8 = хитбоксы желе (Logic/JellyHitbox.gd) — снаряд ловит их
## контактом (Area3D дефолт-маска 1 софтбоди/хитбокс не видел).
## Назначается в _ready: присваивание встроенному свойству в теле класса —
## Parse Error «Unexpected identifier».

const ProjectilePool = preload("res://Logic/Skills/ProjectilePool.gd")
const DecalFrames = preload("res://Graphics/DecalFrames.gd")
const AnimatedDecalComponent = preload("res://Graphics/AnimatedDecalComponent.gd")

@export var speed: float = 20.0
## Урон снаряда — ПОЛЕ (Q38 элитные боты ада): SpawnProjectileEffect умножает
## на context.damage_mult (элита ×2.5). Раньше константа 25 в take_damage.
## BASE_DAMAGE: сброс в pooled_reset — снаряд элиты (62) не «заразит» пул.
const BASE_DAMAGE := 25
@export var damage: int = BASE_DAMAGE
var direction: Vector3 = Vector3.FORWARD

func set_direction(dir: Vector3):
    direction = dir.normalized()

func _ready():
    collision_mask = 1 | 8
    body_entered.connect(_on_body_entered)

func _physics_process(delta):
    global_position += direction * speed * delta

func _on_body_entered(body: Node):
    # Самоподрыв выключен ПО КАСТЕРУ (meta cast_caster от SpawnProjectileEffect,
    # Q38): старый фильтр body.name == "Player" делал fireball ботов вообще
    # безвредным для игрока. Кастер — не обязательно Player (боты/элита тоже
    # кастуют); пул-безопасный set/erase как у impact_sfx.
    if has_meta("cast_caster") and body == get_meta("cast_caster"):
        return

    # Сигнатуры take_damage разнятся: PlayerController — (amount),
    # HealthComponent/HellEnemyBase — (amount, impulse_dir). По фактическому
    # числу аргументов (регресс 8a41311: fireball бота в игрока = SCRIPT ERROR,
    # урон не применялся).
    if body.has_method("take_damage"):
        var _td_args: int = 1
        for m in body.get_method_list():
            if m.name == "take_damage":
                _td_args = m.args.size()
                break
        if _td_args >= 2:
            body.take_damage(damage, direction)
        else:
            body.take_damage(damage)

    # Пятно взрыва на поверхности (аним. декаль 4.8): спавн ДО release —
    # узел ещё в дереве, декаль живёт в current_scene независимо от пула.
    _spawn_scorch()

    # Звук удара (meta от SpawnProjectileEffect, 17.11: взрыв метеора о землю):
    # play_sfx создаёт отдельный плеер AudioManager — release снаряда не глушит.
    # Голое имя autoload не резолвится в -s-смоуках (Identifier not found,
    # одобрено юзером 19.11.26) — берём через /root, runtime-поведение тот же.
    if has_meta("impact_sfx"):
        var am := get_node_or_null("/root/AudioManager")
        if am:
            am.play_sfx(get_meta("impact_sfx"))

    # Тряска камеры при ударе (метеорит и т.п., meta от SpawnProjectileEffect).
    if has_meta("impact_shake"):
        var cs := get_node_or_null("/root/CameraShake")
        if cs:
            cs.add_trauma(get_meta("impact_shake"))

    # Желе-монстр (QUEUE Q25): взрыв дёргает софтбоди. Area3D/CharacterBody
    # софтбоди физически не давят — JellyMonster сам спавнит RigidBody-толкатель
    # и фильтрует далёкие взрывы по дистанции.
    get_tree().call_group("jelly_monster", "jolt_from", global_position)

    ProjectilePool.release(self)

func _spawn_scorch():
    var scene := get_tree().current_scene if get_tree() else null
    if not scene:
        return
    var dir := direction if direction.length_squared() > 0.001 else Vector3.DOWN
    var normal := AnimatedDecalComponent.surface_normal(get_world_3d(), global_position, dir, Vector3.UP)
    # Подпалина (QUEUE Q5, заказ юзера: «подпалины после фаерболов и метеорита»):
    # размер — по метеору (meta decal_scale от SpawnProjectileEffect), живёт 18 с.
    var d_scale := 1.0
    if has_meta("decal_scale"):
        d_scale = float(get_meta("decal_scale"))
    var frames := DecalFrames.explosion_scorch(Color(1.0, 0.45, 0.1))
    var decal := AnimatedDecalComponent.new()
    decal.configure(frames, 12.0, 18.0, 1.6 * d_scale)
    scene.add_child(decal)
    decal.place(global_position, normal)
    # След-лужа лавы (метеор, meta lava_pool): эмиссивная декаль с пульсом
    # прожилок, живёт дольше всех следов — «лужи лавы, оставляющие след».
    if has_meta("lava_pool"):
        var lava := AnimatedDecalComponent.new()
        lava.configure(DecalFrames.lava_puddle(Color(1.0, 0.38, 0.03)), 6.0, 30.0, 2.4 * d_scale, true)
        scene.add_child(lava)
        lava.place(global_position, normal)
        lava.set_emission(4.0)

func pooled_reset():
    direction = Vector3.FORWARD
    # Сброс урона к базе (Q38): пул шарит снаряды между элитой (×2.5 → 62) и
    # обычными кастами — без сброса damage 62 прилип бы к следующим снарядам.
    damage = BASE_DAMAGE
    # Шлейф Trail3D при переиспользовании из пула: старая лента должна
    # исчезнуть, иначе от спавна тянется след прошлого полёта.
    var ribbon := get_node_or_null("TrailRibbon")
    if ribbon and ribbon.has_method("clear"):
        ribbon.clear()
