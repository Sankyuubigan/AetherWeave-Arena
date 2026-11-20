extends Node3D
## Q32 мягкий грунт: дюна-патч со следами/проминами. SSOT глубины: Image R8
## → depth_tex шейдера (displacement детерминированный — урок Q31: точки
## SoftBody3D сломаны). Следы Л/П по пройденной дистанции, промин стоя;
## накопление min(1, old+add); 1 ImageTexture.update за тик (64 КБ — дёшево).
## dent_scale компонента и шейдера держать синхронными (0.30).

@export var patch_size := 12.0     # размер патча (м) — маппинг XZ→UV
@export var tex_size := 256        # сторона текстуры глубины
@export var step_gap := 0.5        # дистанция между следами (м)
@export var foot_offset := 0.18    # смещение следа Л/П (м)
@export var foot_sigma_px := 1.8   # радиус следа (px)
@export var stand_sigma_px := 5.0  # радиус промина стоя (px)
@export var foot_amp := 0.45       # глубина следа (доля dent_scale)
@export var stand_amp := 0.22      # прибавка промина за цикл стояния (0.35 с)

var _img: Image
var _tex: ImageTexture
var _mat: ShaderMaterial
var _side := 1.0                   # чередование Л/П
var _dist := 0.0                   # пройдено с последнего следа
var _stand_t := 0.0
var _dirty := false

func _ready() -> void:
	var mi := get_node_or_null("GroundMesh") as MeshInstance3D
	if mi == null:
		push_error("[SOFT-GROUND] нет GroundMesh в префабе")
		set_physics_process(false)
		return
	_mat = mi.material_override as ShaderMaterial
	if _mat == null:
		push_error("[SOFT-GROUND] нет ShaderMaterial на GroundMesh")
		set_physics_process(false)
		return
	_img = Image.create(tex_size, tex_size, false, Image.FORMAT_R8)
	_img.fill(Color(0, 0, 0))
	_tex = ImageTexture.create_from_image(_img)
	_mat.set_shader_parameter("depth_tex", _tex)
	print("[SOFT-GROUND] ready")

func _physics_process(delta: float) -> void:
	var player := get_tree().get_first_node_in_group("player") as CharacterBody3D
	if player != null and player.is_on_floor():
		var local := to_local(player.global_position)
		var half := patch_size * 0.5
		if absf(local.x) <= half and absf(local.z) <= half:
			var v := Vector2(player.velocity.x, player.velocity.z)
			if v.length() > 0.5:
				_dist += v.length() * delta
				_stand_t = 0.0
				if _dist >= step_gap:
					_dist = 0.0
					_side = -_side
					var dir := v.normalized()
					var perp := Vector2(-dir.y, dir.x) * (_side * foot_offset)
					# след чуть позади центра тела (стопа под каблуком)
					var p := Vector2(local.x, local.z) - dir * 0.12 + perp
					_stamp(p, foot_sigma_px, foot_amp)
			else:
				_stand_t += delta
				_dist = 0.0
				if _stand_t >= 0.35:
					_stand_t = 0.0
					_stamp(Vector2(local.x, local.z), stand_sigma_px, stand_amp)
	if _dirty:
		_dirty = false
		_tex.update(_img)

## Гаусс-стемп в текстуру глубины. p — локальные метры XZ (origin патча).
## За границей текстуры пиксели пропускаются (следы у кромки обрезаются —
## там база 0, промин всё равно не виден).
func _stamp(p: Vector2, sigma_px: float, amp: float) -> void:
	var half := patch_size * 0.5
	var cx := (p.x + half) / patch_size * float(tex_size)
	var cy := (p.y + half) / patch_size * float(tex_size)
	var rad := int(ceil(sigma_px * 2.5))
	var s2 := sigma_px * sigma_px
	for dy in range(-rad, rad + 1):
		var py := int(cy) + dy
		if py < 0 or py >= tex_size:
			continue
		for dx in range(-rad, rad + 1):
			var px := int(cx) + dx
			if px < 0 or px >= tex_size:
				continue
			var d2 := float(dx * dx + dy * dy)
			var add := amp * exp(-d2 / (2.0 * s2))
			var old := _img.get_pixel(px, py).r
			var nv := minf(1.0, old + add)
			if nv > old:
				_img.set_pixel(px, py, Color(nv, nv, nv))
				_dirty = true

## Метрика для гейта: сколько пикселей текстуры промято выше порога.
func count_dented_pixels(threshold := 0.02) -> int:
	var data := _img.get_data()
	var n := 0
	for i in range(data.size()):
		if float(data[i]) / 255.0 > threshold:
			n += 1
	return n
