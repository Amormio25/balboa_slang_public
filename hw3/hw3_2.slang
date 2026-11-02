import hw3_common;

[shader("compute")]
[numthreads(8, 8, 1)]
void compute_main(uint2 tid : SV_DispatchThreadID,
                  uniform float3 background,
                  StructuredBuffer<Shape> shapes,
                  uniform int num_shapes,
                  StructuredBuffer<Sphere> spheres,
                  StructuredBuffer<PointLight> lights,
                  uniform int num_lights,
                  RWTexture2D<float4> image) {
    uint width, height;
    image.GetDimensions(width, height);
    if (tid.x >= width || tid.y >= height) {
        return;
    }

    image[tid] = float4(background, 1.0);

// {
//     "background": [0.5, 0.5, 0.5],
//     "objects": [
//         {
//             "type": "sphere",
//             "center": [0.0, 0.0, -3.0],
//             "radius": 1.0,
//             "Kd": [0.9, 0.2, 0.2],
//             "Kr": [0.0, 0.0, 0.0]
//         }
//     ],
//     "lights": [
//         {
                // this is an xyz coordinate not just a 3 float vector
//             "position": [-3.0, 4.0, 1.0], 
//             "intensity": [120.0, 120.0, 120.0]
//         }
//     ]
// }

    // cast a ray from the point to the direction of the light (shadow ray)
    //  set upper bound tmax for how far it can travel
    //  skip intersections with t < t_min (self intersections)
    //  shadow test is just seeing if anything is in between our point and the point light



    // reuse 3.1 to find the closest sphere and hit point.

    // Instead of coloring using the surface normal, calculate lighting.

    // for each point light, cast a shadow ray from the hit point toward the light

    // if another object intersects that shadow ray before it reaches the light, that light doesn't light up the hit point



    float aspect_ratio = float(width) / float(height);
    float2 px_center = float2(tid.x + 0.5, height - tid.y - 0.5);

    float normalized_x = px_center.x / width;
    float normalized_y = px_center.y / height;

    float image_x = normalized_x * 2 * aspect_ratio - aspect_ratio;
    float image_y = normalized_y * 2 - 1;

    float3 p = float3(image_x, image_y, -1); // point on image plane

    float closest_t = 1e30;
    int hit_i = -1;

    float t_min = EPSILON; // prevent self intersection

    for (int i = 0; i < num_shapes; i++) {
        Sphere sphere = spheres[shapes[i].index];
        float3 center = sphere.center;
        float radius = sphere.radius;

        float3 camera_to_point_ray = p;
        float a = dot(camera_to_point_ray, camera_to_point_ray);
        float b = -2.0 * dot(camera_to_point_ray, center);
        float c = dot(center, center) - pow(radius, 2);

        float2 roots;
        if (!solve_quadratic(a, b, c, roots)) {
            continue;
        }

        float t_hit = 1e30;
        if (roots.x > EPSILON && roots.x < t_hit) t_hit = roots.x;
        if (roots.y > EPSILON && roots.y < t_hit) t_hit = roots.y;
        if (t_hit < closest_t) {
            closest_t = t_hit;
            hit_i = i; 
        }
    }

    // if we made a hit on a shape, we currently have the closest one hit recorded, so we need to check all the lights and check all the shapes if they obstruct the lights possibly going to this pixel
    float3 total_light = float3(0,0,0);
    if (hit_i != -1) {
        
        // we need to sum the contribution of all point lights on this pixel

        for (int j = 0; j < num_lights; j++) {
            // just to make it more clear, 0+td is 0+t times distance from origin to point which is just point
            Sphere hit_sphere = spheres[shapes[hit_i].index];
         
            float3 camera_to_point_ray = p;


            float3 hit_point = float3(0,0,0) + closest_t * camera_to_point_ray;
            float3 intersection_to_light = lights[j].position - hit_point;
            float3 shadow_dir = normalize(intersection_to_light);

            // t max should not exceed past this vector
            float t_max = length(intersection_to_light);

            bool obstacle_hit = false;
            for (int k = 0; k < num_shapes; k++) {
                Sphere maybe_sphere_obstacle = spheres[shapes[k].index];
                float3 center = maybe_sphere_obstacle.center;
                float radius = maybe_sphere_obstacle.radius;

                // check if the shadow ray hits anything
                // origin is not 0 anymore so we have a new equation for a b c
                float a = dot(shadow_dir, shadow_dir);
                float b = -2.0 * (
                    dot(shadow_dir, center) - 
                    dot(hit_point, shadow_dir));
                float c = -2.0 * dot(hit_point, center) + 
                                dot(hit_point, hit_point) + 
                                dot(center, center) - pow(radius, 2);

                float2 shadow_roots;
                if (!solve_quadratic(a, b, c, shadow_roots)) {
                    continue;
                }

                if (shadow_roots.x > EPSILON && shadow_roots.x < t_max)  {
                    obstacle_hit = true;
                }
                if (shadow_roots.y > EPSILON && shadow_roots.y < t_max)  {
                    obstacle_hit = true;
                }
            }
             if (!obstacle_hit) {
                float3 n = normalize(hit_point - hit_sphere.center);
                float3 l = normalize(intersection_to_light);

                total_light += shapes[hit_i].Kd * lights[j].intensity * 1 / pow(t_max, 2) * max(0.0, dot(n, l));
            }
        }
        image[tid] = float4(total_light, 1.0);
    }
}

// finish correction then 2 more to do