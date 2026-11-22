extends StaticBody3D

@export var max_health: int = 100
var current_health: int = 100
var is_dead: bool = false
var is_friendly: bool = false # Флаг для определения фракции

## Баффы Потока Барда (Q16 Шаг 3, инвариант спеца №36): клампы в СЕТТЕРАХ —
## никакой код не может записать значение вне диапазона (Logic-инвариант).
@export var damage_reduction: float = 0.0:
    set(v):
        damage_reduction = clampf(v, 0.0, 0.5)
@export var reflect_ratio: float = 0.0:
    set(v):
        reflect_ratio = clampf(v, 0.0, 0.6)

## Купол Потока Барда (Q16 Шаг 6): Callable-хук по образцу power_provider —
## если вернул true, урон полностью съеден прочностью купола (HP не тронут).
var damage_interceptor: Callable = Callable()

## Отражение урона (Шаги 3/6): слушают BardFlowComponent/VFX (кормит купол).
signal damage_reflected(attacker: Node, reflected_dmg: int, hit_pos: Vector3)

var hp_bar: ProgressBar
var floating_sprite: Sprite3D

func _ready():
    add_to_group("aim_targets") # AIM ASSIST Q29: цель наведения (фракция в is_friendly)
    current_health = max_health
    
    var mesh = get_node_or_null("MeshInstance3D")
    if mesh:
        mesh.position.y = 0.0

    var viewport = SubViewport.new()
    viewport.transparent_bg = true
    viewport.size = Vector2(250, 40)
    viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
    add_child(viewport)
    
    hp_bar = ProgressBar.new()
    hp_bar.set_anchors_preset(Control.PRESET_FULL_RECT)
    hp_bar.show_percentage = true
    hp_bar.max_value = max_health
    hp_bar.value = current_health
    
    var sb_bg = StyleBoxFlat.new()
    sb_bg.bg_color = Color(0.1, 0.1, 0.1, 0.8)
    var sb_fg = StyleBoxFlat.new()
    # Если дружественный, то цвет полоски зеленый
    if is_friendly:
        sb_fg.bg_color = Color(0.2, 0.9, 0.2, 1.0)
    else:
        sb_fg.bg_color = Color(0.9, 0.1, 0.1, 1.0)
        
    hp_bar.add_theme_stylebox_override("background", sb_bg)
    hp_bar.add_theme_stylebox_override("fill", sb_fg)
    viewport.add_child(hp_bar)
    
    floating_sprite = Sprite3D.new()
    floating_sprite.texture = viewport.get_texture()
    floating_sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
    floating_sprite.position.y = 2.5
    add_child(floating_sprite)

func take_damage(amount: int, impulse_dir: Vector3 = Vector3.ZERO, attacker: Node = null, is_reflected: bool = false):
    if is_dead:
        return

    # Боевой музон: любой урон (в нас или от нас) — сигнал MusicDirector
    var md = get_node_or_null("/root/MusicDirector")
    if md:
        md.note_combat()

    # Q16 Шаг 6: купол Потока Барда перехватывает удар ДО потери HP.
    if damage_interceptor.is_valid() \
            and bool(damage_interceptor.call(amount, impulse_dir, attacker, is_reflected)):
        return

    # Q16 Шаг 3: редукция баффов (кламп 0..0.5 в сеттере) — до применения.
    var applied := amount
    if damage_reduction > 0.0:
        applied = int(round(float(amount) * (1.0 - damage_reduction)))

    current_health -= applied

    # Цифры урона: Graphics-автолоад (в -s-смоках его нет — молча пропускаем)
    var dn = get_node_or_null("/root/DamageNumbers")
    if dn:
        dn.spawn_at(global_position + Vector3(0, 2.2, 0), applied, false)

    # Q16 Шаг 3: отражение (Поток Барда). raw (ДО редукции) × reflect_ratio
    # уходит атакующему. is_reflected=true — гард пинг-понга: отражённый урон
    # не отражается обратно (два «борда» не пинг-понгуют). Сигнатуры attackers
    # разнятся (регресс 8a41311) — разбор по числу аргументов метода.
    if reflect_ratio > 0.0 and not is_reflected and attacker != null \
            and not attacker.is_queued_for_deletion() and attacker.has_method("take_damage"):
        var refl := int(round(float(amount) * reflect_ratio))
        var td_args := 1
        for m in attacker.get_method_list():
            if m.name == "take_damage":
                td_args = m.args.size()
                break
        if td_args >= 4:
            attacker.take_damage(refl, impulse_dir, self, true)
        elif td_args >= 2:
            attacker.take_damage(refl, impulse_dir)
        else:
            attacker.take_damage(refl)
        damage_reflected.emit(attacker, refl, global_position + Vector3(0, 2.0, 0))

    if current_health <= 0:
        current_health = 0
        hp_bar.value = current_health
        die(impulse_dir, applied)
    else:
        hp_bar.value = current_health
        
func heal(amount: int):
    if is_dead:
        return
        
    current_health += amount
    if current_health > max_health:
        current_health = max_health

    hp_bar.value = current_health

    # Цифры лечения: зелёные, с плюсом (Graphics-автолоад)
    var dn = get_node_or_null("/root/DamageNumbers")
    if dn:
        dn.spawn_at(global_position + Vector3(0, 2.2, 0), amount, true)

    print("Получено лечение! ХП: ", current_health)

func die(impulse_dir: Vector3 = Vector3.ZERO, amount: int = max_health):
    is_dead = true

    # Рэгдолл-смерть (PhysicalBones3D, заказ юзера 18.11.26): компонент вешается
    # генератором сцены (build_dummy.gd). Отброс ∝ смертельному урону.
    var rag = get_node_or_null("Ragdoll")
    if rag:
        rag.activate(amount, impulse_dir)
    
    var mesh = get_node_or_null("MeshInstance3D")
    if mesh:
        mesh.hide()
    floating_sprite.hide()
    
    var col = get_node_or_null("CollisionShape3D")
    if col:
        col.set_deferred("disabled", true)
        
    await get_tree().create_timer(5.0).timeout
    respawn()

func respawn():
    current_health = max_health
    hp_bar.value = current_health
    is_dead = false
    
    var mesh = get_node_or_null("MeshInstance3D")
    if mesh:
        mesh.show()
    floating_sprite.show()
    
    var col = get_node_or_null("CollisionShape3D")
    if col:
        col.set_deferred("disabled", false)