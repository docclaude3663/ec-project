class_name DCSPresets extends RefCounted

#####################
## Пресеты правил электрики (ATTN_10 §10.5.11, D7)
#####################
## «Простая» P0: виртуальная проводка, без токов и защиты, без изостыков. «Стандарт» P1: как после D3.
## «Реалистичная» P2: проводка обязательна, конфликт выводов отключает оба, защита с ручным сбросом.
## Кампания будет собирать правила главы поверх пресета (ATTN_19), здесь только три базовых.

const SIMPLE := &"simple"
const STANDARD := &"standard"
const REALISTIC := &"realistic"

const ORDER: Array[StringName] = [&"simple", &"standard", &"realistic"]
const TITLES := {&"simple": "Простая", &"standard": "Стандарт", &"realistic": "Реалистичная"}


static func make(id: StringName) -> DCSRules:
	var r := DCSRules.new()
	r.preset = id
	match id:
		SIMPLE:
			r.fidelity = DCSRules.Fidelity.P0
			r.wiring_required = false
			r.supply_required = false
			r.conflict_policy = 0
			r.short_protection = DCSRules.ShortProtection.NONE
			r.gaps_enabled = false
			r.load_for_lights = false
		REALISTIC:
			r.fidelity = DCSRules.Fidelity.P2
			r.wiring_required = true
			r.supply_required = true
			r.conflict_policy = 1
			r.short_protection = DCSRules.ShortProtection.MANUAL
			r.gaps_enabled = true
			r.overheat = true
			r.dcc_enabled = true
			r.load_for_lights = true
		_:
			r.preset = STANDARD
	return r
