extends RefCounted

class Cell:
	var x: int
	var z: int
	var possibilities: Array
	var collapsed: bool = false
	var chosen: int = -1

	func entropy() -> int:
		return possibilities.size()

var grid_width: int
var grid_depth: int
var modules: Array
var cells: Array

func _init(w: int, d: int, mods: Array):
	grid_width = w
	grid_depth = d
	modules = mods
	_init_cells()

func _init_cells():
	cells = []
	for z in grid_depth:
		var row = []
		for x in grid_width:
			var c = Cell.new()
			c.x = x
			c.z = z
			c.possibilities = range(modules.size())
			row.append(c)
		cells.append(row)

func collapse() -> Dictionary:
	while true:
		var cell = _find_lowest_entropy()
		if cell == null:
			return {success=true, grid=_extract_grid()}
		if cell.possibilities.is_empty():
			return {success=false, grid=[]}
		_observe(cell)
		if not _propagate(cell):
			return {success=false, grid=[]}
	return {success=false, grid=[]}

func _find_lowest_entropy() -> Cell:
	var min_ent = 999
	var candidates = []
	for z in grid_depth:
		for x in grid_width:
			var c = cells[z][x]
			if c.collapsed:
				continue
			var e = c.entropy()
			if e < min_ent:
				min_ent = e
				candidates = [c]
			elif e == min_ent:
				candidates.append(c)
	if candidates.is_empty():
		return null
	return candidates[randi() % candidates.size()]

func _observe(cell: Cell):
	var total_weight = 0.0
	for idx in cell.possibilities:
		total_weight += modules[idx].weight
	var roll = randf() * total_weight
	var cumulative = 0.0
	var chosen = cell.possibilities[-1]
	for idx in cell.possibilities:
		cumulative += modules[idx].weight
		if roll <= cumulative:
			chosen = idx
			break
	cell.possibilities = [chosen]
	cell.chosen = chosen
	cell.collapsed = true

func _propagate(from: Cell) -> bool:
	var stack = [from]
	while not stack.is_empty():
		var current = stack.pop_back()
		var neighbors = _get_neighbors(current)
		for nb in neighbors:
			if nb.cell.collapsed:
				continue
			var compatible = _get_compatible(nb, current)
			if compatible.size() < nb.cell.possibilities.size():
				if compatible.is_empty():
					return false
				nb.cell.possibilities = compatible
				stack.append(nb.cell)
	return true

func _get_neighbors(cell: Cell) -> Array:
	var result = []
	var dirs = [
		{dx=0, dz=-1, side="N", opp="S"}, # северный сосед
		{dx=0, dz=1,  side="S", opp="N"}, # южный сосед
		{dx=1, dz=0,  side="E", opp="W"}, # восточный сосед
		{dx=-1, dz=0, side="W", opp="E"}, # западный сосед
	]
	for d in dirs:
		var nx = cell.x + d.dx
		var nz = cell.z + d.dz
		if nx >= 0 and nx < grid_width and nz >= 0 and nz < grid_depth:
			result.append({
				cell=cells[nz][nx],
				my_side=d.side,
				nb_side=d.opp
			})
	return result

func _get_compatible(nb: Dictionary, current: Cell) -> Array:
	var result = []
	var my_side = nb.my_side
	var nb_side = nb.nb_side
	for nb_idx in nb.cell.possibilities:
		var can_place = false
		for cur_idx in current.possibilities:
			var cur_mod = modules[cur_idx]
			var nb_mod = modules[nb_idx]
			if _socket_compatible(cur_mod.sockets[my_side], nb_mod.sockets[nb_side]):
				can_place = true
				break
		if can_place:
			result.append(nb_idx)
	return result

func _extract_grid() -> Array:
	var result = []
	for z in grid_depth:
		var row = []
		for x in grid_width:
			row.append(cells[z][x].chosen)
		result.append(row)
	return result

static func _socket_compatible(a: int, b: int) -> bool:
	if a == b:
		return true
	if (a == 0 and b == 2) or (a == 2 and b == 0):
		return true
	return false
