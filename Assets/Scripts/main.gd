extends Node2D

var selected_piece: Area2D = null

func piece_clicked(piece: Area2D):
	# If no piece selected, select this one (if it belongs to current player)
	if selected_piece == null:
		if can_select_piece(piece):
			selected_piece = piece
			piece.select()
	else:
		# If clicking the same piece, deselect it
		if piece == selected_piece:
			selected_piece.deselect()
			selected_piece = null
		else:
			# Attempt to move the selected piece to the clicked piece's position or handle attack
			if can_move(selected_piece, piece):
				# Move or attack logic here, for example:
				move_piece(selected_piece, piece.position)
				selected_piece.deselect()
				selected_piece = null
			else:
				# Switch selection to the new piece if allowed
				if can_select_piece(piece):
					selected_piece.deselect()
					selected_piece = piece
					piece.select()

func can_select_piece(piece: Area2D) -> bool:
	# Example: only select your own pieces, add your logic here
	return piece.team == "red"  # Or your current player's turn

func can_move(from_piece: Area2D, to_piece: Area2D) -> bool:
	# Example: can move if the target square is empty or enemy piece (simplified)
	return true  # Replace with your Stratego movement/attack rules

func move_piece(piece: Area2D, target_position: Vector2):
	# Move piece visually
	piece.position = target_position
	# Add your gamecontroller logic here to update game state
	
# Assuming you have a TileMap node named "Board"
@onready var board = $Board

func _input(event):
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var click_pos = get_global_mouse_position()
		var local_pos = board.to_local(click_pos)
		var cell = board.local_to_map(local_pos)

		var piece = _piece_at_cell(cell)
		if piece != null:
			piece_clicked(piece)
		else:
			empty_tile_clicked(cell)

func _piece_at_cell(cell: Vector2) -> Area2D:
	# Iterate all pieces and check which one is at cell (assuming you store pieces with grid coord)
	# You need to implement storing piece coords on grid to make this work.
	for piece in get_tree().root.get_node("Main/RedPieces").get_children():
		if piece_has_coord(piece, cell):
			return piece
	for piece in get_tree().root.get_node("Main/BluePieces").get_children():
		if piece_has_coord(piece, cell):
			return piece
	return null

func piece_has_coord(piece: Area2D, cell: Vector2) -> bool:
	# Implement how you store piece grid coordinates (e.g., piece.coord or piece.position mapped)
	var piece_cell = Vector2(board.local_to_map(piece.position))
	return piece_cell == cell

func empty_tile_clicked(cell: Vector2):
	if selected_piece == null:
		return # no piece selected, do nothing

	# Attempt to move selected piece to clicked cell if move is valid
	if can_move_to_cell(selected_piece, cell):
		move_piece_to_cell(selected_piece, cell)
		selected_piece.deselect()
		selected_piece = null
	else:
		# invalid move, you can play a sound or show message
		print("Invalid move")

func can_move_to_cell(piece: Area2D, cell: Vector2) -> bool:
	# Implement Stratego movement rules here, for example:
	#  - check lake squares
	#  - check adjacency or scout rules
	#  - check if destination is empty
	#  - etc.
	return true
func move_piece_to_cell(piece: Area2D, cell: Vector2):
	var board_tilemap := board as TileMap
	var cell_size = Vector2(board.tile_set.tile_size)
	var new_pos = board_tilemap.map_to_local(cell) + cell_size / 2
	piece.position = new_pos

	# Update your game state logic here, call GameController etc.
