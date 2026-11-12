[shader("compute")]
[numthreads(64, 1, 1)]
void compute_main(uint tid : SV_DispatchThreadID,
                  RWStructuredBuffer<float3> positions,
                  RWStructuredBuffer<float3> velocities,
                  uniform uint num_particles,
                  // time step size
                  uniform float dt) {
    if (tid >= num_particles) {
        return; // each thread handles different particle (float3vec)
    }
    // TODO: HW 4.1. Your code below.
    // gravity:  (0, −9.8, 0)
    // simple euler uses v_n in the x_n+1 equation, which is why we compute v_n+1 first
    // simulate floor or ground level at horizontal plan y = -1, or -0.97


    // v_n+1 = v_n + g(t_n, x_n) dt
    // x_n+1 = x_n + f(t_n, v_n+1) dt
    // t_n = t_0 + n dt after n steps


    float3 gravity = float3(0, -9.8, 0);
    float3 pos0 = positions[tid];
    float3 v0 = velocities[tid];

    float3 v1 = v0 + gravity * dt;
    float3 pos1 = pos0 + v1 * dt;

    // check if we went through floor
    // if so correct pos and then reverse dir velocity

    if (pos1.y <= -0.97) {
        pos1.y = -0.97;
        v1.y = -v1.y;
    } 
    positions[tid] = pos1;
    velocities[tid] = v1;

    return;
}
