[shader("compute")]
[numthreads(8, 8, 1)]
void compute_main(uint2 tid : SV_DispatchThreadID,
                  uniform float2 sp0,
                  uniform float2 sp1,
                  uniform float2 sp2,
                  uniform int2 aabb_min,
                  uniform float3 color,
                  RWTexture2D<float4> image) {
    // the screen space pixel coord
    int2 ipixel = int2(tid) + int2(aabb_min);
    uint width, height;
    image.GetDimensions(width, height);
    if (ipixel.x < 0 || ipixel.y < 0 || ipixel.x >= width || ipixel.y >= height) {
        return;
    }

    // TODO: HW 2.1

    // image[ipixel] = float4(float3(0.0), 1.0);

    // note: read the writeup carefully for this since it explains a lot but a simple explanation why we divide by -z is this: remember we have line from origin to our point in 3d space, and the intersection with image plane is the projected point. To get there we basically just go in the -z direction less.
    float2 p = float2(ipixel.x + 0.5, ipixel.y + 0.5);

    float2 edge0 = sp1 - sp0;
    float2 edge1 = sp2 - sp1;
    float2 edge2 = sp0 - sp2;

    float2 normal0 = float2(edge0.y, -edge0.x);
    float2 normal1 = float2(edge1.y, -edge1.x);
    float2 normal2 = float2(edge2.y, -edge2.x);

    float result0 = dot((p - sp0), normal0);
    float result1 = dot((p - sp1), normal1);
    float result2 = dot((p - sp2), normal2);

    bool all_positive = result0 >= 0 && result1 >= 0 && result2 >= 0;
    bool all_negative = result0 <= 0 && result1 <= 0 && result2 <= 0;
    if (all_positive || all_negative) {
        image[ipixel] = float4(color, 1.0);
    }

}
