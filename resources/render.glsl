#[vertex]
#version 450

#define DEBUG_OCCLUDED 1
#define DEBUG_UNOCCLUDED 2
#define DEBUG 0

struct Boid {
    vec3 position;
    int flags;
    vec3 forward;
    float padding1;
    vec3 next_forward;
    float padding2;
    vec3 velocity;
    float padding3;
    vec3 acceleration;
    float padding4;
};

layout(location = 0) in vec3 in_position;
layout(set = 0, binding = 0, std430) readonly buffer BoidBuffer {
	Boid boids[];
};
layout(push_constant, std430) uniform Params {
	mat4 view_proj;
} params;
layout(location = 0) out vec3 out_color;

mat3 get_basis(vec3 forward) {
	forward = normalize(forward);
	vec3 up;
	if (abs(forward.y) < 0.999) {
		up = vec3(0.0, 1.0, 0.0);
	} else {
		up = vec3(1.0, 0.0, 0.0);
	}
	vec3 right = normalize(cross(up, forward));
	up = cross(forward, right);
	return mat3(right, forward, up);
}

void main() {
	Boid boid = boids[gl_InstanceIndex];
	vec3 position = boid.position.xyz;
	vec3 forward = boid.forward.xyz;
	mat3 basis = get_basis(forward);
	gl_Position = params.view_proj * vec4(position + basis * in_position, 1.0);
#if DEBUG
	if (bool(boid.flags & DEBUG_UNOCCLUDED)) {
		out_color = vec3(0.0, 1.0, 0.0);
	} else if (bool(boid.flags & DEBUG_OCCLUDED)) {
		out_color = vec3(1.0, 0.0, 0.0);
	} else {
#endif
		out_color = mix(vec3(1.0, 1.0, 1.0), vec3(0.0, 0.0, 1.0), length(boid.velocity) * 0.25);
#if DEBUG
	}
#endif
}

#[fragment]
#version 450

layout(location = 0) in vec3 in_color;
layout(location = 0) out vec4 out_color;

void main() {
	out_color = vec4(in_color, 1.0);
}
