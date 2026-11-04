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
                  uniform int max_depth,
                  RWTexture2D<float4> image) {
    uint width, height;
    image.GetDimensions(width, height);
    if (tid.x >= width || tid.y >= height) {
        return;
    }

    // should be about the same thing as 3.2, but need to account for mirror reflection. 3.1 handled normal rendering, 3.2 accounted for lights and shadows, this one in addition to lights and shadows, at the hit point on sphere we need to check if this shape has a Kr > 0, and if so reflect by tracing ray in the mirror reflection direction. that ray should go tmax and if no hits, stay bg color.

    // so because that reflection ray can keep hitting other spheres, conceptually that means we'd need to find out the color and light contributions etc on that sphere, so its like we wrap everything inside the iterative loop

    // could keep on reflecting so our iterative loop goes maxDepth times




    float aspect_ratio = float(width) / float(height);
    float2 px_center = float2(tid.x + 0.5, height - tid.y - 0.5);

    float normalized_x = px_center.x / width;
    float normalized_y = px_center.y / height;

    float image_x = normalized_x * 2 * aspect_ratio - aspect_ratio;
    float image_y = normalized_y * 2 - 1;

    float3 p = float3(image_x, image_y, -1); // point on image plane
    float3 camera_to_point_ray = p;

    float t_min = EPSILON; // prevent self intersection

    float3 color = 0.0;
    float3 throughput = 1.0;
    float3 total_light = 0.0;
    // ray origin will change as we reflect, this how we can update/keep track
    float3 ray_origin = 0.0;
    
    
    for (int bounce = 0; bounce < max_depth; bounce++) {
        // each iteration we'll hit some sphere, then reflect and possibly hit another sphere requiring ray_origin to be updated, and so closest_t and the sphere hit will also need to be updated each iteration
        float closest_t = 1e30;
        int hit_i = -1;

        for (int i = 0; i < num_shapes; i++) {
            Sphere sphere = spheres[shapes[i].index];
            float3 center = sphere.center;
            float radius = sphere.radius;

            float a = dot(camera_to_point_ray, camera_to_point_ray);
            float b = -2.0 * (
                dot(camera_to_point_ray, center) - 
                dot(ray_origin, camera_to_point_ray));
            float c = -2.0 * dot(ray_origin, center) + 
                            dot(ray_origin, ray_origin) + 
                            dot(center, center) - pow(radius, 2);

            float2 roots;
            if (!solve_quadratic(a, b, c, roots)) {
                continue;
            }

            float t_hit = 1e30;
            if (roots.x > t_min && roots.x < t_hit) t_hit = roots.x;
            if (roots.y > t_min && roots.y < t_hit) t_hit = roots.y;
            if (t_hit < closest_t) {
                closest_t = t_hit;
                hit_i = i; 
            }
        }

        // no hit, so we just get color of bg
        if (hit_i == -1) {
            color += throughput * background;
            break;
        }
        // if we made a hit on a shape, we currently have the closest one hit recorded, so we need to check all the lights and check all the shapes if they obstruct the lights possibly going to this pixel
        if (hit_i != -1) {
            total_light = 0.0;
            Sphere hit_sphere = spheres[shapes[hit_i].index];
            float3 hit_point = ray_origin + closest_t * camera_to_point_ray;

            // we need to sum the contribution of all point lights on this pixel
            for (int j = 0; j < num_lights; j++) {
                // just to make it more clear, 0+td is 0+t times distance from origin to point which is just point
            
                // possible we came from some other ray-sphere intersection and not just the camera anymore, so o is previous ray origin
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

                    if (shadow_roots.x > t_min && shadow_roots.x < t_max)  {
                        obstacle_hit = true;
                    }
                    if (shadow_roots.y > t_min && shadow_roots.y < t_max)  {
                        obstacle_hit = true;
                    }
                }

                if (!obstacle_hit) {
                    float3 n = normalize(hit_point - hit_sphere.center);
                    float3 l = normalize(intersection_to_light);

                    total_light += shapes[hit_i].Kd * lights[j].intensity * 1 / pow(t_max, 2) * max(0.0, dot(n, l));

                    // mirror reflections
                    // color += throughput * total_light;
                    // throughput *= shapes[hit_i].Kr;
                    // ray = reflect(ray);
                }
            }
            color += throughput * total_light;
            throughput *= shapes[hit_i].Kr;

            float3 n = normalize(hit_point - hit_sphere.center);
            float3 reflected_dir = reflect(normalize(camera_to_point_ray), n);
            ray_origin = hit_point + EPSILON * reflected_dir;
            camera_to_point_ray = reflected_dir;
        }
    }
    image[tid] = float4(color, 1.0);
}