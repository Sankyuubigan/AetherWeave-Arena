extends "res://Logic/Skills/Effect.gd"

## Под-приём «Ноты Гармонии» (Q16 Шаг 6, ЛКМ в Потоке): звучит случайная
## нота пентатоники в полифонию Потока Барда. Урона не наносит: суть приёма
## — ритм-пресс (StanceComponent.try_handle_slot → RhythmJudge.submit_press)
## и вердикт судьи, кормящий топливо/барьер/tier в BardFlowComponent.

func apply(caster: Node, _context: Dictionary) -> void:
	var flow = caster.get_node_or_null("BardFlowComponent")
	if flow != null and flow.has_method("play_random_note"):
		flow.play_random_note(0.0)
