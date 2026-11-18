# Tech Stack and Architecture Rules

## 1. Базовые технологии
* **Движок:** Godot Engine 4.x.
* **Язык:** GDScript (исключительно).

## 2. Разделение кода (Separation of Concerns)
Проект строго разделен на две логические части. В структуре папок это должно быть явно видно (условно `res://Logic/` и `res://Graphics/`).
* **Logic / Network (Серверная часть):** 
  Здесь живет математика, физика, таймеры, здоровье, позиции. Эта часть НИКАК не привязана к 3D-моделям, партиклам или UI. Она может работать в Headless-режиме (без монитора).
* **Graphics / UI (Клиентская часть):**
  Здесь живут анимации, звуки, эффекты магии, интерфейс. 
* **ГЛАВНОЕ ПРАВИЛО ПОТОКА ДАННЫХ:** Никогда не разрешайте `Graphics` напрямую менять здоровье, статы или позицию. Графика может ТОЛЬКО считывать данные из `Logic` (или слушать ее сигналы) и отрисовывать их. Ввод от игрока идет в `Logic`, а `Logic` уже дает команду `Graphics` на анимацию.

## 3. Архитектура: Микромодульная (Component-Based)
Каждый объект (Игрок, Враг) — это пустой `Root Node`, состоящий из микро-модулей (независимых скриптов).
Примеры модулей в папке Logic: `HealthComponent`, `MovementComponent`, `NetworkTransformComponent`.
Примеры модулей в папке Graphics: `AnimationComponent`, `VFXComponent`.
Модули общаются исключительно через **Сигналы** (Signals), чтобы не ломать игру при удалении одной из фич.

## 4. Система Навыков и Умений (Data-Driven Composition)
Вся магия и умения в игре строятся по принципу "Композиции" (детальки Лего) без жесткого наследования и хардкода. Мы не пишем отдельный скрипт для каждого скилла.
👉 Подробная инструкция и правила создания умений описаны здесь: **[docs/skill_system.md](skill_system.md)**

## 5. Референсы: godot-demo-projects (источник идей)
Официальные демо Godot — источник проверенных приёмов (ссылки добавлены юзером 18.11.26):
* **Audio:** [godot-demo-projects/audio](https://github.com/godotengine/godot-demo-projects/tree/master/audio)
* **3D:** [godot-demo-projects/3d](https://github.com/godotengine/godot-demo-projects/tree/master/3d)

### Уже взятое в проект (18.11.26)
* `bpm_sync` → MusicDirector: старт боевого лупа на границе такта, формула стабильной позиции playback.
* `spectrum` → MusicSpectrum (автолоад F4): FFT-спектр на шину Music.
* `generator` → процедурный синтез SFX (build_laser_sfx, нейро-луки в SkillDB).
* `audio_effects` → шины Music/SFX + Limiter на Master (AudioManager).
* `ragdoll_physics` → RagdollCorpse/RagdollComponent: PhysicalBone3D под Skeleton3D/PhysicalBoneSimulator3D, ConeTwist.
* `ik` → CastIKComponent (SkeletonIK3D в 4.8-beta не работает → ручная 2-bone IK поверх клипов).
* `navigation` + `waypoints` → HellEnemyBase: патруль-FSM + NavigationAgent3D-преследование, навмеш-бейк.
* `physics_interpolation` → project setting + reset_physics_interpolation (телепорты/снаряды).
* `visibility_ranges` → build_env_prop + скаттер чанков (visibility_range на инстансы/чанки).
* `volumetric_fog` + `tonemap_color_correction` → MainArena/ProceduralArena (fog + FILMIC).
* `decals` → setting rendering/textures/decals/filter=5 (выручает для будущих текстурных декалей).
* `labels_and_texts` → DamageNumbers на Label3D.
* `rhythm_game` → ЗАПЛАНИРОВАНО под умения барда (заказ юзера 18.11.26): окна нажатий
  в бит поверх кастуемой мелодии; берём техприёмы демо — синхронизация input↔audio
  (стабильная позиция playback, как в MusicDirector) и 1€-фильтр гладкости нот.

### Осознанно НЕ взято (нет геймплейной нужды / ниша)
* audio: `device_changer`, `mic_record`, `midi_piano`, `text_to_speech` — девайсы/микрофон/MIDI/TTS.
* 3d: `global_illumination` (SDFGI — дорого, у нас прямой свет + SSAO), `sky_shaders`, `occlusion_culling_mesh_lod` (FPS 190+ без него), `variable_rate_shading`, `antialiasing` (пресеты AA), `procedural_materials`, `material_testers`, `soft_body_physics`, `voxel`, `csg`, `sprites`, `rigidbody_character`, `platformer`, `squash_the_creeps`, `truck_town`, `physics_tests` (свой тест-раннер), `navigation_mesh_chunks` (вариант при росте мира >200×200), `physical_light_camera_units` (арт уже настроен), `kinematic_character` (свой PlayerController старше).
* Возврат к списку — только при новой задаче (напр. GI для финального арта, чанковый навмеш для большой карты).
