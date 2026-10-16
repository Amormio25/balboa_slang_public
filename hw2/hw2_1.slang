[shader("compute")]
[numthreads(8, 8, 1)]
void compute_main(uint2 tid : SV_DispatchThreadID,
                  uniform float2 sp0,
                  uniform float2 sp1,
                  uniform float2 sp2,
                  uniform int2 aabb_min,
                  uniform float3 color,
                  RWTexture2D<float4> image) {
    int2 ipixel = int2(tid) + int2(aabb_min);
    uint width, height;
    image.GetDimensions(width, height);
    if (ipixel.x < 0 || ipixel.y < 0 || ipixel.x >= width || ipixel.y >= height) {
        return;
    }

    // TODO: HW 2.1

    image[ipixel] = float4(float3(0.0), 1.0);

    // note: read the writeup carefully for this since it explains a lot but a simple explanation why we divide by -z is this: remember we have line from origin to our point in 3d space, and the intersection with image plane is the projected point. To get there we basically just go in the -z direction less.
}
