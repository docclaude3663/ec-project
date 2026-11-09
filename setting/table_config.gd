class_name TableConfig extends ObjectConfig

# XX claude-table T1 (новый файл)
########################
## Паспорт секции подмакетника. Цепляется в C_Identity (IdentitySetting.object_config)
########################
## Читается типизированно: TableConfig.from_entity(entity). Размер и толщина задают только начальную форму:
## дальше форму ведёт C_Contour, а толщину C_TableSection (оба идут в сейв).

## Размер прямоугольной секции в плане (X, Z), u
@export var size := Vector2(100.0, 100.0)

## Толщина плиты, u. Верх плиты всегда на y = 0 (ATTN_23 §23.2), плита растёт вниз. 5 = как в v1
@export var thickness := 5.0


## Типизированное чтение паспорта. null, если у сущности нет паспорта или в нем конфиг другого семейства
static func from_entity(entity: Entity) -> TableConfig:
	var idc := entity.get_comp(C_Identity) as C_Identity
	if idc == null:
		return null
	return idc.object_config as TableConfig
