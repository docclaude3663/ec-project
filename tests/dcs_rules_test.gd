extends Node

# D7 (ATTN_10 §10.9): новый файл
## Тест правил электрики (DCSRules, DCSPresets, PGM.apply_rules, сейв правил). Запуск: tests/dcs_rules_test.tscn, F6.
## R1 пресеты: значения «Простая», «Стандарт», «Реалистичная»
## R2 to_dict и from_dict: полный круг; пустой словарь даёт «Стандарт»-значения
## R3 apply_preset ставит PGM.wiring_required, conflict_policy, load_for_lights и сигнал rules_changed
## R4 supply_required: без сети напряжение 0 в «Стандарт», в «Простая» напряжение есть
## R5 P0: КЗ полярности обнуляет цепь без отключения вывода (tripped = false)
## R6 P1: защита по КЗ отключает вывод (как после D3), ShortProtection.NONE не отключает
## R7 ShortProtection.AUTO: сработавший вывод возвращается сам, когда КЗ нет
## R8 сейв правил: save_state → load_state; сейв без ключа rules даёт «Стандарт»
## R9 reset_state возвращает «Стандарт»
## R10 gaps_enabled = false: RailNetBuilder.gaps_enabled выключен

var _fails := 0
var _rules_signals := 0


func check(name: String, ok: bool, info := "") -> void:
	if ok:
		print("PASS  ", name)
	else:
		_fails += 1
		print("FAIL  ", name, "  ", info)


func _ready() -> void:
	PGM.reset_state()
	PGM.rules_changed.connect(func() -> void: _rules_signals += 1)

	# R1
	var s := DCSPresets.make(DCSPresets.SIMPLE)
	check("R1 Простая: P0, без проводки, без защиты, без изостыков, сеть не нужна",
			s.fidelity == DCSRules.Fidelity.P0 and not s.wiring_required and s.short_protection == DCSRules.ShortProtection.NONE
			and not s.gaps_enabled and not s.supply_required)
	var st := DCSPresets.make(DCSPresets.STANDARD)
	check("R1 Стандарт: P1, ручной сброс, изостыки, MERGE",
			st.fidelity == DCSRules.Fidelity.P1 and not st.wiring_required and st.short_protection == DCSRules.ShortProtection.MANUAL
			and st.gaps_enabled and st.conflict_policy == 0 and st.supply_required)
	var re := DCSPresets.make(DCSPresets.REALISTIC)
	check("R1 Реалистичная: P2, проводка, TRIP, DCC, свет нагружает",
			re.fidelity == DCSRules.Fidelity.P2 and re.wiring_required and re.conflict_policy == 1 and re.dcc_enabled and re.load_for_lights)

	# R2
	var back := DCSRules.from_dict(re.to_dict())
	check("R2 круг to_dict/from_dict", back.to_dict() == re.to_dict(), str(back.to_dict()))
	check("R2 пустой словарь это значения «Стандарт»", DCSRules.from_dict({}).to_dict()["fidelity"] == 1 and DCSRules.from_dict({}).wiring_required == false)

	# R3
	var before := _rules_signals
	PGM.apply_preset(DCSPresets.REALISTIC)
	check("R3 Реалистичная применена", PGM.wiring_required and PGM.conflict_policy == PGM.ConflictPolicy.TRIP and PGM.load_for_lights and _rules_signals == before + 1)
	PGM.apply_preset(DCSPresets.STANDARD)
	check("R3 Стандарт применён", not PGM.wiring_required and PGM.conflict_policy == PGM.ConflictPolicy.MERGE and not PGM.load_for_lights)

	# R4
	PGM.set_command(1, 50)
	PGM.mains.on = false
	check("R4 Стандарт без сети: 0", PGM.get_power(1) == 0.0, str(PGM.get_power(1)))
	PGM.apply_preset(DCSPresets.SIMPLE)
	check("R4 Простая без сети: напряжение есть", PGM.get_power(1) == 50.0, str(PGM.get_power(1)))
	PGM.mains.on = true

	# R5
	PGM.shorted_nets[1] = true
	check("R5 P0: КЗ обнуляет цепь", PGM.get_power(1) == 0.0)
	var o := PGM.get_output(1)
	PGM._retrip_shorted()
	check("R5 P0: вывод не отключён защитой", o != null and not o.tripped)
	PGM.shorted_nets.clear()

	# R6
	PGM.apply_preset(DCSPresets.STANDARD)
	PGM.set_command(1, 50)
	PGM.shorted_nets[1] = true
	PGM._retrip_shorted()
	check("R6 P1: КЗ отключает вывод", o.tripped and o.trip_reason == "polarity", str(o.trip_reason))
	PGM.shorted_nets.clear()
	PGM.reset_output(1)
	var none := DCSPresets.make(DCSPresets.STANDARD)
	none.short_protection = DCSRules.ShortProtection.NONE
	PGM.apply_rules(none)
	PGM.set_command(1, 50)
	PGM.shorted_nets[1] = true
	PGM._retrip_shorted()
	check("R6 защита NONE: вывод не отключён", not o.tripped)
	PGM.shorted_nets.clear()

	# R7
	var auto := DCSPresets.make(DCSPresets.STANDARD)
	auto.short_protection = DCSRules.ShortProtection.AUTO
	PGM.apply_rules(auto)
	PGM.set_command(1, 50)
	PGM.trip_contour(1, "overload")
	check("R7 AUTO: вывод отключён", o.tripped)
	PGM._auto_reset_step()
	check("R7 AUTO: сразу не сброшен", o.tripped)
	await get_tree().create_timer(DCSRules.AUTO_RESET_S + 0.3).timeout
	PGM._auto_reset_step()
	PGM._auto_reset_step()
	check("R7 AUTO: сброшен по таймеру", not o.tripped)

	# R8
	PGM.apply_preset(DCSPresets.REALISTIC)
	var saved := PGM.save_state()
	PGM.apply_preset(DCSPresets.SIMPLE)
	PGM.load_state(saved)
	check("R8 сейв: Реалистичная вернулась", PGM.rules.preset == DCSPresets.REALISTIC and PGM.wiring_required, str(PGM.rules.preset))
	var old := saved.duplicate(true)
	old.erase("rules")
	PGM.load_state(old)
	check("R8 сейв без rules: Стандарт", PGM.rules.preset == DCSPresets.STANDARD and not PGM.wiring_required)
	PGM.apply_preset(DCSPresets.SIMPLE)
	PGM.load_state({})
	check("R8 пустой сейв: Стандарт", PGM.rules.preset == DCSPresets.STANDARD)

	# R9
	PGM.apply_preset(DCSPresets.REALISTIC)
	PGM.reset_state()
	check("R9 reset_state: Стандарт", PGM.rules.preset == DCSPresets.STANDARD and not PGM.wiring_required)

	# R10
	PGM.apply_preset(DCSPresets.SIMPLE)
	check("R10 Простая: изостыки выключены в сборщике", not PGM._builder.gaps_enabled)
	PGM.apply_preset(DCSPresets.STANDARD)
	check("R10 Стандарт: изостыки включены", PGM._builder.gaps_enabled)

	PGM.reset_state()
	print("ИТОГ: ", "ВСЕ PASS" if _fails == 0 else "FAIL x%d" % _fails)
