class_name SwitchShapeSettings extends ComponentSettings

# XX claude-switch (новый файл)
## Форма стрелки. В массиве компонентов .tres после PathSetting и до SocketSettings.
## Значения берет из паспорта (SwitchConfig) и переносит в компонент, как остальные Settings.

func create_component(entity: Entity) -> Component:
	var comp := C_SwitchShape.new()
	comp.name = 'C_SwitchShape'
	var cfg := SwitchConfig.from_entity(entity)
	if cfg == null:
		push_error("SwitchShapeSettings: в паспорте (C_Identity.object_config) нет SwitchConfig, форма по умолчанию")
	else:
		comp.length = cfg.radius
		comp.diverge_deg = absf(cfg.diverge_deg)
		comp.diverge_radius = cfg.diverge_radius
		comp.hand = 1.0 if cfg.hand >= 0 else -1.0
		comp.start_route = cfg.start_route
	entity.add_component(comp)
	return comp
