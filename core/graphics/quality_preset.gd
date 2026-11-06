class_name QualityPreset extends Resource

########################
## Quality: стоимость картинки (TDD §14.3, S5). Третья ось графики после Look и Time.
########################
## Quality только РЕЖЕТ дорогое сверху: эффект Look включен, только если его разрешает Quality
## (например, SSAO = Look.ssao_enabled AND Quality.ssao). Сам стиль Quality не меняет.
## Встроенные tier (builtin) строятся кодом, .tres в res://data/graphics/quality/ их переопределяют по id.
## Числа-перечисления хранятся как int (значения enum Godot), смысл в комментариях.

@export var id: StringName
@export var title: String

@export_category("Shadows")
## Размер атласа теней солнца, RenderingServer.directional_shadow_atlas_set_size
@export var dir_shadow_atlas := 2048
## Каскады: 1 (orthogonal), 2 или 4
@export_range(1, 4) var dir_shadow_splits := 1
## Дальность теней солнца. Ограничена размером стола и комнаты: чем меньше, тем выше разрешение на макете
## Дальность теней солнца от камеры, ед. (мир в см: комната 480 × 380, 300 обрезало тень на 3 м от камеры)
@export var dir_shadow_max_distance := 600.0
## RenderingServer.ShadowQuality: 0 hard, 1 soft very low, 2 low, 3 medium, 4 high, 5 ultra
@export_range(0, 5) var soft_shadow_quality := 1
## Атлас теней точечных и spot источников (лампа), Viewport.positional_shadow_atlas_size
@export var positional_shadow_atlas := 2048
## Тень от рассеянного света окна (WindowLight). На Low свет остаётся, но без тени
@export var window_light_shadow := true
## Тени от траков (балласт, шпалы, рельсы, опоры). По умолчанию выключены на всех tier: на макете из сотен траков
## они давали +6 мс на кадр (каждый трак попадал в теневой проход), а тень рельса в атласе размером в пару пикселей.
## Включать осознанно в .tres конкретного tier (например, для high)
@export var track_shadows := false

@export_category("Anti-aliasing")
@export_enum("Off:0", "MSAA 2x:1", "MSAA 4x:2", "MSAA 8x:3") var msaa := 0
@export var fxaa := true

@export_category("Ambient occlusion")
@export var ssao := false
@export var ssao_half_size := true
## RenderingServer.EnvironmentSSAOQuality: 0 very low, 1 low, 2 medium, 3 high, 4 ultra
@export_range(0, 4) var ssao_quality := 1
## SSIL (непрямое освещение в экранном пространстве)
@export var ssil := false

@export_category("Global illumination")
## SDFGI сильно просаживает fps при движении камеры (каскады следуют за камерой). По умолчанию выкл на всех tier.
## Включать только осознанно в .tres (например, для отдельного tier Ultra)
@export var sdfgi := false

@export_category("Contact shadows (Godot 4.8)")
@export var contact_shadows := false

@export_category("Miniature (S8, пока только хранится)")
@export var tilt_shift := false
@export var dof := false

@export_category("Outlines")
## false = только важные контуры (hover, selected, ghost, blocked), без reserve и multi
@export var outlines_all := false

@export_category("Entity lights (ATTN_16)")
## Сколько источников света сущностей (фары, окна, сигналы) горят одновременно. Ближайшие к камере,
## остальные скрыты, их состояние сохраняется. 0 = все выключены
@export var entity_light_max := 8
## Вместо Light3D только светящиеся элементы (LightConfig.glow_*). Дёшево: для Low
@export var entity_light_emissive_only := false

@export_category("Room (S7)")
## 0 дальний LOD, 1 средний, 2 полный
@export var room_detail_lod := 0


static func builtin_ids() -> Array:
	return [&"low", &"medium", &"high"]


static func builtin(_id: StringName) -> QualityPreset:
	match _id:
		&"low":
			return _make(_id, "Low", {
				"dir_shadow_atlas": 2048, "dir_shadow_splits": 1, "dir_shadow_max_distance": 450.0,
				"soft_shadow_quality": 1, "positional_shadow_atlas": 2048, "window_light_shadow": false,
				"msaa": 0, "fxaa": true,
				"ssao": false, "ssil": false, "contact_shadows": false,
				"tilt_shift": false, "dof": false, "outlines_all": false, "room_detail_lod": 0,
				"entity_light_max": 3, "entity_light_emissive_only": true,
			})
		&"medium":
			return _make(_id, "Medium", {
				"dir_shadow_atlas": 4096, "dir_shadow_splits": 2, "dir_shadow_max_distance": 600.0,
				"soft_shadow_quality": 3, "positional_shadow_atlas": 4096,
				"msaa": 1, "fxaa": false,
				"ssao": true, "ssao_half_size": true, "ssao_quality": 1, "ssil": false,
				"contact_shadows": true,
				"tilt_shift": true, "dof": false, "outlines_all": true, "room_detail_lod": 1,
				"entity_light_max": 8,
			})
		&"high":
			return _make(_id, "High", {
				"dir_shadow_atlas": 8192, "dir_shadow_splits": 4, "dir_shadow_max_distance": 700.0,
				"soft_shadow_quality": 4, "positional_shadow_atlas": 4096,
				"msaa": 2, "fxaa": true,
				"ssao": true, "ssao_half_size": false, "ssao_quality": 2, "ssil": true,
				"contact_shadows": true,
				"tilt_shift": true, "dof": true, "outlines_all": true, "room_detail_lod": 2,
				"entity_light_max": 16,
			})
	return null


static func _make(_id: StringName, _title: String, d: Dictionary) -> QualityPreset:
	var p := QualityPreset.new()
	p.id = _id
	p.title = _title
	for k in d:
		p.set(k, d[k])
	return p
