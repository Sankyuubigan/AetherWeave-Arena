extends SceneTree

## Q32 гейт (headless): unit-стемп меняет пиксель 0→>0.2; ходьба болванки
## 3 с по дюне → >200 промятых пикселей; Л/П полосы обе с глубиной >0.05.
## EXIT 0/1. physics_frame в -s НЕ эмитится — ждать create_timer (SSOT).

const SG := "res://Graphics/Environment/Props/soft_ground/soft_ground.tscn"

func _init() -> void:
	var wd := create_timer(40.0)
	wd.timeout.connect(func() -> void:
		print("[SG-GATE] WATCHDOG TIMEOUT")
		quit(1))
	await physics_frame
	var sg: Node3D = (load(SG) as PackedScene).instantiate()
	root.add_child(sg)
	await physics_frame
	var failures := 0

	# 1) UNIT-STAMP: один стемп → центральный пиксель > 0.2
	sg._stamp(Vector2(0, 0), 5.0, 0.22)
	var c: float = sg._img.get_pixel(128, 128).r
	var ok1 := c > 0.2
	print("[SG-GATE] unit-stamp center=", c, " -> ", "PASS" if ok1 else "FAIL")
	if not ok1:
		failures += 1
	# чистая карта перед ходьбой
	sg._img.fill(Color(0, 0, 0))
	sg._dirty = false

	# 2) ходьба: капсула + test_walk_body, старт (-4,1.2,0), dir (1,0), 2 м/с
	var body := CharacterBody3D.new()
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.35
	cap.height = 1.7
	cs.shape = cap
	body.add_child(cs)
	body.add_to_group("player")
	body.set_script(load("res://Generators/test_walk_body.gd"))
	body.position = Vector3(-4, 1.2, 0)
	body.move_dir = Vector2(1, 0)
	body.speed = 2.0
	root.add_child(body)
	await create_timer(3.0).timeout
	var n: int = sg.count_dented_pixels(0.02)
	var ok2 := n > 200
	print("[SG-GATE] walk: pos.x=", body.position.x, " pixels=", n, " -> ", "PASS" if ok2 else "FAIL")
	if not ok2:
		failures += 1

	# 3) Л/П полосы: z=+0.18 (py 132-136) и z=-0.18 (py 120-125)
	var max_a := 0.0
	var max_b := 0.0
	for py in range(132, 137):
		for px in range(256):
			max_a = maxf(max_a, sg._img.get_pixel(px, py).r)
	for py in range(120, 126):
		for px in range(256):
			max_b = maxf(max_b, sg._img.get_pixel(px, py).r)
	var ok3 := max_a > 0.05 and max_b > 0.05
	print("[SG-GATE] bands L=", max_a, " R=", max_b, " -> ", "PASS" if ok3 else "FAIL")
	if not ok3:
		failures += 1

	print("[SG-GATE] RESULT: ", "ALL PASS" if failures == 0 else "FAIL %d" % failures)
	quit(0 if failures == 0 else 1)
