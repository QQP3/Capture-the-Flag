# GameController.gd
# A single-file rules manager for Stratego in Godot (GDScript).
# Drop this script on a Node (e.g. "GameController") in your scene tree.
# Assumptions about Piece nodes in the scene:
# - Each piece is a Node2D (or subclass) with exported or settable properties:
#     var rank : int       # 10 = Marshal, 9 = General, ... 1 = Scout, 0 = Spy, -1 = Bomb, -2 = Flag
#     var team : String    # "red" or "blue"
#     var movable : bool   # false for Bomb and Flag
#     var special : String # optional: e.g. "miner", "spy", "scout"
# - Piece node should provide methods or be moved by GameController (move_piece handles board array)
# - Coordinates are Vector2(x, y) where x, y in [0,9]; x is column(A..J), y is row(0..9) bottom-to-top by your mapping
# Integration hints (see bottom comments for usage examples)

extends Node

signal move_made(src, dest, piece)
signal attack_resolved(attacker, defender, result)
signal game_over(winner)

const BOARD_SIZE = 10

# lake coordinates (0-based). These are the lakes that cannot be entered.
var lakes = [
	Vector2(2,4), Vector2(3,4), Vector2(6,4), Vector2(7,4),
	Vector2(2,5), Vector2(3,5), Vector2(6,5), Vector2(7,5)
]

# 2D array board[y][x] -> stores reference to piece node or null
var board = []

# track pieces by team for convenience
var pieces_by_team = {
	"red": [],
	"blue": []
}

# turn: "red" or "blue". Red moves first by default
var turn = "red"

# history for optional replay/debugging: array of dictionaries
var history = []

# simple anti-stall trackers
var last_two_moves = [] # store tuples of (src, dest, piece)

func _ready():
	_init_board()

func _init_board():
	board.clear()
	for y in range(BOARD_SIZE):
		var row = []
		for x in range(BOARD_SIZE):
			row.append(null)
		board.append(row)
	pieces_by_team["red"].clear()
	pieces_by_team["blue"].clear()
	history.clear()
	last_two_moves.clear()

# Register a piece on the board at a given coord. Called when pieces are created/placed.
func register_piece(piece, coord: Vector2) -> void:
	var x = int(coord.x)
	var y = int(coord.y)
	if not _in_bounds(coord):
		push_error("register_piece: coord out of bounds: %s" % coord)
		return
	board[y][x] = piece
	if piece.team in pieces_by_team:
		pieces_by_team[piece.team].append(piece)
	else:
		pieces_by_team[piece.team] = [piece]
	# keep piece aware of its logical coord
	piece.set("coord", coord)

# Unregister a piece (when captured or removed from board)
func unregister_piece(piece) -> void:
	var coord = piece.get("coord") if piece.has_method("get") or piece.has_meta else null
	if coord != null and _in_bounds(coord):
		board[int(coord.y)][int(coord.x)] = null
	if piece.team in pieces_by_team and piece in pieces_by_team[piece.team]:
		pieces_by_team[piece.team].erase(piece)

# Helper
func _in_bounds(coord: Vector2) -> bool:
	return coord.x >= 0 and coord.x < BOARD_SIZE and coord.y >= 0 and coord.y < BOARD_SIZE

func _is_lake(coord: Vector2) -> bool:
	for l in lakes:
		if int(l.x) == int(coord.x) and int(l.y) == int(coord.y):
			return true
	return false

# Public: try to move a piece from src to dest. Returns true if move succeeded.
# This performs validation, resolves attacks, switches turns, emits signals and records history.
func attempt_move(src: Vector2, dest: Vector2) -> bool:
	if not _in_bounds(src) or not _in_bounds(dest):
		return false
	var piece = board[int(src.y)][int(src.x)]
	if piece == null:
		return false
	if piece.team != turn:
		return false
	# immobile pieces cannot move
	if not piece.movable:
		return false	
		
	# same-square or invalid
	if src == dest:
		return false	
	
	# lake check
	if _is_lake(dest):
		return false	
	
	# destination occupied
	var dest_piece = board[int(dest.y)][int(dest.x)]
	if dest_piece != null and dest_piece.team == piece.team:
		return false # cannot capture own piece	
	# movement rules
	if not _valid_movement(piece, src, dest):
		return false	
	# two-square/back-and-forth rule: prevent repeating same two squares 3 times
	if not _anti_stall_check(src, dest, piece):
		return false	
	# execute move or attack
	if dest_piece == null:
		_move_piece(piece, src, dest)
		_record_history({"type":"move","piece":piece,"from":src,"to":dest})
		emit_signal("move_made", src, dest, piece)
		_after_move()
		return true
	else:
		# attack
		var result = _resolve_attack(piece, dest_piece, src, dest)
		_record_history({"type":"attack","attacker":piece,"defender":dest_piece,"from":src,"to":dest,"result":result})
		emit_signal("attack_resolved", piece, dest_piece, result)
		_after_move()
		return true	
