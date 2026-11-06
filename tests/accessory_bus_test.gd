extends Node

# D6 (ATTN_10 §10.9): новый файл
## Тест шины аксессуаров (AccessoryBus) и датчика занятости без сцены физики.
## Запуск: tests/accessory_bus_test.tscn, F6. Результат в Output: PASS / FAIL и итог.
## B1 включена: 12 В; выключена: 0
## B2 нет сети: при supply_required шина мертва, без supply_required работает
## B3 нагрузка не считается без load_for_lights
## B4 перегрузка дольше DELAY отключает шину, сразу при двойном превышении
## B5 reset возвращает шину, нагрузка в норме не отключает
## B6 без защиты (protection = false) шина не отключается
## B7 сейв: enabled, лимит, tripped
## B8 датчик: set_occupied возвращает смену состояния, проходы считаются

var _fails := 0


class FakeLoad extends RefCounted:
	var w := 0.0
	func bus_watts() -> float:
		return w


func check(name: String, ok: bool, info := "") -> void:
	if ok:
		print("PASS  ", name)
	else:
		_fails += 1
		print("FAIL  ", name, "  ", info)


func _ready() -> void:
	var mains := PowerSupply.new()
	var bus := AccessoryBus.new()
	check("B1 включена 12 В", is_equal_approx(bus.voltage(mains, true), 12.0))
	bus.enabled = false
	check("B1 выключена 0", bus.voltage(mains, true) == 0.0)
	bus.enabled = true

	mains.on = false
	check("B2 нет сети и сеть обязательна: 0", bus.voltage(mains, true) == 0.0)
	check("B2 сеть не обязательна: 12 В", is_equal_approx(bus.voltage(mains, false), 12.0))
	mains.on = true

	var load1 := FakeLoad.new()
	load1.w = 24.0   # 2 А при лимите 1 А
	bus.add_consumer(load1)
	bus.step(0.1, mains, true, false, true)
	check("B3 без load_for_lights нагрузка 0", bus.load_a == 0.0 and not bus.tripped)

	var res := ""
	for i in 4:
		res = bus.step(0.1, mains, true, true, true)
	check("B4 до DELAY ещё не отключена", res == "" and not bus.tripped and is_equal_approx(bus.load_a, 2.0), "%s %s" % [res, bus.load_a])
	res = bus.step(0.1, mains, true, true, true)
	check("B4 после DELAY отключена", res == "trip" and bus.tripped, str(bus.tripped))
	check("B4 отключённая шина 0 В", bus.voltage(mains, true) == 0.0)

	bus.reset()
	load1.w = 60.0   # 5 А: больше 2 лимитов
	res = bus.step(0.1, mains, true, true, true)
	check("B4 двойное превышение отключает сразу", res == "trip", res)

	bus.reset()
	load1.w = 6.0   # 0.5 А в норме
	for i in 10:
		bus.step(0.1, mains, true, true, true)
	check("B5 в норме не отключается", not bus.tripped and is_equal_approx(bus.load_a, 0.5))

	load1.w = 60.0
	for i in 10:
		bus.step(0.1, mains, true, true, false)
	check("B6 без защиты не отключается", not bus.tripped)

	bus.i_max = 2.5
	bus.enabled = false
	bus.tripped = true
	var b2 := AccessoryBus.new()
	b2.load_data(bus.save_data())
	check("B7 сейв", not b2.enabled and b2.tripped and is_equal_approx(b2.i_max, 2.5))
	var b3 := AccessoryBus.new()
	b3.load_data({})
	check("B7 пустой сейв: значения по умолчанию", b3.enabled and not b3.tripped and is_equal_approx(b3.i_max, 1.0))

	var s := C_OccupancySensor.new()
	check("B8 свободно -> занято: смена", s.set_occupied(true) and s.occupied)
	check("B8 повтор: без смены", not s.set_occupied(true))
	check("B8 занято -> свободно: смена и проход", s.set_occupied(false) and s.passes == 1 and s.state_text() == "свободно")
	s.free()

	print("ИТОГ: ", "ВСЕ PASS" if _fails == 0 else "FAIL x%d" % _fails)
