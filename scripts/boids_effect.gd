class_name BoidsEffect extends CompositorEffect

static var RENDER_SHADER: RDShaderFile = preload("res://resources/render.glsl")

var boids: Boids = null
var _device: RenderingDevice = null
var _vertex_buffer: RID
var _vertex_array: RID
var _uniform_set: RID
var _pipeline: RID
var _shader: RID
var _vertex_count: int
var _framebuffer_format: int = -1

func _init() -> void:
	effect_callback_type = CompositorEffect.EFFECT_CALLBACK_TYPE_POST_OPAQUE
	RenderingServer.call_on_render_thread(_render_init.bind())

func _render_init() -> void:
	_device = RenderingServer.get_rendering_device()
	const SEGMENTS = 6
	const RADIUS = 0.1
	const HEIGHT = 0.2
	var vertices: PackedFloat32Array = PackedFloat32Array()
	for i in range(SEGMENTS):
		var a0: float = (float(i) / SEGMENTS) * TAU
		var a1: float = (float(i + 1) / SEGMENTS) * TAU
		var b0: Vector3 = Vector3(cos(a0) * RADIUS, 0.0, sin(a0) * RADIUS)
		var b1: Vector3 = Vector3(cos(a1) * RADIUS, 0.0, sin(a1) * RADIUS)
		var tip: Vector3 = Vector3(0.0, HEIGHT, 0.0)
		vertices.append_array([tip.x, tip.y, tip.z, b0.x, b0.y, b0.z, b1.x, b1.y, b1.z])
		vertices.append_array([0.0, 0.0, 0.0, b1.x, b1.y, b1.z, b0.x, b0.y, b0.z])
	_vertex_buffer = _device.vertex_buffer_create(vertices.size() * 4, vertices.to_byte_array())
	_vertex_count = SEGMENTS * 2 * 3

func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		for rid in [_vertex_buffer, _pipeline, _shader, _uniform_set]:
			if rid.is_valid():
				_device.free_rid(rid)

func _render_callback(_effect_callback_type: int, render_data: RenderData) -> void:
	var render_scene_buffers: RenderSceneBuffers = render_data.get_render_scene_buffers()
	var color = render_scene_buffers.get_color_layer(0)
	var depth = render_scene_buffers.get_depth_layer(0)
	if not color.is_valid() or not depth.is_valid():
		return
	var framebuffer: RID = _device.framebuffer_create([color, depth])
	var framebuffer_format: int = _device.framebuffer_get_format(framebuffer)
	if framebuffer_format != _framebuffer_format:
		_build_render_pipeline(framebuffer_format)
		_framebuffer_format = framebuffer_format
	var render_scene_data: RenderSceneData = render_data.get_render_scene_data()
	var view: Transform3D = render_scene_data.get_cam_transform().inverse()
	var view_proj: Projection = render_scene_data.get_cam_projection() * Projection(view)
	var push: PackedFloat32Array = PackedFloat32Array()
	push.resize(16)
	for col in range(4):
		for row in range(4):
			push[col * 4 + row] = view_proj[col][row]
	var draw_list: int = _device.draw_list_begin(framebuffer, RenderingDevice.DRAW_DEFAULT_ALL, [])
	_device.draw_list_bind_render_pipeline(draw_list, _pipeline)
	_device.draw_list_bind_uniform_set(draw_list, _uniform_set, 0)
	_device.draw_list_bind_vertex_array(draw_list, _vertex_array)
	_device.draw_list_set_push_constant(draw_list, push.to_byte_array(), push.size() * 4)
	_device.draw_list_draw(draw_list, false, boids.boid_count)
	_device.draw_list_end()
	_device.free_rid(framebuffer)

func _build_render_pipeline(framebuffer_format: int) -> void:
	if _vertex_array.is_valid():
		_device.free_rid(_vertex_array)
	if _uniform_set.is_valid():
		_device.free_rid(_uniform_set)
	if _shader.is_valid():
		_device.free_rid(_shader)
	if _pipeline.is_valid():
		_device.free_rid(_pipeline)
	var attribute: RDVertexAttribute = RDVertexAttribute.new()
	attribute.location = 0
	attribute.format = RenderingDevice.DATA_FORMAT_R32G32B32_SFLOAT
	attribute.stride = 12
	attribute.offset = 0
	var vertex_format = _device.vertex_format_create([attribute])
	_vertex_array = _device.vertex_array_create(_vertex_count, vertex_format, [_vertex_buffer])
	var blend_state: RDPipelineColorBlendState = RDPipelineColorBlendState.new()
	blend_state.attachments.append(RDPipelineColorBlendStateAttachment.new())
	var depth_stencil_state: RDPipelineDepthStencilState = RDPipelineDepthStencilState.new()
	depth_stencil_state.enable_depth_test = true
	depth_stencil_state.enable_depth_write = true
	depth_stencil_state.depth_compare_operator = RenderingDevice.COMPARE_OP_GREATER_OR_EQUAL
	var rasterization_state: RDPipelineRasterizationState = RDPipelineRasterizationState.new()
	rasterization_state.cull_mode = RenderingDevice.POLYGON_CULL_BACK
	_shader = _device.shader_create_from_spirv(RENDER_SHADER.get_spirv())
	_pipeline = _device.render_pipeline_create(
		_shader,
		framebuffer_format,
		vertex_format,
		RenderingDevice.RENDER_PRIMITIVE_TRIANGLES,
		rasterization_state,
		RDPipelineMultisampleState.new(),
		depth_stencil_state,
		blend_state
	)
	var uniform: RDUniform = RDUniform.new()
	uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	uniform.binding = 0
	uniform.add_id(boids._boid_buffer)
	_uniform_set = _device.uniform_set_create([uniform], _shader, 0)
