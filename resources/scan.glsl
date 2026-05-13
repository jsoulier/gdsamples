#[compute]
#version 450

#define DEBUG_OCCLUDED 1
#define DEBUG_UNOCCLUDED 2
#define GOLDEN_ANGLE 2.39996323
#define EMPTY -1
#define SOLID -2

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
layout(set = 0, binding = 1, std430) readonly buffer SvoBuffer {
    int nodes[];
} svo;
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

vec3 steer_towards(vec3 direction, vec3 velocity) {
    float _length = length(direction);
    if (_length < 0.0001) {
        return vec3(0.0);
    }
    velocity = normalize(direction) * params.max_speed - velocity;
    if (length(velocity) < 0.0001) {
        return vec3(0.0);
    }
    _length = length(velocity);
    if (_length > params.max_steer_force) {
        velocity = velocity / _length * params.max_steer_force;
    }
    return velocity;
}

bool is_occluded(vec3 position) {
    vec3 node_min = vec3(params.svo_min_x, params.svo_min_y, params.svo_min_z);
    float size = params.svo_size;
    vec3 local = position - node_min;
    if (any(lessThan(local, vec3(0.0))) || any(greaterThanEqual(local, vec3(size)))) {
        return true;
    }
    int node_index = 0;
    for (int depth = 0; depth < int(params.svo_max_depth); depth++) {
        float half_size = size * 0.5;
        vec3 center = node_min + vec3(half_size);
        int slot = 0;
        if (position.x >= center.x) slot |= 1;
        if (position.y >= center.y) slot |= 2;
        if (position.z >= center.z) slot |= 4;
        node_min += vec3(
            (slot & 1) != 0 ? half_size : 0.0,
            (slot & 2) != 0 ? half_size : 0.0,
            (slot & 4) != 0 ? half_size : 0.0
        );
        size = half_size;
        int child = svo.nodes[node_index * 8 + slot];
        if (child == SOLID) {
            return true;
        } else if (child == EMPTY) {
            return false;
        } else {
            node_index = child;
        }
    }
    return true;
}

void main() {
    int id = int(gl_GlobalInvocationID.x);
    if (id >= int(params.num_boids)) {
        return;
    }
    boids[id].flags = 0;
    vec3 position = boids[id].position.xyz;
    vec3 forward = boids[id].forward.xyz;
    vec3 velocity = boids[id].velocity.xyz;
    vec3 flock_heading = vec3(0.0);
    vec3 flock_center  = vec3(0.0);
    vec3 avoidance = vec3(0.0);
    int num_mates = 0;
    for (int b = 0; b < int(params.num_boids); b++) {
        if (b == id) {
            continue;
        }
        vec3 offset = boids[b].position.xyz - position;
        float distance_sqr = dot(offset, offset);
        if (distance_sqr < params.view_radius * params.view_radius) {
            num_mates++;
            flock_heading += boids[b].forward.xyz;
            flock_center += boids[b].position.xyz;
            if (distance_sqr < params.avoid_radius * params.avoid_radius) {
                avoidance -= offset / max(distance_sqr, 0.0001);
            }
        }
    }
    vec3 acceleration = vec3(0.0);
    acceleration += steer_towards(forward, velocity) * params.forward_weight;
    if (num_mates > 0) {
        flock_center /= float(num_mates);
        vec3 offset_to_center = flock_center - position;
        acceleration += steer_towards(flock_heading, velocity) * params.align_weight;
        acceleration += steer_towards(offset_to_center, velocity) * params.cohesion_weight;
        acceleration += steer_towards(avoidance, velocity) * params.separate_weight;
    }
    if (is_occluded(position + forward * params.sensor_length)) {
        boids[id].flags |= DEBUG_OCCLUDED;
        vec3 up;
        if (abs(forward.y) < 0.99) {
            up = vec3(0.0, 1.0, 0.0);
        } else {
            up = vec3(1.0, 0.0, 0.0);
        }
        vec3 right = normalize(cross(up, forward));
        up = cross(forward, right);
        vec3 direction = forward;
        bool found_unoccluded = false;
        for (int i = 0; i < int(params.sensor_count); i++) {
            float t = float(i) / float(params.sensor_count - 1);
            float cos_theta = 1.0 - 2.0 * t;
            float sin_theta = sqrt(max(0.0, 1.0 - cos_theta * cos_theta));
            float phi = float(i) * GOLDEN_ANGLE;
            direction = normalize(right * cos(phi) * sin_theta + up * sin(phi) * sin_theta + forward * cos_theta);
            if (!is_occluded(position + direction * params.sensor_length)) {
                found_unoccluded = true;
                break;
            }
        }
        if (found_unoccluded) {
            acceleration += steer_towards(direction, velocity) * params.collision_weight;
            boids[id].flags |= DEBUG_UNOCCLUDED;
        }
    }
    velocity += acceleration * params.delta_time;
    float speed = length(velocity);
    vec3 direction;
    if (speed > 0.0001) {
        direction = velocity / speed;
    } else {
        direction = forward;
    }
    speed = clamp(speed, params.min_speed, params.max_speed);
    velocity = direction * speed;
    boids[id].next_forward = direction;
    boids[id].velocity = velocity;
    boids[id].acceleration = acceleration;
}
