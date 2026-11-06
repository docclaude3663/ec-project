class_name AccessoryBus extends RefCounted

#####################
## Шина аксессуаров (ATTN_10 §10.5.7, D6)
#####################
## Фиксированные 12 В для света домов и фонарей, привода стрелок и датчиков. Один на макет, живёт в `PGM.bus`.
## Не пульт и не PowerSource: у неё нет выводов и меток, только выключатель, лимит тока и защита.
## Потребители (`bus_watts() -> float`) регистрируются в `consumers`; нагрузка идёт в расчёт, только когда
## `load_for_lights` включён (правило D7), иначе шина ток не считает.
## Питается от сети макета (`PGM.mains`), когда правило supply_required включено.
## Проводка (клемма ACCESSORY на домах и фонарях) пока не заведена: шина общая, как питающая сеть (P1).

const VOLTS := 12.0
## Секунд перегрузки до отключения
const DELAY := 0.5
## Во сколько раз ток должен превысить лимит, чтобы отключить сразу
const INSTANT_FACTOR := 2.0

var enabled := true
var i_max := 1.0
var tripped := false
## Ток нагрузки, А (обновляется в step)
var load_a := 0.0
var overload_t := 0.0
## Объекты с методом bus_watts() -> float
var consumers: Array = []


func add_consumer(o: Object) -> void:
	if o != null and not consumers.has(o):
		consumers.append(o)


func remove_consumer(o: Object) -> void:
	consumers.erase(o)


## Шина запитана: включена, не отключена защитой, есть сеть (если она обязательна)
func powered(mains: PowerSupply, supply_required: bool) -> bool:
	return enabled and not tripped and (not supply_required or mains == null or mains.on)


func voltage(mains: PowerSupply, supply_required: bool) -> float:
	return VOLTS if powered(mains, supply_required) else 0.0


## Один шаг (10 Гц). Возвращает "trip", если шина отключилась в этом шаге, иначе "".
## `light_load`: нагрузка считается (правило load_for_lights), `protection`: защита включена
func step(dt: float, mains: PowerSupply, supply_required: bool, light_load: bool, protection: bool) -> String:
	if not light_load or not enabled or tripped or (supply_required and mains != null and not mains.on):
		load_a = 0.0
		overload_t = 0.0
		return ""
	var watts := 0.0
	for c in consumers.duplicate():
		if is_instance_valid(c):
			watts += float(c.bus_watts())
		else:
			consumers.erase(c)
	load_a = watts / VOLTS
	if not protection:
		overload_t = 0.0
		return ""
	var limit := maxf(i_max, 0.001)
	if load_a > limit * INSTANT_FACTOR:
		return _trip()
	if load_a > limit:
		overload_t += dt
		if overload_t >= DELAY:
			return _trip()
	else:
		overload_t = 0.0
	return ""


func _trip() -> String:
	tripped = true
	load_a = 0.0
	overload_t = 0.0
	return "trip"


func reset() -> void:
	tripped = false
	overload_t = 0.0


func save_data() -> Dictionary:
	return {"enabled": enabled, "i_max": i_max, "tripped": tripped}


func load_data(d: Dictionary) -> void:
	enabled = bool(d.get("enabled", true))
	i_max = clampf(float(d.get("i_max", 1.0)), 0.1, 20.0)
	tripped = bool(d.get("tripped", false))
	load_a = 0.0
	overload_t = 0.0
