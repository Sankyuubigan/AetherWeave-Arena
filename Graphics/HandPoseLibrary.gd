class_name HandPoseLibrary
## 5 пресетов поз пальцев (вердикт спеца 23.11.26). Сгиб фаланги в градусах
## [проксимальная, средняя, дистальная]. POINT: указательный разогнут,
## остальные пальцы — как FIST. Применяет HandPoseModifier3D поверх позы;
## вес 1.0 ТОЛЬКО когда активный клип БЕЗ пальцевых треков (нейро/UAL) —
## у Mixamo-клипов пальцы родные, модификатор их не трогает (вес 0).

const FINGERS := ["Thumb", "Index", "Middle", "Ring", "Pinky"]

## пресет → сгиб [prox, mid, dist] в градусах (для всех пальцев, кроме POINT).
const CURLS := {
	"RELAXED": [15.0, 25.0, 15.0],
	"FIST": [80.0, 90.0, 80.0],
	"OPEN_CAST": [5.0, 5.0, 5.0],
	"GRIP": [55.0, 70.0, 55.0],
	"POINT": [80.0, 90.0, 80.0],  # все FIST, кроме указательного (разогнут)
}

## Сгиб (deg) для пальца в пресете. finger = "Thumb"/"Index"/...
static func curl_for(preset: String, finger: String) -> Vector3:
	var c: Array = CURLS.get(preset, CURLS["RELAXED"])
	var v := Vector3(c[0], c[1], c[2])
	if preset == "POINT" and finger == "Index":
		v = Vector3(5.0, 5.0, 5.0)
	return v

## Имя кости фаланги: mixamorig_<Side>Hand<Finger><seg> (seg 1..3).
static func bone_name(side: String, finger: String, seg: int) -> String:
	return "mixamorig_%sHand%s%d" % [side, finger, seg]