# Movement validation depending on rank/specials
func _valid_movement(piece, src: Vector2, dest: Vector2) -> bool:
	var dx = int(dest.x) - int(src.x)
	var dy = int(dest.y) - int(src.y)
	# must be straight line (no diagonal)
	if dx != 0 and dy != 0:
		return false
	# Scout special: rank == 1 ? (user-defined). We'll assume Scout rank == 1 for this file
	var is_scout = false
	if ("special" in piece and piece.special == "scout") or piece.rank == 1:
		is_scout = true
	if is_scout:
		# scouts can move any number of empty spaces in straight line, and may capture at endpoint
		if dx == 0 and dy == 0:
			return false
		var step = Vector2(sign(dx), sign(dy))
		var pos = src + step
		while pos != dest:
			# cannot pass through lakes or pieces
			if _is_lake(pos):
				return false
			if board[int(pos.y)][int(pos.x)] != null:
				return false
			pos += step
		return true
	else:
		# all others move one square orthogonally
		if abs(dx) + abs(dy) != 1:
			return false
		return true

# Anti-stall: prevent same piece shuttling between two squares indefinitely
func _anti_stall_check(src: Vector2, dest: Vector2, piece) -> bool:
	# push to last_two_moves and examine
	var move_tuple = {"src":src,"dest":dest,"piece":piece}
	# check if last two moves form a loop: A->B then B->A then A->B etc.
	if last_two_moves.size() >= 2:
		var a = last_two_moves[last_two_moves.size()-2]
		var b = last_two_moves[last_two_moves.size()-1]
		# compare coordinates
		if a.src == dest and a.dest == src and b.src == src and b.dest == dest:
			# Deny to prevent long loops. You can adapt to permit once and then warn.
			return false
	return true

# Moves the piece on the board array and updates piece.coord property
func _move_piece(piece, src: Vector2, dest: Vector2) -> void:
	board[int(src.y)][int(src.x)] = null
	board[int(dest.y)][int(dest.x)] = piece
	piece.set("coord", dest)
	# if piece node has a method to update its visual position (e.g., snap_to_grid), call it
	if piece.has_method("on_logical_move"):
		piece.call("on_logical_move", src, dest)
	# update last_two_moves
	last_two_moves.append({"src":src,"dest":dest,"piece":piece})
	if last_two_moves.size() > 4:
		last_two_moves.remove(0)

# Remove piece from board and scene if desired
func _capture_piece(piece) -> void:
	var coord = piece.get("coord") if piece.has_method("get") or piece.has_meta else null
	if coord != null and _in_bounds(coord):
		board[int(coord.y)][int(coord.x)] = null
	if piece.team in pieces_by_team and piece in pieces_by_team[piece.team]:
		pieces_by_team[piece.team].erase(piece)
	# optionally free the node; caller decides. We'll queue_free here by default
	if piece.get_parent() != null:
		piece.queue_free()

