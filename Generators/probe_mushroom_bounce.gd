extends SceneTree

## Q31 гейт (шаг 4 PRP): глубина промина и высота подброса монотонны по высоте
## сброса, полёт без провала сквозь шляпку. Headless.
## dent читается из mush.dent_current (шейдерный промин компонента —
## SoftBody3D-точки сломаны в 4.x, issues #93847/#108090); полётная высота
## от точки отрыва (vy > 4 = отскок; от y отрыва, не от пола — старт 9 м
## всегда выше apex подброса, ловили «не монотонен» на высоте старта).

const MUSH := "res://Graphics/Environment/Props/mushroom_bounce/mushroom_bounce.tscn"

func _init() -> void:
	await physics_frame
	var mush: Node3D = (load(MUSH) as PackedScene).instantiate()
	root.add_child(mush)
	await physics_frame
	await physics_frame

	var body := CharacterBody3D.new()
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.35
	cap.height = 1.7
	cs.shape = cap
	body.add_child(cs)
	body.add_to_group("player")
	body.set_script(load("res://Generators/test_fall_body.gd"))
	root.add_child(body)
	await physics_frame

	var r3 := await _drop(body, mush, 5.4)   # ~3 м над шляпкой (2.32+3)
	var r9 := await _drop(body, mush, 11.4)  # ~9 м над шляпкой
	print("[BOUNCE] drop3: flight=%.2f dent=%.2f | drop9: flight=%.2f dent=%.2f" %
		[r3.apex, r3.dent, r9.apex, r9.dent])

	var ok := true
	if r3.dent < 0.03:
		print("[BOUNCE] FAIL: промин с 3 м отсутствует (%.3f < 0.03)" % r3.dent); ok = false
	if r3.apex < 2.0:
		print("[BOUNCE] FAIL: подброс с 3 м слаб (%.2f < 2.0)" % r3.apex); ok = false
	if r9.dent <= r3.dent:
		print("[BOUNCE] FAIL: промин не монотонен (%.2f !> %.2f)" % [r9.dent, r3.dent]); ok = false
	if r9.apex <= r3.apex:
		print("[BOUNCE] FAIL: подброс не монотонен (%.2f !> %.2f)" % [r9.apex, r3.apex]); ok = false
	if r9.apex < 3.5:
		print("[BOUNCE] FAIL: подброс с 9 м слаб (%.2f < 3.5)" % r9.apex); ok = false
	if r3.fell_through or r9.fell_through:
		print("[BOUNCE] FAIL: тело провалилось сквозь шляпку"); ok = false
	print("[BOUNCE] GATE: ", "PASS" if ok else "FAIL")
	body.queue_free()
	mush.queue_free()
	quit(0 if ok else 1)

## Один сброс: тело падает на шляпку, компонент батутит; dent = пик
## mush.dent_current (затухает dent_release с — latch держит максимум),
## полётная высота первого отскока. Окно 420 тиков (7 с) — батут бесконечно
## эластичный, стоять не будет.
func _drop(body: CharacterBody3D, mush: Node3D, from_h: float) -> Dictionary:
	body.position = Vector3(0, from_h, 0)
	body.velocity = Vector3.ZERO
	var dent := 0.0
	var fell := false
	var launched := false     # первый отскок пойман
	var launch_y := 0.0
	var apex := 0.0           # макс y ПОСЛЕ отрыва
	var flight := -1.0        # apex - launch_y (вершина достигнута)
	var settle := 0
	for t in range(420):
		await physics_frame
		var p: Vector3 = body.global_position
		var vy: float = body.velocity.y
		dent = maxf(dent, mush.dent_current)
		if vy > 4.0 and not launched:
			launched = true
			launch_y = p.y
			apex = p.y
		if launched:
			if p.y > apex:
				apex = p.y
			if vy <= 0.0 and flight < 0.0:
				flight = apex - launch_y
		if p.y < 0.7:
			fell = true
		if launched and body.velocity.length() < 0.3 and p.y > 1.8:
			settle += 1
			if settle > 8:
				break
		else:
			settle = 0
	if flight < 0.0:
		flight = apex - launch_y  # не долетел до вершины за окно — брать как есть
	print("[BOUNCE]   drop %.1f: flight=%.2f dent=%.3f launched=%s" %
		[from_h, flight, dent, launched])
	return {"apex": flight, "dent": dent, "fell_through": fell}
