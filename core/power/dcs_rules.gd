class_name DCSRules extends Resource

#####################
## Правила электрики макета (ATTN_10 §10.5.11, D7)
#####################
## Один ресурс на партию: пишется в сейв (`PGM.save_state`), выбирается пресетом (`DCSPresets`) и применяется
## через `PGM.apply_rules`. Читают: PGM (проводка, конфликт, защита), PowerSolver (токи, лимиты, сеть), RailNetBuilder (изостыки), UI.
## Поля overheat, common_rail, dcc_enabled пока только хранятся (их читают D8, D9 и будущая тепловая модель).

## P0: токи и лимиты не считаются, защиты нет, КЗ полярности только обнуляет цепь. P1: токи, лимиты, защита (D3). P2: как P1, строгие режимы
enum Fidelity { P0, P1, P2 }
## NONE: защиты нет. AUTO: сработавший вывод сам возвращается через `AUTO_RESET_S`, если причины нет. MANUAL: только сброс игроком
enum ShortProtection { NONE, AUTO, MANUAL }

## Секунд до автосброса защиты при ShortProtection.AUTO
const AUTO_RESET_S := 3.0

@export var preset: StringName = &"standard"
@export var fidelity: Fidelity = Fidelity.P1
## Клип без провода обесточен (физическая проводка обязательна)
@export var wiring_required := false
## Источники с needs_supply мертвы без питающей сети (PGM.mains)
@export var supply_required := true
## Политика конфликта выводов: 0 MERGE, 1 TRIP (PGM.ConflictPolicy)
@export var conflict_policy := 0
@export var short_protection: ShortProtection = ShortProtection.MANUAL
## Изостыки работают и доступны в UI; false: рельсы одного связного участка всегда одна цепь
@export var gaps_enabled := true
@export var overheat := false
@export var common_rail := false
@export var dcc_enabled := false
## Свет вагонов и домов нагружает вывод
@export var load_for_lights := false


func to_dict() -> Dictionary:
	return {
		"preset": String(preset), "fidelity": int(fidelity), "wiring_required": wiring_required,
		"supply_required": supply_required, "conflict_policy": conflict_policy,
		"short_protection": int(short_protection), "gaps_enabled": gaps_enabled, "overheat": overheat,
		"common_rail": common_rail, "dcc_enabled": dcc_enabled, "load_for_lights": load_for_lights,
	}


static func from_dict(d: Dictionary) -> DCSRules:
	var r := DCSRules.new()
	r.preset = StringName(d.get("preset", "custom"))
	r.fidelity = clampi(int(d.get("fidelity", 1)), 0, 2) as Fidelity
	r.wiring_required = bool(d.get("wiring_required", false))
	r.supply_required = bool(d.get("supply_required", true))
	r.conflict_policy = clampi(int(d.get("conflict_policy", 0)), 0, 1)
	r.short_protection = clampi(int(d.get("short_protection", 2)), 0, 2) as ShortProtection
	r.gaps_enabled = bool(d.get("gaps_enabled", true))
	r.overheat = bool(d.get("overheat", false))
	r.common_rail = bool(d.get("common_rail", false))
	r.dcc_enabled = bool(d.get("dcc_enabled", false))
	r.load_for_lights = bool(d.get("load_for_lights", false))
	return r
