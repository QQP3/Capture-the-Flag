extends Area2D

@export var rank: int = 0
@export var team: String = "red"  # or "blue"
var is_selected: bool = false

@onready var texture_rect = $TextureRect

func _ready():
	# Optional: make pieces semi-transparent if needed, etc.
	texture_rect.modulate = Color(1, 1, 1)

func _input_event(viewport, event, shape_idx):
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		# Tell Main (your root) that this piece was clicked
		var main_node = get_tree().root.get_node("Main")
		main_node.piece_clicked(self)

func select():
	is_selected = true
	texture_rect.modulate = Color(0.5, 0.5, 0.5)  # Yellow tint on select

func deselect():
	is_selected = false
	texture_rect.modulate = Color(1, 1, 1)  # Normal color on deselect
