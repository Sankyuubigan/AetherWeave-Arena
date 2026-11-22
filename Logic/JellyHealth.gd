extends Node
## HP-компонент желе (Q49, заказ юзера 22.11.26 «вражеские... их можно
## дамажить, у них есть хп»). Вынесен из JellyMonster (лимит 500 строк).
## Полоска — приём HellEnemyBase._build_hp_bar (SubViewport + Sprite3D billboard).
## Урон приходит через JellyHitbox.take_damage → JellyMonster.take_damage →
## этот компонент. Смерть = сигнал died (желе разлетается и удаляется).

signal died
signal damaged(amount: int)

var max_health := 100
var current_health := 100
var is_dead := false

var _hp_bar: ProgressBar = null
var _sprite: Sprite3D = null

## bar_y — высота полоски над центром желе (купол r2.6+dome ≈ 3.6).
func setup(max_hp: int, bar_y: float) -> void:
	max_health = max_hp
	current_health = max_hp
	var viewport := SubViewport.new()
	viewport.transparent_bg = true
	viewport.size = Vector2(250, 40)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	_hp_bar = ProgressBar.new()
	_hp_bar.set_anchors_preset(Control.PRESET_FULL_RECT)
	_hp_bar.show_percentage = false
	_hp_bar.max_value = max_health
	_hp_bar.value = current_health
	var sb_bg := StyleBoxFlat.new()
	sb_bg.bg_color = Color(0.1, 0.1, 0.1, 0.8)
	var sb_fg := StyleBoxFlat.new()
	sb_fg.bg_color = Color(0.85, 0.25, 0.1, 1.0)
	_hp_bar.add_theme_stylebox_override("background", sb_bg)
	_hp_bar.add_theme_stylebox_override("fill", sb_fg)
	viewport.add_child(_hp_bar)
	_sprite = Sprite3D.new()
	_sprite.texture = viewport.get_texture()
	_sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_sprite.position.y = bar_y
	add_child(_sprite)

func take(amount: int) -> void:
	if is_dead or amount <= 0:
		return
	current_health = maxi(0, current_health - amount)
	if _hp_bar != null:
		_hp_bar.value = current_health
	if current_health <= 0:
		is_dead = true
		if _sprite != null:
			_sprite.visible = false
		died.emit()
	else:
		damaged.emit(amount)
