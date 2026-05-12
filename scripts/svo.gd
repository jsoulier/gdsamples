@tool class_name SVO extends Node3D

static var EMPTY: int = -1
static var SOLID: int = -2
static var DEBUG_COLOR: Color = Color(0.2, 0.8, 0.4, 1.0)

@export var scene: Node3D = null
@export_range(1, 12) var max_depth: int = 7
@export_range(1, 12) var debug_depth: int = 10
@export_dir var out_data: String = "res://data/"

var _nodes: Array = []
var _origin: Vector3 = Vector3.ZERO
var _size: float = 1.0
var _debug_lines: Array[Array] = []

func _new_node() -> int:
	var index: int = _nodes.size()
	_nodes.append([EMPTY, EMPTY, EMPTY, EMPTY, EMPTY, EMPTY, EMPTY, EMPTY])
	return index

func _enter_tree() -> void:
	if Engine.is_editor_hint():
		var palette = EditorInterface.get_command_palette()
		palette.add_command("SVO: Build", "svo/build", _build)

func _exit_tree() -> void:
	if Engine.is_editor_hint():
		var palette = EditorInterface.get_command_palette()
		palette.remove_command("svo/build")

func _ready() -> void:
	_get_debug_lines()

func _process(_delta: float) -> void:
	if not visible:
		return
	if debug_depth >= _debug_lines.size():
		return
	var level: Array = _debug_lines[debug_depth]
	for i in range(level.size() / 2):
		DebugDraw3D.draw_line(level[i * 2], level[i * 2 + 1], DEBUG_COLOR)

func _build() -> void:
	print("Building SVO for %s" % scene.name)
	var aabbs: Array[AABB] = []
	_get_aabbs(scene, Transform3D.IDENTITY, aabbs)
	if aabbs.is_empty():
		push_error("Failed to collect any AABBs for %s" % scene.name)
		return
	print("Collected %d AABBs" % aabbs.size())
	var scene_min: Vector3 = Vector3(INF, INF, INF)
	var scene_max: Vector3 = Vector3(-INF, -INF, -INF)
	for aabb: AABB in aabbs:
		scene_min = scene_min.min(aabb.position)
		scene_max = scene_max.max(aabb.end)
	var padding: Vector3 = (scene_max - scene_min) * 0.005 + Vector3.ONE * 0.001
	scene_min -= padding
	scene_max += padding
	var extents: Vector3 = scene_max - scene_min
	_origin = scene_min
	_size = maxf(extents.x, maxf(extents.y, extents.z))
	_nodes.clear()
	_new_node()
	_subdivide(aabbs, 0, _origin, _size, 0)
	print("Collected %d nodes" % _nodes.size())
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_data))
	_export_binary()
	_export_metadata()
	if Engine.is_editor_hint():
		EditorInterface.get_resource_filesystem().scan()
	print("Built SVO for %s" % scene.name)
	_get_debug_lines()

func _get_aabbs(node: Node, xform: Transform3D, out: Array[AABB]) -> void:
	if node is Node3D:
		xform = xform * (node as Node3D).transform
	if node is MeshInstance3D:
		var mesh: Mesh = (node as MeshInstance3D).mesh
		if mesh:
			out.append(xform * mesh.get_aabb())
	for child in node.get_children():
		_get_aabbs(child, xform, out)

func _subdivide(aabbs: Array[AABB], index: int, _min: Vector3, size: float, depth: int) -> void:
	var half: float = size * 0.5
	for slot in range(8):
		var child_min: Vector3 = _min + Vector3(
			half if (slot & 1) else 0.0,
			half if (slot & 2) else 0.0,
			half if (slot & 4) else 0.0)
		var child_max: Vector3 = child_min + Vector3(half, half, half)
		var cell: AABB = AABB(child_min, child_max - child_min)
		var _aabbs: Array[AABB] = []
		var is_solid: bool = false
		for aabb: AABB in aabbs:
			if aabb.encloses(cell):
				is_solid = true
				break
			if aabb.intersects(cell):
				_aabbs.append(aabb)
		if is_solid:
			_nodes[index][slot] = SOLID
			continue
		if _aabbs.is_empty():
			continue
		if depth == max_depth - 1:
			_nodes[index][slot] = SOLID
			continue
		var child_index: int = _new_node()
		_nodes[index][slot] = child_index
		_subdivide(_aabbs, child_index, child_min, half, depth + 1)
		is_solid = true
		for node in _nodes[child_index]:
			if node != SOLID:
				is_solid = false
		if is_solid:
			_nodes[index][slot] = SOLID

