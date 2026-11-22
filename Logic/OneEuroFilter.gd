extends RefCounted

## 1€-фильтр (adaptive low-pass, Casiez 2012): сглаживает время ритма для
## визуала нот (Q16 Шаг 4) — без заметного лага на быстрых изменениях.

var _min_cutoff := 1.0
var _beta := 0.007
var _d_cutoff := 1.0
var _x_prev := 0.0
var _dx_prev := 0.0
var _has_state := false

func _init(min_cutoff: float = 1.0, beta: float = 0.007, d_cutoff: float = 1.0) -> void:
	_min_cutoff = maxf(min_cutoff, 0.001)
	_beta = beta
	_d_cutoff = maxf(d_cutoff, 0.001)

func _alpha(cutoff: float, dt: float) -> float:
	var tau := 1.0 / (TAU * cutoff)
	return 1.0 / (1.0 + tau / dt)

func filter(x: float, dt: float) -> float:
	if not _has_state:
		_has_state = true
		_x_prev = x
		_dx_prev = 0.0
		return x
	var dx := (x - _x_prev) / dt
	var edx := _dx_prev + _alpha(_d_cutoff, dt) * (dx - _dx_prev)
	var cutoff := _min_cutoff + _beta * absf(edx)
	var xh := _x_prev + _alpha(cutoff, dt) * (x - _x_prev)
	_x_prev = xh
	_dx_prev = edx
	return xh
