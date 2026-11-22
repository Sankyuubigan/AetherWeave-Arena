extends "res://Logic/Skills/Effect.gd"

## Под-приём «Ударный Аккорд» (Q16, ПКМ в Потоке): звучит АККОРД — три
## разные ноты пентатоники одновременно (плейтест 22.11.26: у аккорда был
## только AoE-урон, звука не было вовсе). Сам урон — AoeDamageEffect рядом
## в сборке скилла; суть ритм-пресса та же, что у нот (BardNoteEffect).

func apply(caster: Node, _context: Dictionary) -> void:
	var flow = caster.get_node_or_null("BardFlowComponent")
	if flow != null and flow.has_method("play_chord"):
		flow.play_chord(0.0)
