class_name CrossingShapeSettings extends ComponentSettings

# XX claude-switch (новый файл)
## Форма кросса. В массиве компонентов .tres после PathSetting и до SocketSettings.
## Значения берет из паспорта (CrossingConfig) и переносит в компонент, как остальные Settings.

func create_component(entity: Entity) -> Component:
	var comp := C_CrossingShape.new()
	comp.name = 'C_CrossingShape'
	var cfg := CrossingConfig.from_entity(entity)
	if cfg == null:
		push_error("CrossingShapeSettings: в паспорте (C_Identity.object_config) нет CrossingConfig, форма по умолчанию")
	else:
		comp.length = cfg.radius
		comp.cross_deg = cfg.cross_deg
		comp.separate_circuits = cfg.separate_circuits
	entity.add_component(comp)
	return comp
