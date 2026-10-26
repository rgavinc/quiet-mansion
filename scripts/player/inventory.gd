class_name Inventory
extends Node
## Held objects and usable items. Scroll wheel cycles. Capacity from PlayerStats.

signal changed(items: Array)
signal selected_changed(index: int)

var items: Array = []
var selected: int = -1


func capacity() -> int:
	return int(PlayerStats.get_stat(&"inventory_slots"))


func is_full() -> bool:
	return items.size() >= capacity()


func add(item: Dictionary) -> bool:
	if is_full():
		return false
	items.append(item)
	selected = items.size() - 1
	_emit()
	return true


func current() -> Dictionary:
	return items[selected] if selected >= 0 and selected < items.size() else {}


func take_current() -> Dictionary:
	var it := current()
	if it.is_empty():
		return {}
	items.remove_at(selected)
	selected = mini(selected, items.size() - 1)
	_emit()
	return it


func cycle(direction: int) -> void:
	if items.is_empty():
		selected = -1
		selected_changed.emit(selected)
		return
	selected = posmod(selected + direction, items.size())
	selected_changed.emit(selected)
	var fe := get_node_or_null(^"/root/FESignals")
	if fe: fe.select_item(selected)


func _emit() -> void:
	changed.emit(items)
	selected_changed.emit(selected)
	var fe := get_node_or_null(^"/root/FESignals")
	if fe:
		fe.set_items(items)
		fe.select_item(selected)
