extends Node

## Тряска камеры (19.11.26, верб. юзера: «при падении метеорита или
## использовании Громового раската экран слегка трясло»).
## Autoload: сцены/игрока не трогает — каждый кадр двигает h_offset/v_offset
## ТЕКУЩЕЙ камеры вьюпорта (никем больше не заняты, греп проверил; transform
## и SpringArm не трогаем — не конфликтует с камерой от 3-го лица).
## Trauma-модель (GDC): trauma 0..1, offset = MAX_OFFSET * trauma² * sin,
## затухание линейное. Источники: Skill.shake (момент каста — громовой
## раскат) и SpawnProjectileEffect.impact_shake (удар снаряда — метеорит).

const MAX_OFFSET: float = 0.25   # м, амплитуда при trauma=1
const TRAUMA_SPEED: float = 2.2  # 1/с, затухание

var _trauma: float = 0.0
var _time: float = 0.0

## Добавить встряску: amount 0..1 (0.4 = ощутимо, 0.7 = сильно).
func add_trauma(amount: float) -> void:
	_trauma = clampf(_trauma + amount, 0.0, 1.0)

func _process(delta: float) -> void:
	_time += delta
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	if _trauma <= 0.0:
		# Сброс, чтобы оффсет не залип на последнем кадре тряски.
		if cam.h_offset != 0.0 or cam.v_offset != 0.0:
			cam.h_offset = 0.0
			cam.v_offset = 0.0
		return
	_trauma = maxf(_trauma - TRAUMA_SPEED * delta, 0.0)
	var power := _trauma * _trauma
	cam.h_offset = MAX_OFFSET * power * sin(_time * 47.3)
	cam.v_offset = MAX_OFFSET * power * sin(_time * 53.7)
