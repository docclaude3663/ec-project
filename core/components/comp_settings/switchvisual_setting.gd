class_name SwitchVisualSettings extends ComponentSettings

# XX claude-switch (новый файл)
## Визуал стрелки: процедурный, как у flex. Первым после Identity в массиве компонентов .tres

## Рельсы, шпалы, балласт. Пусто = «следовать сессии»: стиль берётся у TSM (как у flex, ATTN_17 §17.13).
## Непусто = стиль зафиксирован в объекте
@export var style: TrackStyle
## Рычаг у носка. Выключить у траков без переключения (например, упор)
@export var lever := true


func create_component(entity: Entity) -> Component:
	var vis := C_SwitchVisual.new()
	# Ширина коллизии из паспорта (0 = как в стиле)
	vis.style = TrackStyle.with_collision_width(TSM.resolve_for(entity, style), TrackConfig.collision_width_of(entity))
	vis.with_lever = lever
	vis.name = 'C_SwitchVisual'
	entity.add_component(vis)
	return vis
