[shader("compute")]
[numthreads(64, 1, 1)]
void project_constraints(uint tid : SV_DispatchThreadID,
                         StructuredBuffer<float3> positions_in,
                         RWStructuredBuffer<float3> positions_out,
                         StructuredBuffer<float> inv_masses,
                         uniform int2 grid_size,
                         uniform float2 spacing) {
    if (tid >= grid_size.x * grid_size.y) {
        return;
    }
    // TODO: HW 4.3. Your code below.
    // main change is just that instead of a 1d connected rope like object we have a sheet
    // corners this time don't move?

    // current tid maps to one vertex
    // for this vertex
    //      if it's not infinite inverse mass (not moving)
    //      look through every valid neighbor for which we might do the updates
    //      if it has a valid structural link that means it's got possibly 4 neighbors up down left right
    //      if it has a valid shear link think the diagonal of the cell both ways
    //      if it has a valid bending link think like all directions if applicable but two places away (not diagonal) for lessening the crease
    // we'll just do the similar updates we've been doing as in 4.2

    int x = tid % grid_size.x; // this is column index btw
    int y = tid / grid_size.x; // this is row index
    
    float3 pos = positions_in[tid];
    float wi = inv_masses[tid];

    if (wi == 0.0) {
        positions_out[tid] = pos;
        return;
    }

    float3 correction = 0;
    int num_corrections = 0;

    static const int directions[12][2] = {
        {1,0}, {-1,0}, {0,1}, {0,-1},  // structural
        {1,1}, {-1,1}, {1,-1}, {-1,-1},  // shear
        {2,0}, {-2,0}, {0,2}, {0,-2},  // bending
    };
    
    for (int link = 0; link < 12; link++) {
        int directions_x = directions[link][0];
        int directions_y = directions[link][1];

        // out of bounds check
        int other_x = x + directions_x;
        int other_y = y + directions_y;
        if (other_x < 0 || other_x >= grid_size.x ||
            other_y < 0 || other_y >= grid_size.y) {
            continue;
        }

        // skip other y full rows, then move other_x cols along this row
        int other_tid = other_y * grid_size.x + other_x;
        float rest_length = length(float2(directions_x * spacing.x, 
                                            directions_y * spacing.y));
        correction += get_correction(pos, positions_in[other_tid], 
                                    wi, inv_masses[other_tid], rest_length);
        num_corrections += 1;
    }

    if (num_corrections > 0) {
        correction /= num_corrections;
    }
    positions_out[tid] = pos + correction;

    return;
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
