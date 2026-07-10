extends RefCounted

static func get_modules() -> Array:
	var modules = []
	modules.append(_make_module("floor",     {"N":0,"E":0,"S":0,"W":0}, Color(0.35,0.35,0.35), 0.20))
	modules.append(_make_module("wall_n",    {"N":1,"E":0,"S":0,"W":0}, Color(0.55,0.42,0.30), 0.07))
	modules.append(_make_module("wall_s",    {"N":0,"E":0,"S":1,"W":0}, Color(0.55,0.42,0.30), 0.07))
	modules.append(_make_module("wall_e",    {"N":0,"E":1,"S":0,"W":0}, Color(0.55,0.42,0.30), 0.07))
	modules.append(_make_module("wall_w",    {"N":0,"E":0,"S":0,"W":1}, Color(0.55,0.42,0.30), 0.07))
	modules.append(_make_module("corner_ne", {"N":1,"E":1,"S":0,"W":0}, Color(0.50,0.35,0.25), 0.04))
	modules.append(_make_module("corner_nw", {"N":1,"E":0,"S":0,"W":1}, Color(0.50,0.35,0.25), 0.04))
	modules.append(_make_module("corner_se", {"N":0,"E":1,"S":1,"W":0}, Color(0.50,0.35,0.25), 0.04))
	modules.append(_make_module("corner_sw", {"N":0,"E":0,"S":1,"W":1}, Color(0.50,0.35,0.25), 0.04))
	modules.append(_make_module("door_n",    {"N":2,"E":0,"S":0,"W":0}, Color(0.30,0.25,0.20), 0.03))
	modules.append(_make_module("door_s",    {"N":0,"E":0,"S":2,"W":0}, Color(0.30,0.25,0.20), 0.03))
	modules.append(_make_module("door_e",    {"N":0,"E":2,"S":0,"W":0}, Color(0.30,0.25,0.20), 0.03))
	modules.append(_make_module("door_w",    {"N":0,"E":0,"S":0,"W":2}, Color(0.30,0.25,0.20), 0.03))
	modules.append(_make_module("t_n",       {"N":1,"E":1,"S":0,"W":1}, Color(0.50,0.38,0.28), 0.03))
	modules.append(_make_module("t_s",       {"N":0,"E":1,"S":1,"W":1}, Color(0.50,0.38,0.28), 0.03))
	modules.append(_make_module("t_e",       {"N":1,"E":1,"S":1,"W":0}, Color(0.50,0.38,0.28), 0.03))
	modules.append(_make_module("t_w",       {"N":1,"E":0,"S":1,"W":1}, Color(0.50,0.38,0.28), 0.03))
	modules.append(_make_module("cross",     {"N":1,"E":1,"S":1,"W":1}, Color(0.50,0.38,0.28), 0.01))
	return modules

static func _make_module(id: String, sockets: Dictionary, color: Color, weight: float) -> Dictionary:
	return {"id": id, "sockets": sockets, "color": color, "weight": weight}

static func is_compatible(a: int, b: int) -> bool:
	if a == b:
		return true
	if (a == 0 and b == 2) or (a == 2 and b == 0):
		return true
	return false
