class_name TimeOfDayPreset extends Resource

########################
## Time: время суток (TDD §14.3, S4). Вторая ось графики после Look.
########################
## Задает солнце (угол, цвет, энергия), тон ambient и фона, небо в окне и лампу.
## Итог = Look (база) * Time (модификатор): ambient_color Look умножается на ambient_tint и т.д.
## Углы солнца подобраны так, чтобы луч попадал в окно северной стены на стол (окно 120 x 130, низ 90 от пола):
## азимут 0 = солнце строго за окном, плюс к востоку. Допустимый разброс около +-30 градусов.

@export var id: StringName
@export var title: String

@export_category("Sun")
@export var sun_azimuth := 0.0
@export var sun_elevation := 40.0
@export var sun_color := Color(1.0, 0.96, 0.9)
## Множитель к энергии солнца (после Look.sun_energy_mul)
@export var sun_energy := 1.0

@export_category("Ambient")
@export var ambient_tint := Color(1.0, 1.0, 1.0)
@export var ambient_energy_mul := 1.0
@export var background_tint := Color(1.0, 1.0, 1.0)

@export_category("Window sky")
@export var sky_top := Color(0.45, 0.68, 0.95)
@export var sky_bottom := Color(0.82, 0.92, 1.0)

@export_category("Sky fill")
## Заполняющий направленный свет «небо» (SkyFill): не видит стены и потолок (отдельный visual layer), поэтому освещает пол,
## мебель и стол целиком и даёт мягкие тени предметов вне пятна окна. Направление: азимут как у солнца, высота fill_elevation
@export var fill_color := Color(0.72, 0.84, 1.0)
@export var fill_energy := 0.6
@export var fill_elevation := 65.0

@export_category("Lamp")
## Включать лампу над столом автоматически (ручной переключатель в Observe это перекрывает)
@export var lamp_on := false


static func builtin_ids() -> Array:
	return [&"morning", &"day", &"evening", &"night"]


static func builtin(_id: StringName) -> TimeOfDayPreset:
	match _id:
		&"morning":
			return _make(_id, "Утро", {
				"sun_azimuth": -25.0, "sun_elevation": 22.0,
				"sun_color": Color(1.0, 0.82, 0.62), "sun_energy": 0.75,
				"ambient_tint": Color(1.0, 0.93, 0.88), "ambient_energy_mul": 0.9,
				"background_tint": Color(1.0, 0.9, 0.8),
				"sky_top": Color(0.62, 0.74, 0.95), "sky_bottom": Color(1.0, 0.82, 0.65),
				"fill_color": Color(0.9, 0.88, 1.0), "fill_energy": 0.4, "fill_elevation": 60.0,
			})
		&"day":
			return _make(_id, "День", {
				"sun_azimuth": 5.0, "sun_elevation": 40.0,
				"sun_color": Color(1.0, 0.96, 0.9), "sun_energy": 1.0,
			})
		&"evening":
			return _make(_id, "Вечер", {
				"sun_azimuth": 25.0, "sun_elevation": 16.0,
				"sun_color": Color(1.0, 0.6, 0.35), "sun_energy": 0.6,
				"ambient_tint": Color(1.0, 0.82, 0.75), "ambient_energy_mul": 0.8,
				"background_tint": Color(1.0, 0.75, 0.6),
				"sky_top": Color(0.35, 0.38, 0.70), "sky_bottom": Color(1.0, 0.55, 0.30),
				"fill_color": Color(1.0, 0.68, 0.5), "fill_energy": 0.25, "fill_elevation": 30.0,
			})
		&"night":
			# Солнце работает как луна: холодный слабый свет, лампа включена
			return _make(_id, "Ночь", {
				"sun_azimuth": 0.0, "sun_elevation": 35.0,
				"sun_color": Color(0.55, 0.65, 1.0), "sun_energy": 0.12,
				"ambient_tint": Color(0.58, 0.66, 0.92), "ambient_energy_mul": 0.65,
				"background_tint": Color(0.3, 0.35, 0.6),
				"sky_top": Color(0.03, 0.05, 0.15), "sky_bottom": Color(0.10, 0.12, 0.25),
				"fill_color": Color(0.4, 0.5, 0.9), "fill_energy": 0.1, "fill_elevation": 60.0,
				"lamp_on": true,
			})
	return null


static func _make(_id: StringName, _title: String, d: Dictionary) -> TimeOfDayPreset:
	var p := TimeOfDayPreset.new()
	p.id = _id
	p.title = _title
	for k in d:
		p.set(k, d[k])
	return p