# Resolve attack between attacker and defender located at dest.
# Returns a dictionary with result information.
func _resolve_attack(attacker, defender, src: Vector2, dest: Vector2) -> Dictionary:
	# reveal both pieces (emit signal or call method so UI updates)
	if attacker.has_method("reveal"):
		attacker.call("reveal")
	if defender.has_method("reveal"):
		defender.call("reveal")

	var res = {"winner":null, "loser":null, "both_removed":false}

	# special: defender is Bomb
	if defender.rank == -1: # Bomb
		if ("special" in attacker and attacker.special == "miner") or attacker.rank == 3 or attacker.special == "miner":
			# miner defeats bomb
			res.winner = attacker
			res.loser = defender
			_capture_piece(defender)
			_move_piece(attacker, src, dest)
		else:
			res.winner = defender
			res.loser = attacker
			_capture_piece(attacker)
			# bomb remains
	# special: attacker is spy and attacks marshal (rank 10 assumed)
	elif ( ("special" in attacker and attacker.special == "spy") or attacker.rank == 0 ) and defender.rank == 10:
		res.winner = attacker
		res.loser = defender
		_capture_piece(defender)
		_move_piece(attacker, src, dest)
	else:
		# standard compare: higher numeric rank wins (note: convention could be 10 highest)
		if attacker.rank > defender.rank:
			res.winner = attacker
			res.loser = defender
			_capture_piece(defender)
			_move_piece(attacker, src, dest)
		elif attacker.rank < defender.rank:
			res.winner = defender
			res.loser = attacker
			_capture_piece(attacker)
			# defender remains on its square
		else:
			# equal ranks -> both removed
			res.both_removed = true
			_capture_piece(attacker)
			_capture_piece(defender)
	# After attack updates, check for flag capture
	if res.winner != null and res.winner.rank == -2:
		# flag captured (shouldn't be movable, but defensive)
		emit_signal("game_over", attacker.team)
	# check for win by elimination below after returning
	return res

# Called after each successful move/attack to switch turns and check end conditions
func _after_move() -> void:
	# push to history last_two_moves for anti-stall
	if last_two_moves.size() > 0:
		history.append(last_two_moves[last_two_moves.size()-1])
	# switch turn
	if (turn == "red"):
		turn = "blue"
	else:
		turn = "red"
	# check end conditions
	var winner = _check_win_conditions()
	if winner != null:
		emit_signal("game_over", winner)

# Check whether a team has lost: flag captured or no movable pieces left
func _check_win_conditions() -> String:
	# check flags exist
	for team in ["red","blue"]:
		var flag_exists = false
		var movable_exists = false
		for p in pieces_by_team[team]:
			if p.rank == -2:
				flag_exists = true
			if p.movable:
				movable_exists = true
		if not flag_exists:
			# team lost because flag missing
			return _opponent(team)
		if not movable_exists:
			# team cannot move -> opponent wins
			return _opponent(team)
	return ""

func _opponent(team: String) -> String:
	if team == "red":
		return "blue"
	else:
		return "red"

func _record_history(entry: Dictionary) -> void:
	history.append(entry)

# Utility to find a piece at coordinate
func piece_at(coord: Vector2):
	if not _in_bounds(coord):
		return null
	return board[int(coord.y)][int(coord.x)]

# Debug helper: print board to output using rank or '.'
func debug_print_board():
	var s = "\n"
	for y in range(BOARD_SIZE-1, -1, -1):
		for x in range(BOARD_SIZE):
			var p = board[y][x]
			if p == null:
				s += ". "
			else:
				s += str(p.rank) + " "
		s += "\n"
	print(s)

# ----------------------
# Integration notes (how to wire this to your scene)
# ----------------------
# - When setting up the initial positions, call register_piece(piece, coord) for every piece.
# - When the player clicks a piece and destination, call attempt_move(src_coord, dest_coord).
# - Connect to signals to update UI:
#     connect("move_made", self, "_on_move_made")
#     connect("attack_resolved", self, "_on_attack_resolved")
#     connect("game_over", self, "_on_game_over")
# - Piece nodes should implement optional methods:
#     func reveal(): show its front side
#     func on_logical_move(src, dest): animate between grid cells
# - This script manages the logical state (board array), not the visual node parenting. Keep piece nodes as children in a dedicated container for each player or all under one node.
# - You can extend this file to support:
#     * recording full algebraic notation
#     * saving/loading positions
#     * multiplayer authority checks (for networked play)
# ----------------------
# Example usage snippet (not part of the script):
# var gc = $GameController
# gc.register_piece($RedMarshal, Vector2(0,0))
# gc.register_piece($BlueFlag, Vector2(5,9))
# gc.attempt_move(Vector2(0,0), Vector2(0,1))
# ----------------------
# License: MIT-ish (use/modify as you like)
