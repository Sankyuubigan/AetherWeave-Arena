extends Node
## Локомоция скиннутого врага: один AnimationPlayer с shared_animations.res
## (те же клипы, что у игрока). Движется — Run, стоит — Idle, кроссфейд 0.2.
## AnimationTree мобу не нужен: FSM пове­дения живёт в HellEnemyBase.

var anim_player: AnimationPlayer
var _moving := false

func _ready() -> void:
	anim_player = get_parent().get_node_or_null("GraphicsWrapper/AnimationPlayer")
	if anim_player == null:
		set_process(false)
		return
	if anim_player.has_animation("Idle"):
		anim_player.play("Idle", 0.2)

func _process(_delta: float) -> void:
	if anim_player == null:
		return
	var body := get_parent()
	var moving_now: bool = Vector2(body.velocity.x, body.velocity.z).length() > 0.3
	if moving_now == _moving:
		return
	_moving = moving_now
	var want := "Run" if _moving else "Idle"
	if anim_player.has_animation(want) and anim_player.current_animation != want:
		anim_player.play(want, 0.2)
