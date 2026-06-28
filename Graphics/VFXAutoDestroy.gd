extends Node3D

# Скрипт вешается на корень сцены визуального эффекта (взрыв, телепорт)
# чтобы автоматически удалить его из памяти, когда частицы отыграют.

func _ready():
    var particles = $Burst
    if particles and particles is GPUParticles3D:
        particles.emitting = true
        var delay = particles.lifetime + 0.2
        await get_tree().create_timer(delay).timeout
    else:
        # Fallback, если узла нет
        await get_tree().create_timer(2.0).timeout
        
    queue_free()