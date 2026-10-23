extends CanvasLayer
## Corner badge while AssetProvenance still has ai art/audio.

@onready var label: Label = %WatermarkLabel

func _ready() -> void:
	AssetProvenance.provenance_changed.connect(_on_prov)
	_on_prov(AssetProvenance.ai_remaining)

func _on_prov(n: int) -> void:
	visible = n > 0
	if label:
		label.text = "AI assets in use (%d)" % n
