import hw1_common;

[shader("compute")]
[numthreads(8, 8, 1)]
void compute_main(uint2 tid : SV_DispatchThreadID,
                  uniform float3 background,
                  uniform int samples_per_axis,
                  StructuredBuffer<Shape> shapes,
                  uniform int num_shapes,
                  StructuredBuffer<Circle> circles,
                  StructuredBuffer<Polyline> polylines,
                  StructuredBuffer<QuadraticBezier> quadratic_beziers,
                  StructuredBuffer<float2> points,
                  RWTexture2D<float4> image) {
    
    // LLM usage:
    // Model: ChatGPT, GPT-6
    // This was easily the most time-consuming and difficult task and where I got help from AI the most. I understood that we basically now had to apply similar logic accounting for bezier curves, but I struggled a lot with the math and deriving the coefficients from the equations given from the slides. It helped me figure out that to get a,b,c that I had to actually transform the equation to get into quadratic form to put into solve_quadratic. I also tried solving the derivative by hand and lowkey struggled from lack of practice and asked ChatGPT if I was going in the right direction step by step, correcting me if I got stuck.
    // Finally, getting the coefficients for solve_cubic took a while and required back and forth help from AI to solve (q(t) − p) · q0(t) = 0

    uint width, height;
    image.GetDimensions(width, height);
    if (tid.x >= width || tid.y >= height) {
        return;
    }

    image[tid] = float4(1.0);
    // TODO: your code here
}
