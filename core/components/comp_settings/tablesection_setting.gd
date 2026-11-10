class_name TableSectionSetting extends ComponentSettings

# XX claude-table T1 (новый файл)
## Собирает секцию подмакетника: C_Contour (прямоугольник по size из TableConfig) и C_TableSection.
## Порядок в массиве компонентов .tres: Identity (TableConfig), TableSection.
## Identity должен идти первым: размер и толщину берём из его TableConfig.


func create_component(entity: Entity) -> Component:
	var size := Vector2(100.0, 100.0)
	var thickness := C_TableSection.DEFAULT_THICKNESS
	var cfg := TableConfig.from_entity(entity)
	if cfg == null:
		push_error("TableSectionSetting: в паспорте (C_Identity.object_config) нет TableConfig, секция 100 x 100")
	else:
		size = cfg.size
		thickness = cfg.thickness

	# 1. Контур. set_rect до add_component: события на шину здесь никто не слушает, данные просто лежат
	var contour := C_Contour.new()
	contour.name = 'C_Contour'
	contour.set_rect(size)
	entity.add_component(contour)

	# 2. Плита: меш и коллизия строятся в on_entity_ready, когда контур уже на месте
	var section := C_TableSection.new()
	section.name = 'C_TableSection'
	section.thickness = thickness
	entity.add_component(section)

	# 3. Ховер и выбор: контуры в режиме «Секции» (T2). Сам режим решает, что можно выбрать (SelectTool._is_pickable)
	var hov := C_Hoverable.new()
	hov.name = 'C_Hoverable'
	entity.add_component(hov)
	var sel := C_Selectable.new()
	sel.name = 'C_Selectable'
	entity.add_component(sel)

	return section
