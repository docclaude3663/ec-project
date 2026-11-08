class_name CatalogProvider extends RefCounted

###########################
## CatalogProvider. Источник данных для панели «категория, тег, объект»
###########################
## Контракт. ToolbarController знает только его и не знает, откуда берутся данные:
## сейчас это объекты из .tres (EntityCatalogProvider), в U4 появится провайдер карточек Observe.
##
## Словари для кнопок: {"id": StringName, "name": String, "icon": Texture2D или null}.
## Кнопки элементов создает сам провайдер (create_buttons): он знает, что это, объект или карточка, и с какими
## аргументами звать приемник режима on_pressed (объекты: on_pressed.call(setting), карточки: (category, id, pressed)).


## Провайдер зовёт его, когда изменились сами данные (например, переименован или удалён состав):
## ToolbarController перестраивает кнопки. Пусто: никто не слушает
var on_changed: Callable = Callable()


## Категории (нижний ряд кнопок) в порядке показа
func get_categories() -> Array[Dictionary]:
	return []


## Теги категории (кнопки справа от сетки) в порядке показа
func get_tags(_category: StringName) -> Array[Dictionary]:
	return []


## Фильтры, применимые к тегу: [{"id", "title", "options": [{"id", "name"}]}]. Независимы от тега и друг от друга
func get_filters(_category: StringName, _tag: StringName) -> Array[Dictionary]:
	return []


## Кнопки элементов категории и тега в порядке показа. Тегов нет: tag пустой.
## filters: {id фильтра: выбранное значение}, нет ключа или пусто = «любой»
func create_buttons(_category: StringName, _tag: StringName, _on_pressed: Callable, _filters: Dictionary = {}) -> Array[Button]:
	return []
