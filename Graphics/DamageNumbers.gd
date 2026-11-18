extends Node

## Цифры урона/лечения (фишка из демо 3d/labels_and_texts): Label3D над жертвой —
## billboard с обводкой, всплеск-скейл на импакте, подъём и фейд.
## Автозагрузка (/root/DamageNumbers): Logic (HealthComponent) только сообщает
## событие, рисует Graphics — правило потока данных из docs/tech_stack.md.
## В -s-смоках автолоадов нет — вызовы через /root молча пропускаются.
## Кэп на живые цифры: спам AoE не должен взрывать drawcalls.

const MAX_ALIVE := 64
const RISE_TIME := 0.85
const RISE_HEIGHT := 1.3
const LIFETIME := 1.1

var _alive: int = 0

func spawn_at(pos: Vector3, amount: int, is_heal: bool) -> void:
    var scene := get_tree().current_scene
    if scene == null or _alive >= MAX_ALIVE:
        return
    _alive += 1

    var label := Label3D.new()
    label.text = ("+%d" % amount) if is_heal else str(amount)
    label.modulate = Color(0.35, 1.0, 0.45) if is_heal else Color(1.0, 0.62, 0.12)
    label.outline_modulate = Color(0.05, 0.02, 0.0, 0.92)
    label.font_size = 72
    label.pixel_size = 0.008
    label.outline_size = 24
    label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
    label.no_depth_test = true
    label.fixed_size = false
    scene.add_child(label)
    label.global_position = pos + Vector3(randf_range(-0.3, 0.3), 0.15, randf_range(-0.3, 0.3))

    # Всплеск-скейл (импакт) → параллельно подъём и отложенный фейд → free.
    label.scale = Vector3.ONE * 0.5
    var tw := label.create_tween()
    tw.tween_property(label, "scale", Vector3.ONE, 0.12) \
            .set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
    tw.set_parallel(true)
    tw.tween_property(label, "global_position:y", label.global_position.y + RISE_HEIGHT, RISE_TIME) \
            .set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
    tw.tween_property(label, "modulate:a", 0.0, LIFETIME - RISE_TIME * 0.5) \
            .set_delay(RISE_TIME * 0.5).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
    tw.chain().tween_callback(_on_done.bind(label))

func _on_done(label: Label3D) -> void:
    _alive -= 1
    if is_instance_valid(label):
        label.queue_free()
