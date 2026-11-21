extends WorldObject
## Generic breakable prop (furniture junk). Not pickable. Kept for older scenes.
## Uses a floor-junk sprite when one exists in the manifest; otherwise the same
## 20×20 ColorRect as before. Collision, size and position are unchanged.


func _init() -> void:
	display_name = "Obstacle"
	art_slot = PropVisual.first_slot(PropVisual.OBSTACLE_SLOTS)


func _build_visual() -> void:
	var slot := PropVisual.add_obstacle_visual(self, size)
	if slot != "":
		art_slot = slot
