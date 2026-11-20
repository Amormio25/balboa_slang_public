[shader("compute")]
[numthreads(64, 1, 1)]
void predict(uint tid : SV_DispatchThreadID,
             // Updated position
             RWStructuredBuffer<float3> positions,
             // Store the position before update
             RWStructuredBuffer<float3> old_positions,
             RWStructuredBuffer<float3> velocities,
             StructuredBuffer<float> inv_masses,
             uniform uint num_particles,
             // time step size
             uniform float dt) {
    if (tid >= num_particles) {
        return;
    }
    // TODO: HW 4.2. Your code below.
    // inf mass one is ball not moving so its inv mass should be 0
    // remember each thread corresponds to one particle 

    float3 gravity = float3(0, -9.8, 0);
    float3 pos = positions[tid];
    float3 v = velocities[tid];

    old_positions[tid] = pos;

    if (inv_masses[tid] != 0) {
        v += gravity * dt;
        pos += v * dt;
    }
    positions[tid] = pos;
    velocities[tid] = v;

    return;
}

[shader("compute")]
[numthreads(64, 1, 1)]
void project_constraints(uint tid : SV_DispatchThreadID,
                         StructuredBuffer<float3> positions_in,
                         RWStructuredBuffer<float3> positions_out,
                         StructuredBuffer<float> inv_masses,
                         StructuredBuffer<float> rest_lengths,
                         uniform uint num_particles) {
    if (tid >= num_particles) {
        return;
    }
    // TODO: HW 4.2. Your code below.

    // for each ball in range 1, num_particles-2
    //      average corrections from prev and next
    //      the corrections depend on the inv_masses

    float3 xi = positions_in[tid];
    float wi = inv_masses[tid];

    // inf mass should stay put
    if (wi == 0.0) {
        positions_out[tid] = xi;
        return;
    }

    // each ball after first and before last will have two neighbors
    // should average corrections
    float3 correction = 0;
    int num_corrections = 0;
    if (tid > 0) {
        int prev = tid-1;
        correction += get_correction(xi, positions_in[prev], wi, inv_masses[prev], rest_lengths[tid-1]);
        num_corrections += 1;
    }

    if (tid < num_particles - 1) {
        int next = tid+1;

        // rest length tid is the one between ball and ball+1
        correction += get_correction(xi, positions_in[next], wi, inv_masses[next], rest_lengths[tid]);
        num_corrections += 1;
    }

    if (num_corrections > 0) {
        correction /= num_corrections;
    }

    positions_out[tid] = xi + correction;
}

float3 get_correction(float3 pos_original, float3 pos_neighbor, float inv_mass_original, float inv_mass_neighbor, float rest_length_neighbor) {
    float distance = length(pos_neighbor - pos_original);

    // basically next to each other or zero inv mass, so don't divide by distance
    if (distance < 1e-8 || inv_mass_original + inv_mass_neighbor <= 0.0) {
        return float3(0.0);
    }

    float err = distance - rest_length_neighbor;

    // move the ball along the direction by its mass share times the error
    return (inv_mass_original / (inv_mass_original + inv_mass_neighbor) 
            * err 
            * ((pos_neighbor - pos_original) / distance));

}

[shader("compute")]
[numthreads(64, 1, 1)]
void update_velocity(uint tid : SV_DispatchThreadID,
                     RWStructuredBuffer<float3> positions,
                     StructuredBuffer<float3> old_positions,
                     RWStructuredBuffer<float3> velocities,
                     StructuredBuffer<float> inv_masses,
                     uniform uint num_particles,
                     // time step size
                     uniform float dt) {
    if (tid >= num_particles) {
        return;
    }
    // TODO: HW 4.2. Your code below.
    float3 pos = positions[tid];
    float3 old_pos = old_positions[tid];
    if (inv_masses[tid] != 0.0) {
        if (pos.y < -0.97) {
            pos.y = -0.97;
        }
        positions[tid] = pos;
        velocities[tid] = (pos - old_pos) / dt;
    } else {
        positions[tid] = pos;
        velocities[tid] = float3(0.0);
    }

    return;
}
