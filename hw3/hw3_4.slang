import hw3_common;

[shader("compute")]
[numthreads(8, 8, 1)]
void compute_main(uint2 tid : SV_DispatchThreadID,
                  uniform float3 background,
                  uniform Camera camera,
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
    // 1. Generate camera ray using dynamic FOV and camera-to-world transformation
    float aspect_ratio = float(width) / float(height);
    float fov_radians = radians(camera.fov_x);
    float plane_width = 2.0 * tan(fov_radians * 0.5);
    float plane_height = plane_width / aspect_ratio;

    float2 uv = (float2(tid) + 0.5) / float2(width, height);
    float3 ray_dir_cam = normalize(float3(
        (uv.x - 0.5) * plane_width,
        (0.5 - uv.y) * plane_height,
        -1.0
    ));

    float3 ray_origin_world = mul(camera.cam_to_world, float4(0.0, 0.0, 0.0, 1.0)).xyz;
    float3 ray_dir_world = mul(camera.cam_to_world, float4(ray_dir_cam, 0.0)).xyz;

    float t_min = EPSILON;
    float3 color = 0.0;
    float3 throughput = 1.0;
    
    // Track current ray for multi-bounce reflections
    float3 current_ray_origin = ray_origin_world;
    float3 current_ray_dir = ray_dir_world;

    for (int bounce = 0; bounce < max_depth; bounce++) {
        float closest_t = 1e30;
        int hit_i = -1;

        // 2. Find closest intersection in object space for all shapes
        for (int i = 0; i < num_shapes; i++) {
            Shape shape = shapes[i];
            
            // Transform current ray into object space (do not normalize direction)
            float3 o_obj = mul(shape.world_to_obj, float4(current_ray_origin, 1.0)).xyz;
            float3 d_obj = mul(shape.world_to_obj, float4(current_ray_dir, 0.0)).xyz;

            if (shape.type == 0) {
                Sphere sphere = spheres[shape.index];
                float3 center = sphere.center;
                float radius = sphere.radius;

                float a = dot(d_obj, d_obj);
                float b = 2.0 * dot(d_obj, o_obj - center);
                float c = dot(o_obj - center, o_obj - center) - pow(radius, 2);

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
        }

        // If no hit, accumulate background color and break
        if (hit_i == -1) {
            color += throughput * background;
            break;
        }

        // 3. Process hit point, lighting, shadows, and reflections
        Shape hit_shape = shapes[hit_i];
        Sphere hit_sphere = spheres[hit_shape.index];

        // Recompute local ray for the winning shape to get exact hit details
        float3 o_obj = mul(hit_shape.world_to_obj, float4(current_ray_origin, 1.0)).xyz;
        float3 d_obj = mul(hit_shape.world_to_obj, float4(current_ray_dir, 0.0)).xyz;
        float3 p_obj = o_obj + closest_t * d_obj;

        // Map hit point and normal back to world space
        float3 hit_point_world = mul(hit_shape.obj_to_world, float4(p_obj, 1.0)).xyz;
        float3 n_obj = normalize(p_obj - hit_sphere.center);
        float3 hit_normal = normalize(mul(transpose(hit_shape.world_to_obj), float4(n_obj, 0.0)).xyz);

        float3 total_light = 0.0;
        for (int j = 0; j < num_lights; j++) {
            float3 intersection_to_light = lights[j].position - hit_point_world;
            float3 shadow_dir_world = normalize(intersection_to_light);
            float t_max = length(intersection_to_light);

            bool obstacle_hit = false;
            for (int k = 0; k < num_shapes; k++) {
                Shape obstacle_shape = shapes[k];
                Sphere obstacle_sphere = spheres[obstacle_shape.index];

                float3 s_o_obj = mul(obstacle_shape.world_to_obj, float4(hit_point_world, 1.0)).xyz;
                float3 s_d_obj = mul(obstacle_shape.world_to_obj, float4(shadow_dir_world, 0.0)).xyz;

                float a = dot(s_d_obj, s_d_obj);
                float b = 2.0 * dot(s_d_obj, s_o_obj - obstacle_sphere.center);
                float c = dot(s_o_obj - obstacle_sphere.center, s_o_obj - obstacle_sphere.center) - pow(obstacle_sphere.radius, 2);

                float2 shadow_roots;
                if (!solve_quadratic(a, b, c, shadow_roots)) {
                    continue;
                }

                if (shadow_roots.x > t_min && shadow_roots.x < t_max) {
                    obstacle_hit = true;
                }
                if (shadow_roots.y > t_min && shadow_roots.y < t_max) {
                    obstacle_hit = true;
                }
            }

            if (!obstacle_hit) {
                float3 l = normalize(intersection_to_light);
                total_light += hit_shape.Kd * lights[j].intensity * (1.0 / pow(t_max, 2)) * max(0.0, dot(hit_normal, l));
            }
        }

        color += throughput * total_light;
        throughput *= hit_shape.Kr;

        // Setup next reflection ray
        float3 reflected_dir = reflect(current_ray_dir, hit_normal);
        current_ray_origin = hit_point_world + t_min * reflected_dir;
        current_ray_dir = reflected_dir;
    }

    image[tid] = float4(color, 1.0);
}