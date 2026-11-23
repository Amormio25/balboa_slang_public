[shader("compute")]
[numthreads(64, 1, 1)]
void project_constraints(uint tid : SV_DispatchThreadID,
                         StructuredBuffer<float3> positions_in,
                         RWStructuredBuffer<float3> positions_out,
                         StructuredBuffer<float> inv_masses,
                         // The CSR matrix data structure
                         StructuredBuffer<uint> row_ptr,
                         StructuredBuffer<uint> neighbors,
                         // Rest lengthes of the neighbor edges
                         StructuredBuffer<float> neighbor_rest,
                         uniform uint num_particles) {
    if (tid >= num_particles) {
        return;
    }
    // TODO: HW 4.4. Your code below.

    float3 pos = positions_in[tid];
    float wi = inv_masses[tid];

    //pinned particles do not move
    if(wi == 0.0){
        positions_out[tid] = pos;
        return;
    }

    uint start = row_ptr[tid];
    uint end = row_ptr[tid + 1];

    float3 correction = float3(0.0);
    uint num_corrections = 0;

    for(uint k = start; k < end; k++){
        uint neighbor_idx = neighbors[k];
        float rest_len = neighbor_rest[k];
        float3 neighbor_pos = positions_in[neighbor_idx];
        float wj = inv_masses[neighbor_idx];

        correction += get_correction(pos, neighbor_pos, wi, wj, rest_len);
        num_corrections += 1;
    }

    if(num_corrections > 0){
        correction /= float(num_corrections);
    }

    positions_out[tid] = pos + correction;
}

//same as on 4_3

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
