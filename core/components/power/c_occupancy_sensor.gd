class_name C_OccupancySensor extends Component

#####################
## Датчик занятости (ATTN_10 §10.5.7, D6)
#####################
## Компонент на траке. Участок (связный набор траков без изостыков) занят, если на нём стоит любая тележка
## вагона или локо на рельсах; резисторные оси не моделируются. PGM опрашивает занятость на шаге решателя (10 Гц)
## и вызывает `set_occupied`; смена состояния даёт `PGM.sensor_triggered` и (по участку) `PGM.net_occupied`.
## Ставится из вкладки питания трака, пишется в сейв как компонент. События для звука (§10.5.12): подписчиков нет.

## Цвета участка: в слое питания (материал рельса трака с датчиком) и во вкладке питания
const COLOR_FREE := Color(0.25, 0.85, 0.35)
const COLOR_OCCUPIED := Color(1.0, 0.55, 0.1)

var occupied := false
## false после снятия компонента (визуал не должен красить трак, пока узел ещё не освобождён)
var active := true
## Сколько раз участок освободился после занятия (один въехавший и выехавший состав = 1 проход)
var passes := 0


func on_added() -> void:
	name = "C_OccupancySensor"
	add_to_group(&"occupancy_sensor")
	PGM.request_recalculate()   # корни участков нужны датчику сразу
	_refresh_visual()


func on_removed() -> void:
	remove_from_group(&"occupancy_sensor")
	active = false
	_refresh_visual()


## Возвращает true, если состояние сменилось
func set_occupied(v: bool) -> bool:
	if v == occupied:
		return false
	occupied = v
	if not v:
		passes += 1
	_refresh_visual()
	return true


## Трак с датчиком перекрашивается в слое питания (C_TrackVisual._rail_power_material)
func _refresh_visual() -> void:
	if is_instance_valid(entity) and entity.is_inside_tree():
		entity.send_event("on_power_view_changed", {"active": PGM.is_power_layer_active})


func state_text() -> String:
	return "занят" if occupied else "свободен"


func save_data() -> Dictionary:
	return {
		"comp_path": get_script().resource_path,
		"comp_name": get_script().resource_path.get_file().get_basename(),
		"passes": passes,
	}


func load_data(d: Dictionary) -> void:
	passes = int(d.get("passes", 0))
