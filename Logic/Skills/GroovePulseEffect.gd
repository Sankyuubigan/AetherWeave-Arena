extends "res://Logic/Skills/Effect.gd"

## «Нота-пуля» (groove_pulse, дефолт ЛКМ стойки «Пульс Битвы», спец 11-ответ):
## быстрый лёгкий снаряд под стрельбу 1 раз в бит (мини-КД 0.25 с в SkillDB).
## В бит летит быстрее, светится золотом и ×1.25 урона; мимо бита — слабый
## «фальшивый» плевок ×0.4 (Блок 2 ТЗ). Вердикт бита кладёт в context
## ["groove_verdict"] SpellCasterComponent._groove_judge; заряд Грува (+18/+10)
## и красивую ноту даёт судья стойки (BardGrooveComponent.evaluate_action).

const ProjectilePool = preload("res://Logic/Skills/ProjectilePool.gd")

@export var projectile_scene_path: String = "res://Scenes/mana_bolt.tscn"
@export var base_damage: int = 14
@export var hit_mult: float = 1.25
@export var miss_mult: float = 0.4
@export var speed_boost: float = 1.6

var _gold_mat: StandardMaterial3D
## Оригинальная скорость сцены: пул шарит узлы между кастами — читаем один
## раз ДО первой модификации, дальше каждый каст перезаписывает честно.
var _base_speed := -1.0

func apply(caster: Node, context: Dictionary) -> void:
    if not ResourceLoader.exists(projectile_scene_path):
        return
    var verdict := str(context.get("groove_verdict", ""))
    var on_beat := verdict == "perfect" or verdict == "good"
    var tree = caster.get_tree()
    var parent = tree.current_scene if tree and tree.current_scene else caster.get_parent()
    if not parent:
        return
    var proj = ProjectilePool.acquire(load(projectile_scene_path), parent)
    # Кастер-мета (Q38): снаряд не бьёт кастера (пул шарит tscn между скиллами).
    proj.set_meta("cast_caster", caster)
    # Урон: база × в-бит множитель × tier-множитель стойки (внутри damage_mult)
    # × stance_power (у groove провайдер плоский 1.0 — не удвоить).
    var dmg := float(base_damage) * (hit_mult if on_beat else miss_mult) \
            * float(context.get("damage_mult", 1.0)) \
            * float(context.get("stance_power", 1.0))
    if "damage" in proj:
        proj.damage = maxi(1, int(round(dmg)))
    # Скорость: в бит быстрее (кеш базы до модификации — пул-безопасность).
    if "speed" in proj:
        if _base_speed <= 0.0:
            _base_speed = float(proj.speed)
        proj.speed = _base_speed * (speed_boost if on_beat else 1.0)
    _tint(proj, on_beat)

    var origin: Vector3 = caster.global_position + Vector3(0, 1.2, 0)
    if context.has("cast_origin"):
        origin = context["cast_origin"]
    proj.global_position = origin
    proj.reset_physics_interpolation()
    var target_pos = context.get("target_pos", proj.global_position + Vector3.FORWARD)
    if proj.has_method("set_direction"):
        proj.set_direction(proj.global_position.direction_to(target_pos))
    # Мимо бита — «фальшивый» глухой звук (ТЗ Блок 2: слабый плевок).
    if not on_beat:
        var groove = caster.get_node_or_null("BardGrooveComponent")
        if groove != null and groove.has_method("play_poly"):
            groove.play_poly("res://Audio/Bard/note_miss.res", -12.0, 0.85)

## В бит — золотой материал-оверрайд; мимо — сброс к материалу сцены.
## Пул-безопасно: ставится заново КАЖДЫЙ каст (паттерн impact_* мет).
func _tint(proj: Node, on_beat: bool) -> void:
    var mi := _first_mesh(proj)
    if mi == null:
        return
    if not on_beat:
        mi.material_override = null
        return
    if _gold_mat == null:
        _gold_mat = StandardMaterial3D.new()
        _gold_mat.albedo_color = Color(1.0, 0.85, 0.25)
        _gold_mat.emission_enabled = true
        _gold_mat.emission = Color(1.0, 0.8, 0.3)
        _gold_mat.emission_energy_multiplier = 2.5
    mi.material_override = _gold_mat

static func _first_mesh(node: Node) -> MeshInstance3D:
    if node is MeshInstance3D:
        return node
    for c in node.get_children():
        var r := _first_mesh(c)
        if r != null:
            return r
    return null
