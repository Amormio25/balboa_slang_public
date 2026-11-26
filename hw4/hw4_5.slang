[shader("compute")]
[numthreads(64, 1, 1)]
void detect_collision(uint tid : SV_DispatchThreadID,
                      StructuredBuffer<float3> positions,
                      StructuredBuffer<float> inv_masses,
                      // Plane stores (a, b, c, d) where ax+by+cz=d
                      // a, b, c are normalized to a unit 3D vector
                      StructuredBuffer<float4> planes,
                      // Sphere stores center (xyz) + radius (w)
                      StructuredBuffer<float4> spheres,
                      // Contact plane: dot(n, x) = d, with unit normal n
                      // Set to (0, 0, 0, 0) if there is no contact
                      RWStructuredBuffer<float4> contact_planes,
                      uniform uint num_particles,
                      uniform uint num_planes,
                      uniform uint num_spheres,
                      // How much should we shift the generated 
                      // contact plane in the normal direction
                      // (similar to how we shifted the floor by 0.03
                      //  earlier)
                      uniform float collision_distance,
                      // When the signed distance function
                      // evaluates to a value below 
                      // contact_margin + collision_distance
                      // (even when it's positive), we count the
                      // particle to be inside the collider and
                      // a collision event has happened.
                      uniform float contact_margin) {
    if (tid >= num_particles) {
        return;
    }
    // TODO: HW 4.5. Your code below.

    if (inv_masses[tid] == 0.0) {
        contact_planes[tid] = float4(0.0);
        return;
    }

    float3 pos = positions[tid];
    float min_sdf = 1e30;
    float3 best_n = float3(0.0);
    float best_d = 0.0;

    for (uint i = 0; i < num_planes; i++) {
        float4 pl = planes[i];
        float3 n = normalize(pl.xyz);
        float d = pl.w;
        float sdf = dot(n, pos) - d;
        if (sdf < min_sdf) {
            min_sdf = sdf;
            best_n = n;
            best_d = d;
        }
    }

    for (uint j = 0; j < num_spheres; j++) {
        float4 sp = spheres[j];
        float3 center = sp.xyz;
        float radius = sp.w;
        float3 to_pos = pos - center;
        float dist = length(to_pos);
        float sdf = dist - radius;

        if (sdf < min_sdf) {
            min_sdf = sdf;
            float3 n = (dist > 1e-8) ? (to_pos / dist) : float3(0.0, 1.0, 0.0);
            float3 surf_pt = center + n * radius;
            best_n = n;
            best_d = dot(n, surf_pt);
        }
    }

    float threshold = contact_margin + collision_distance;
    if (min_sdf < threshold) {
        contact_planes[tid] = float4(best_n, best_d + collision_distance);
    } else {
        contact_planes[tid] = float4(0.0);
    }
}

[shader("compute")]
[numthreads(64, 1, 1)]
void project_constraints(uint tid : SV_DispatchThreadID,
                         StructuredBuffer<float3> positions_in,
                         StructuredBuffer<float3> old_positions,
                         RWStructuredBuffer<float3> positions_out,
                         StructuredBuffer<float> inv_masses,
                         StructuredBuffer<uint> row_ptr,
                         StructuredBuffer<uint> neighbors,
                         StructuredBuffer<float> neighbor_rest,
                         // Contact plane: dot(n, x) = d, with unit normal n
                         StructuredBuffer<float4> contact_planes,
                         uniform uint num_particles,
                         uniform float static_friction,
                         uniform float kinetic_friction) {
    if (tid >= num_particles) {
        return;
    }
    // TODO: HW 4.5. Your code below.

    float3 pos = positions_in[tid];
    float wi = inv_masses[tid];

    if (wi == 0.0) {
        positions_out[tid] = pos;
        return;
    }

    uint start = row_ptr[tid];
    uint end = row_ptr[tid + 1];
    float3 correction = float3(0.0);
    uint num_corrections = 0;

    for (uint k = start; k < end; k++) {
        uint neighbor_idx = neighbors[k];
        float rest_len = neighbor_rest[k];
        float3 neighbor_pos = positions_in[neighbor_idx];
        float wj = inv_masses[neighbor_idx];

        correction += get_correction(pos, neighbor_pos, wi, wj, rest_len);
        num_corrections += 1;
    }

    if (num_corrections > 0) {
        correction /= float(num_corrections);
    }

    float3 x = pos + correction;

    float4 cp = contact_planes[tid];
    float3 n = cp.xyz;
    float n_len = length(n);
    if (n_len > 1e-8) {
        n /= n_len;
        float d = cp.w;
        float sd = dot(n, x) - d;
        if (sd < 0.0) {
            float penetration = -sd;
            x += n * penetration;

            // Resting contact has tiny leftover penetration; floor so grip still works.
            float mu_n = max(penetration, 0.04);
            float3 old_pos = old_positions[tid];
            float3 disp = x - old_pos;
            float3 tangent = disp - dot(disp, n) * n;
            float tangent_len = length(tangent);

            if (tangent_len > 1e-8) {
                if (tangent_len <= static_friction * mu_n) {
                    x -= tangent;
                } else {
                    float pull = min(tangent_len, kinetic_friction * mu_n);
                    x -= (tangent / tangent_len) * pull;
                }
            }
        }
    }

    positions_out[tid] = x;
}

[shader("compute")]
[numthreads(64, 1, 1)]
void update_velocity(uint tid : SV_DispatchThreadID,
                     RWStructuredBuffer<float3> positions,
                     StructuredBuffer<float3> old_positions,
                     RWStructuredBuffer<float3> velocities,
                     StructuredBuffer<float> inv_masses,
                     uniform uint num_particles,
                     uniform float dt) {
    if (tid >= num_particles) {
        return;
    }
    // TODO: HW 4.5. Your code below.

    float3 pos = positions[tid];
    float3 old_pos = old_positions[tid];

    if (inv_masses[tid] != 0.0) {
        positions[tid] = pos;
        velocities[tid] = (pos - old_pos) / dt;
    } else {
        positions[tid] = pos;
        velocities[tid] = float3(0.0);
    }
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
