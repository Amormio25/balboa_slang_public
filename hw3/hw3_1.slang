import hw3_common;

[shader("compute")]
[numthreads(8, 8, 1)]
void compute_main(uint2 tid : SV_DispatchThreadID,
                  uniform float3 background,
                  StructuredBuffer<Sphere> spheres,
                  uniform int num_spheres,
                  RWTexture2D<float4> image) {
    uint width, height;
    image.GetDimensions(width, height);
    if (tid.x >= width || tid.y >= height) {
        return;
    }

    image[tid] = float4(background, 1.0);    

    // ray tracing starts with pixels and asks: what does this pixel see in the scene? so not 3d to screen space, we have pixel and figure which 3d dir camera passes through it
    // so find px center and convert to image plane coords
    // make a ray
    // loop through each sphere to find intersections
    // find the closest visible intersection, if multiple spheres are intersected, choose the closest positive t
    // render


    // raycast to pixel on image plane for pixel center
    float aspect_ratio = float(width) / float(height);
    float2 px_center = float2(tid.x + 0.5, height - tid.y - 0.5);

    // 0 to 1
    float normalized_x = px_center.x / width;
    float normalized_y = px_center.y / height;

    // -a to a and -1 to 1
    float image_x = normalized_x * 2 * aspect_ratio - aspect_ratio;
    float image_y = normalized_y * 2 - 1;

    float3 p = float3(image_x, image_y, -1); // d is distance from origin to this point which is just the same since origin is 0,0,0

    float closest_t = 1e30;
    int hit_i = -1;

    for (int i = 0; i < num_spheres; i++) {
        float3 center = spheres[i].center;
        float radius = spheres[i].radius;
        // o+td is just td. euc norm is same as the expression dot prod itself, so td-xc dot td-xc to get our a b and c
        float a = dot(p, p);
        float b = -2.0 * dot(p, center);
        float c = dot(center, center) - pow(radius, 2);

        // need to solve quadratic equation for ray-sphere intersection
        // ray (o+td) sphere center x_c and radius r
        // euc norm of ray - sphere center = r^2
        // turn into at^2+bt+c = 0 form
        float2 roots;
        if (!solve_quadratic(a, b, c, roots)) {
            continue;
        }

        // ray can hit sphere 0,1, or 2 times. make sure t > 0 (intersection not behind) for when it's 2, and choose the closer one

        // So here we're basically getting roots for possible intersections with the sphere, to see which has lower t (lower t means the intersection closer to the ray) and if it's the closest weve seen we ll just make note of which sphere it came from so we know to color based on that sphere
        float t_hit = 1e30;
        if (roots.x > EPSILON && roots.x < t_hit) t_hit = roots.x;
        if (roots.y > EPSILON && roots.y < t_hit) t_hit = roots.y;
        if (t_hit < closest_t) {
            closest_t = t_hit;
            hit_i = i; // find which sphere we hit that was closest in front
        }
    }

    if (hit_i >= 0) {
        // 3d intersection point along the ray
        float3 hit = closest_t * p;

        // get the surface normal at that point
        float3 n = normalize(hit - spheres[hit_i].center);

        // convert to 0,1 range so we can use rgb
        float3 color = (n + 1.0) * 0.5;  // (n + 1) / 2
        image[tid] = float4(color, 1.0);
    }

    // Once we found the closest hit among many spheres, visualize the color using the sphere’s normal
}
