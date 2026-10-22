[shader("compute")]
[numthreads(8, 8, 1)]
void compute_main(uint2 tid : SV_DispatchThreadID,
                  uniform float2 sp0,
                  uniform float2 sp1,
                  uniform float2 sp2,
                  uniform float inv_depth0,
                  uniform float inv_depth1,
                  uniform float inv_depth2,
                  uniform int2 aabb_min,
                  uniform float3 c0,
                  uniform float3 c1,
                  uniform float3 c2,
                  uniform float s,
                  uniform float a,
                  RWTexture2D<float4> color_image,
                  RWTexture2D<float> depth_image) {
    int2 ipixel = int2(tid) + int2(aabb_min);
    uint width, height;
    color_image.GetDimensions(width, height);
    if (ipixel.x < 0 || ipixel.y < 0 || ipixel.x >= width || ipixel.y >= height) {
        return;
    }

    // Pixel center in screen space (same as 2.1)
    float2 p = float2(ipixel.x + 0.5, ipixel.y + 0.5);

    // Inside triangle?
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
    if (!all_positive &&  !all_negative) {
        return;
    }

    float area_012 = tri_area(sp0, sp1, sp2);
    float b0_prime = tri_area(p, sp1, sp2) / area_012;
    float b1_prime = tri_area(sp0, p, sp2) / area_012;
    float b2_prime = tri_area(sp0, sp1, p) / area_012;

    float B = 1 / ((b0_prime / (-inv_depth0)) +
                    (b1_prime / (-inv_depth1)) +
                    (b2_prime / (-inv_depth2)));

    float b0 = b0_prime * B / (-inv_depth0);
    float b1 = b1_prime * B / (-inv_depth1);
    float b2 = b2_prime * B / (-inv_depth2);

  
    float z0 = -1.0 / inv_depth0;
    float z1 = -1.0 / inv_depth1;
    float z2 = -1.0 / inv_depth2;
    float pz = b0 * z0 + 
                b1 * z1 + 
                b2 * z2;

    // smaller positive depth means closer to the camera
    float depth = -pz;

    float closest = depth_image[ipixel];
    if (depth < closest) {
        //   depth_image stores the closest depth rendered at each pixel so far
        // if the new triangle's depth is smaller, it is closer, so update the depth buffer.
        // if its depth is greater, another object is already in front, so skip it.
        depth_image[ipixel] = depth;

        // barycentric weights blend the three vertices colors
        float3 color = b0 * c0 + b1 * c1 + b2 * c2;
        color_image[ipixel] = float4(color, 1.0);
    }
}

float tri_area(float2 a, float2 b, float2 c) {
    float2 u = b - a;
    float2 v = c - a;
    return u.x * v.y - u.y * v.x;
}
