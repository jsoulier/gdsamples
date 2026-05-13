#[compute]
#version 450

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

layout(local_size_x = 1024, local_size_y = 1, local_size_z = 1) in;
layout(set = 0, binding = 0, std430) restrict buffer BoidBuffer {
    Boid boids[];
};
layout(push_constant, std430) uniform Params {
    float num_boids;
    float view_radius;
    float avoid_radius;
    float min_speed;
    float max_speed;
    float max_steer_force;
    float align_weight;
    float cohesion_weight;
    float separate_weight;
    float delta_time;
    float forward_weight;
    float svo_min_x;
    float svo_min_y;
    float svo_min_z;
    float svo_size;
    float svo_max_depth;
    float sensor_length;
    float sensor_count;
    float collision_weight;
    float padding0;
} params;

void main() {
    int id = int(gl_GlobalInvocationID.x);
    if (id >= int(params.num_boids)) {
        return;
    }
    boids[id].position += boids[id].velocity * params.delta_time;
    boids[id].forward = boids[id].next_forward;
}
