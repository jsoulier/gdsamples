class_name Boids extends Node3D

static var SCAN_SHADER: RDShaderFile = preload("res://resources/scan.glsl")
static var UPDATE_SHADER: RDShaderFile = preload("res://resources/update.glsl")

@export var svo: SVO = null
@export var boid_count: int = 100
@export var view_radius: float = 5.0
@export var avoid_radius: float = 2.0
@export var min_speed: float = 1.0
@export var max_speed: float = 5.0
@export var max_steer_force: float = 5.0
@export var align_weight: float = 1.0
@export var cohesion_weight: float = 1.0
@export var separate_weight: float = 1.5
@export var forward_weight: float = 0.5
@export var sensor_length: float = 0.2
@export_range(1, 100) var sensor_count: int = 50
@export var collision_weight: float = 10.0

var _device: RenderingDevice = null
var _boid_buffer: RID
var _svo_buffer: RID
var _scan_shader: RID
var _scan_pipeline: RID
var _scan_uniform_set: RID
var _update_shader: RID
var _update_pipeline: RID
var _update_uniform_set: RID
var _svo_metadata: Dictionary = {}

func _ready() -> void:
	_device = RenderingServer.get_rendering_device()
	var boid_data: PackedFloat32Array = PackedFloat32Array()
	boid_data.resize(boid_count * 20)
	boid_data.fill(0.0)
	for i in range(boid_count):
		var base: int = i * 20
		var _position: Vector3 = Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1))
		var forward: Vector3 = Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)).normalized()
		boid_data[base + 0] = global_position.x + _position.x
		boid_data[base + 1] = global_position.y + _position.y
		boid_data[base + 2] = global_position.z + _position.z
		boid_data[base + 3] = 0.0
		boid_data[base + 4] = forward.x
		boid_data[base + 5] = forward.y
		boid_data[base + 6] = forward.z
		boid_data[base + 7] = 0.0
	_boid_buffer = _device.storage_buffer_create(boid_data.size() * 4, boid_data.to_byte_array())
	_svo_metadata = svo.get_metadata()
	if _svo_metadata.is_empty():
		push_error("Failed to load SVO metadata")
		return
	var bytes: PackedByteArray = svo.get_binary()
	if bytes.is_empty():
		push_error("Failed to load SVO binary")
		return
	_svo_buffer = _device.storage_buffer_create(bytes.size(), bytes)
	_scan_shader = _device.shader_create_from_spirv(SCAN_SHADER.get_spirv())
	_scan_pipeline = _device.compute_pipeline_create(_scan_shader)
	_update_shader = _device.shader_create_from_spirv(UPDATE_SHADER.get_spirv())
	_update_pipeline = _device.compute_pipeline_create(_update_shader)
	var boid_uniform: RDUniform = RDUniform.new()
	boid_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	boid_uniform.binding = 0
	boid_uniform.add_id(_boid_buffer)
	var svo_uniform: RDUniform = RDUniform.new()
	svo_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	svo_uniform.binding = 1
	svo_uniform.add_id(_svo_buffer)
	_scan_uniform_set = _device.uniform_set_create([boid_uniform, svo_uniform], _scan_shader, 0)
	_update_uniform_set = _device.uniform_set_create([boid_uniform], _update_shader, 0)
	var effect: BoidsEffect = BoidsEffect.new()
	effect.boids = self
	var compositor: Compositor = Compositor.new()
	compositor.compositor_effects = [effect]
	var camera: Camera3D = get_viewport().get_camera_3d()
	camera.compositor = compositor

func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		for rid in [_boid_buffer, _scan_pipeline, _scan_shader, _scan_uniform_set, \
				_update_pipeline, _update_shader, _update_uniform_set]:
			if rid.is_valid():
				_device.free_rid(rid)

func _process(delta: float) -> void:
	var push: PackedFloat32Array = PackedFloat32Array()
	push.resize(20)
	push[0] = float(boid_count)
	push[1] = view_radius
	push[2] = avoid_radius
	push[3] = min_speed
	push[4] = max_speed
	push[5] = max_steer_force
	push[6] = align_weight
	push[7] = cohesion_weight
	push[8] = separate_weight
	push[9] = delta
	push[10] = forward_weight
	push[11] = float(_svo_metadata.root_min_x)
	push[12] = float(_svo_metadata.root_min_y)
	push[13] = float(_svo_metadata.root_min_z)
	push[14] = float(_svo_metadata.root_size)
	push[15] = float(_svo_metadata.max_build_depth)
	push[16] = sensor_length
	push[17] = float(sensor_count)
	push[18] = collision_weight
	push[19] = 0.0
	@warning_ignore("integer_division")
	var group_count = (boid_count + 1023) / 1024
	var compute_list: int = _device.compute_list_begin()
	_device.compute_list_bind_compute_pipeline(compute_list, _scan_pipeline)
	_device.compute_list_bind_uniform_set(compute_list, _scan_uniform_set, 0)
	_device.compute_list_set_push_constant(compute_list, push.to_byte_array(), push.size() * 4)
	_device.compute_list_dispatch(compute_list, group_count, 1, 1)
	_device.compute_list_end()
	compute_list = _device.compute_list_begin()
	_device.compute_list_bind_compute_pipeline(compute_list, _update_pipeline)
	_device.compute_list_bind_uniform_set(compute_list, _update_uniform_set, 0)
	_device.compute_list_set_push_constant(compute_list, push.to_byte_array(), push.size() * 4)
	_device.compute_list_dispatch(compute_list, group_count, 1, 1)
	_device.compute_list_end()
