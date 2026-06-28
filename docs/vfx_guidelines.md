# Руководство по созданию Магических VFX (Godot 4.x)

Этот документ описывает, как ИИ-агенту генерировать "анимешные" и эффектные магические эффекты, используя исключительно встроенные средства Godot 4, не прибегая к сторонним инструментам (типа Effekseer).

## 1. Главный секрет магии (Additive Blending)
Чтобы магия (огонь, лазеры, искры) выглядела как сгусток энергии, а не как пластик, материал должен светиться. 
При создании `StandardMaterial3D` кодом, обязательно включайте эти параметры:
```gdscript
var mat = StandardMaterial3D.new()
mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED # Игнорировать освещение сцены
mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD # Аддитивное смешивание (свечение)
mat.vertex_color_use_as_albedo = true # Позволяет использовать цвет от системы частиц
mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED # Всегда поворачивать к камере
```

## 2. Использование GPUParticles3D для заклинаний
Любая магия строится из частиц. Для генерации кодом мы используем узел `GPUParticles3D`. 
**Важные правила:**
* **Магия, летящая за объектом (Шлейф):** Установить `local_coords = false`. Это заставит частицы оставаться в пространстве, создавая красивый хвост за летящим снарядом.
* **Взрывы и Вспышки (One-Shot):** Установить `one_shot = true` и `explosiveness = 0.9` (или выше). Все частицы вылетят почти одновременно. 
* **Градиенты (Цвет и Жизнь):** Настройка перехода цвета (например, из яркого фиолетового в прозрачный циановый) — ключ к "аниме" стилю.

```gdscript
# Пример настройки градиента кодом:
var gradient = Gradient.new()
gradient.set_point_color(0, Color(0.8, 0.2, 1.0, 1.0)) # Фиолетовый
gradient.set_point_color(1, Color(0.0, 0.8, 1.0, 0.0)) # Бирюзовый + Прозрачный
var grad_tex = GradientTexture1D.new()
grad_tex.gradient = gradient
p_mat.color_ramp = grad_tex
```

## 3. Автоматическое уничтожение частиц (Memory Management)
Вспышки от телепортаций или ударов не должны висеть в памяти. Каждая сцена-вспышка (с `one_shot = true`) должна на корневом узле иметь скрипт, который удаляет её из дерева после завершения анимации:
```gdscript
# Стандартный подход ИИ для очистки сцен:
await get_tree().create_timer(lifetime + 0.2).timeout
queue_free()
```

## 4. Шейдеры (Продвинутый уровень)
Если потребуется сделать щит, ауру или искажение, ИИ должен генерировать строковый код шейдера, создавать `ShaderMaterial` и применять его на 3D-сферу или цилиндр (Mesh Effect):
```gdscript
var shader = Shader.new()
shader.code = """
shader_type spatial;
render_mode unshaded, blend_add;
// Код волновой функции или ауры
"""
```