func _export_binary() -> void:
	var path: String = ProjectSettings.globalize_path(out_data.path_join("svo.bin"))
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("Failed to write to %s" % path)
		return
	for node in _nodes:
		for value in node:
			file.store_32(value)
	file.close()

func _export_metadata() -> void:
	var metadata: Dictionary = {
		"root_min_x": _origin.x,
		"root_min_y": _origin.y,
		"root_min_z": _origin.z,
		"root_size": _size,
		"max_depth": max_depth,
		"node_count": _nodes.size(),
	}
	var path: String = ProjectSettings.globalize_path(out_data.path_join("svo.json"))
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("Failed to write to %s" % path)
		return
	file.store_string(JSON.stringify(metadata, "\t"))
	file.close()

func _get_debug_lines() -> void:
	var binary_path: String = out_data.path_join("svo.bin")
	var metadata_path: String = out_data.path_join("svo.json")
	if not FileAccess.file_exists(binary_path) or not FileAccess.file_exists(metadata_path):
		return
	var metadata_file: FileAccess = FileAccess.open(metadata_path, FileAccess.READ)
	if metadata_file == null:
		push_error("Failed to open SVO %s" % metadata_path)
		return
	var metadata: Dictionary = JSON.parse_string(metadata_file.get_as_text())
	metadata_file.close()
	var root_min: Vector3 = Vector3(metadata.root_min_x, metadata.root_min_y, metadata.root_min_z)
	var root_size: float = float(metadata.root_size)
	var _max_depth: int = int(metadata.max_depth)
	var node_count: int = int(metadata.node_count)
	var binary_file: FileAccess = FileAccess.open(binary_path, FileAccess.READ)
	if binary_file == null:
		push_error("Failed to open SVO %s" % binary_path)
		return
	var nodes: PackedInt32Array = PackedInt32Array()
	nodes.resize(node_count * 8)
	for i in range(nodes.size()):
		nodes[i] = binary_file.get_32()
	binary_file.close()
	_debug_lines.resize(_max_depth + 1)
	for depth in range(_max_depth + 1):
		_debug_lines[depth] = []
	var stack: Array = [[0, root_min, root_size, 0]]
	while not stack.is_empty():
		var element: Array = stack.pop_back()
		var index: int = element[0]
		var _min: Vector3 = element[1]
		var size: float = element[2]
		var depth: int = element[3]
		if depth == 0:
			_add_debug_box(_min, _min + Vector3(size, size, size), 0)
		var half: float = size * 0.5
		for slot in range(8):
			var child_index: int = nodes[index * 8 + slot]
			if child_index == EMPTY:
				continue
			var child_min: Vector3 = _min + Vector3(
				half if (slot & 1) else 0.0,
				half if (slot & 2) else 0.0,
				half if (slot & 4) else 0.0)
			_add_debug_box(child_min, child_min + Vector3(half, half, half), depth + 1)
			if child_index != SOLID and depth + 1 < _max_depth:
				stack.push_back([child_index, child_min, half, depth + 1])

func _add_debug_box(bmin: Vector3, bmax: Vector3, depth: int) -> void:
	if depth >= _debug_lines.size():
		return
	var cell: Array[Vector3] = [
		Vector3(bmin.x, bmin.y, bmin.z),
		Vector3(bmax.x, bmin.y, bmin.z),
		Vector3(bmax.x, bmax.y, bmin.z),
		Vector3(bmin.x, bmax.y, bmin.z),
		Vector3(bmin.x, bmin.y, bmax.z),
		Vector3(bmax.x, bmin.y, bmax.z),
		Vector3(bmax.x, bmax.y, bmax.z),
		Vector3(bmin.x, bmax.y, bmax.z),
	]
	const EDGES = [
		[0,1],[1,2],[2,3],[3,0],
		[4,5],[5,6],[6,7],[7,4],
		[0,4],[1,5],[2,6],[3,7]
	]
	for edge in EDGES:
		_debug_lines[depth].append(cell[edge[0]])
		_debug_lines[depth].append(cell[edge[1]])
