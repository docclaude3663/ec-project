class_name C_OccupancySensor extends Component

#####################
## Датчик занятости (ATTN_10 §10.5.7, D6)
#####################
## Компонент на траке. Участок (связный набор траков без изостыков) занят, если на нём стоит любая тележка
## вагона или локо на рельсах; резисторные оси не моделируются. PGM опрашивает занятость на шаге решателя (10 Гц)
## и вызывает `set_occupied`; смена состояния даёт `PGM.sensor_triggered` и (по участку) `PGM.net_occupied`.
## Ставится из вкладки питания трака, пишется в сейв как компонент. События для звука (§10.5.12): подписчиков нет.

var occupied := false
## Сколько раз участок освобождался: простой счётчик проходов для индикатора
var passes := 0


func on_added() -> void:
	name = "C_OccupancySensor"
	add_to_group(&"occupancy_sensor")
	PGM.request_recalculate()   # корни участков нужны датчику сразу


func on_removed() -> void:
	remove_from_group(&"occupancy_sensor")


## Возвращает true, если состояние сменилось
func set_occupied(v: bool) -> bool:
	if v == occupied:
		return false
	occupied = v
	if not v:
		passes += 1
	return true


func state_text() -> String:
	return "занято" if occupied else "свободно"


func save_data() -> Dictionary:
	return {
		"comp_path": get_script().resource_path,
		"comp_name": get_script().resource_path.get_file().get_basename(),
		"passes": passes,
	}


func load_data(d: Dictionary) -> void:
	passes = int(d.get("passes", 0))
