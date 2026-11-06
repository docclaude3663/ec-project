class_name PowerSolver extends RefCounted

#####################
## Решатель нагрузки и защиты (ATTN_10 §10.5.6, D3)
#####################
## Чистая логика без сцены, проверяется `tests/power_solver_test.tscn`. PGM зовёт `step` с шагом 10 Гц.
## Ток цепи это сумма токов портов, ток вывода это сумма цепей с его меткой, нагрузка сети это сумма выводов.
## Защита вывода (если у модели `protection`):
##  - ток выше `i_max`: состояние OVERLOAD, таймер; через `overload_delay` вывод TRIPPED;
##  - ток выше `2 · i_max`: вывод TRIPPED сразу;
##  - ток в норме: OK, таймер сброшен.
## КЗ полярности и крестовины (`trip` с причиной "polarity" или "frog") отключают вывод независимо от `protection`
## и дают состояние SHORT. Сброс только `reset`: аварийный стоп источника на защиту не влияет (Q8).

## Сколько секунд перегрузка терпится до отключения
var overload_delay := 0.5
## Во сколько раз ток должен превысить лимит, чтобы отключить вывод сразу
var instant_factor := 2.0


## Питающая сеть обязательна для источников с needs_supply (правило D7 supply_required)
static var supply_required := true
## false (P0): токи и лимиты не считаются
var fidelity_limits := true
## false: защита по перегрузке не срабатывает (правило D7 short_protection = NONE)
var protection := true


## Напряжение на выходе, % команды со знаком: 0, если источник выключен или в аварийном стопе, вывод отключён
## защитой или пульту нужна сеть, а её нет
static func voltage_of(source: PowerSource, out: PowerOutput, mains: PowerSupply) -> float:
	if source == null or out == null:
		return 0.0
	if not source.enabled or source.estop or out.tripped:
		return 0.0
	if supply_required and source.needs_supply() and (mains == null or not mains.on):
		return 0.0
	return clampf(float(out.command), -out.v_max, out.v_max)


static func trip(out: PowerOutput, reason: String) -> void:
	out.tripped = true
	out.trip_reason = reason
	out.state = PowerOutput.State.SHORT if reason in ["polarity", "frog", "conflict"] else PowerOutput.State.TRIPPED
	out.overload_t = 0.0
	out.current = 0.0


static func reset(out: PowerOutput) -> void:
	out.tripped = false
	out.trip_reason = ""
	out.state = PowerOutput.State.OK
	out.overload_t = 0.0


## Один шаг расчёта. Возвращает события для PGM: {"label", "kind": "overload" | "trip" | "clear", "reason"}.
## Освобождённых владельцев портов выкидывает из `ports`
func step(sources: Array, ports: Array, mains: PowerSupply, dt: float, light_load_enabled := false) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	var by_label: Dictionary = {}   # метка -> [источник, вывод]
	for s in sources:
		for o: PowerOutput in (s as PowerSource).outputs:
			o.current = 0.0
			by_label[o.label] = [s, o]

	# 1. токи портов складываются в выводы
	var i := ports.size() - 1
	while i >= 0:
		var p := ports[i] as PowerPort
		if p == null or (p.owner != null and not is_instance_valid(p.owner)):
			ports.remove_at(i)
		elif p.net != 0 and by_label.has(p.net):
			var pair: Array = by_label[p.net]
			var out := pair[1] as PowerOutput
			if not out.tripped:
				out.current += p.current(light_load_enabled)
		i -= 1

	# 2. защита и нагрузка сети
	var load_w := 0.0
	for s in sources:
		var src := s as PowerSource
		for out: PowerOutput in src.outputs:
			var v := voltage_of(src, out, mains)
			load_w += absf(v) * 0.01 * PowerSupply.VOLTS_AT_100 * out.current
			_protect(src, out, dt, events)
	if mains != null:
		mains.load_w = load_w
		mains.overloaded = load_w > mains.capacity_w
	return events


## Ток ветки (D5, предохранитель): сумма токов портов, стоящих на перечисленных цепях `nets` (ключи метки вывода)
static func branch_current(ports: Array, nets: Dictionary, light_load_enabled := false) -> float:
	var sum := 0.0
	for p in ports:
		var port := p as PowerPort
		if port != null and port.net != 0 and nets.has(port.net) and (port.owner == null or is_instance_valid(port.owner)):
			sum += port.current(light_load_enabled)
	return sum


func _protect(src: PowerSource, out: PowerOutput, dt: float, events: Array[Dictionary]) -> void:
	if out.tripped:
		return
	if not fidelity_limits or not protection:
		# P0 или защита выключена: токи видны (P1+), но вывод не отключается и не помечен перегрузкой
		if out.state != PowerOutput.State.OK:
			out.state = PowerOutput.State.OK
			out.overload_t = 0.0
		return
	var limit := maxf(out.i_max, 0.001)
	var was := out.state
	if out.current > limit * instant_factor:
		if src.has_protection():
			trip(out, "overload")
			events.append({"label": out.label, "kind": "trip", "reason": "overload"})
			return
		out.state = PowerOutput.State.OVERLOAD
	elif out.current > limit:
		out.state = PowerOutput.State.OVERLOAD
		out.overload_t += dt
		if src.has_protection() and out.overload_t >= overload_delay:
			trip(out, "overload")
			events.append({"label": out.label, "kind": "trip", "reason": "overload"})
			return
	else:
		out.state = PowerOutput.State.OK
		out.overload_t = 0.0
	if out.state != was:
		events.append({"label": out.label, "kind": "overload" if out.state == PowerOutput.State.OVERLOAD else "clear", "reason": ""})
