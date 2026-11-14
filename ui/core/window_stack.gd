class_name WindowStack extends RefCounted

# U10 (ATTN_17 §17.3.1): новый файл
## Стек открытых модальных окон. Esc закрывает верхнее (ModalWindow смотрит сюда сам).
## Игра спрашивает «есть ли открытое окно» через UIPointer.modal_open().

static var _stack: Array[Control] = []


static func push(w: Control) -> void:
	if not _stack.has(w):
		_stack.append(w)


static func remove(w: Control) -> void:
	_stack.erase(w)


## Верхнее окно или null. Освобождённые окна выбрасываются
static func top() -> Control:
	while not _stack.is_empty() and not is_instance_valid(_stack.back()):
		_stack.pop_back()
	return null if _stack.is_empty() else _stack.back()


static func has_open() -> bool:
	return top() != null
