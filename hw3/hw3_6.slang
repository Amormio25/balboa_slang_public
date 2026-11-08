import hw3_common;

[shader("compute")]
[numthreads(8, 8, 1)]
void compute_main(uint2 tid : SV_DispatchThreadID,
                  uniform float3 background,
                  uniform Camera camera,
                  StructuredBuffer<Shape> shapes,
                  uniform int num_shapes,
                  StructuredBuffer<Sphere> spheres,
                  StructuredBuffer<TriangleMesh> meshes,
                  StructuredBuffer<float3> vertices,
                  StructuredBuffer<float3> vertex_normals,
                  StructuredBuffer<uint3> triangles,
                  StructuredBuffer<BVHNode> bvh_nodes,
                  StructuredBuffer<PointLight> lights,
                  uniform int num_lights,
                  uniform int max_depth,
                  RWTexture2D<float4> image) {
    uint width, height;
    image.GetDimensions(width, height);
    if (tid.x >= width || tid.y >= height) {
        return;
    }
    // LLM Usage:
    // Model: ChatGPT, GPT-6
    // I used ChatGPT because this problem on the writeup was a little bit hard to understand in the wording, but after some brainstorming and looking back on my notes it didn't seem too much changes from 3.5. I mainly asked it to confirm if my understanding regarding the bounding boxes was correct given the notes and lectures.

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
    
    // get ray origin and first ray in world space
    float3 ray_origin = xform_pt(camera.cam_to_world, float3(0.0, 0.0, 0.0));
    camera_to_point_ray = xform_vec(camera.cam_to_world, p);
    
    // main change is that intersections happen in object space but things like normals and hit point for lighting are part of the scene so that's world space
    
    for (int bounce = 0; bounce < max_depth; bounce++) {
        float closest_t = 1e30;
        int hit_i = -1;
        float3 hit_b = 0.0; // to store if closest was triangle
        uint3 hit_tri = 0;

        for (int i = 0; i < num_shapes; i++) {
            // get the object space origin and ray
            float3 org_o = xform_pt(shapes[i].world_to_obj, ray_origin);
            float3 dir_o = xform_vec(shapes[i].world_to_obj, camera_to_point_ray);

            if (shapes[i].type == ShapeType.Sphere) {
                Sphere sphere = spheres[shapes[i].index];
                float3 center = sphere.center;
                float radius = sphere.radius;

                float a = dot(dir_o, dir_o);
                float b = -2.0 * (
                    dot(dir_o, center) - 
                    dot(org_o, dir_o));
                float c = -2.0 * dot(org_o, center) + 
                                dot(org_o, org_o) + 
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
            } else {
                TriangleMesh mesh = meshes[shapes[i].index];
                int cur = mesh.bvh_root_index;
                int bvh_end = bvh_nodes[mesh.bvh_root_index].next_index;
                // cur up to next index descendants of node i
                while (cur < bvh_end) {
                    BVHNode node = bvh_nodes[cur];
                    // miss the box so check next bounding box
                    if (!intersect_aabb(node.bbox_min, node.bbox_max,
                                        org_o, dir_o, t_min, closest_t)) {
                        cur = node.next_index;
                    } else {
                        // only if we actually hit a leaf node do we then check if we intersected with any of the triangles in the node
                        if (node.is_leaf) {
                            for (int j = node.triangle_begin; j < node.triangle_end; j++) {
                                uint3 tri = triangles[j] + mesh.vertex_offset;
                                float3 v0 = vertices[tri.x];
                                float3 v1 = vertices[tri.y];
                                float3 v2 = vertices[tri.z];

                                // the helper uses something like pointers for updating
                                float3 b;
                                float t_hit;
                                bool triangle_hit = intersect_tri(v0, v1, v2, org_o, dir_o, t_min, closest_t, b, t_hit);

                                if (triangle_hit && t_hit < closest_t) {
                                    hit_i = i;
                                    closest_t = t_hit;
                                    hit_b = b;
                                    hit_tri = tri;
                                }
                            }
                        }
                        cur = cur + 1;
                    }
                }

            }
        }

        if (hit_i == -1) {
            color += throughput * background;
            break;
        }

        if (hit_i != -1) {
            total_light = 0.0;
            float3 hit_point = ray_origin + closest_t * camera_to_point_ray;
            float3 n;

            if (shapes[hit_i].type == ShapeType.Sphere) {
                Sphere hit_sphere = spheres[shapes[hit_i].index];
                float3 org_o = xform_pt(shapes[hit_i].world_to_obj, ray_origin);
                float3 dir_o = xform_vec(shapes[hit_i].world_to_obj, camera_to_point_ray);

                // intersection hit point in object space
                float3 hit_o = org_o + closest_t * dir_o;
                n = normalize(xform_vec(shapes[hit_i].obj_to_world,
                                        normalize(hit_o - hit_sphere.center)));

                for (int j = 0; j < num_lights; j++) {
                    float3 intersection_to_light = lights[j].position - hit_point;
                    float3 shadow_dir = normalize(intersection_to_light);
                    float t_max = length(intersection_to_light);

                    bool obstacle_hit = false;
                    for (int k = 0; k < num_shapes; k++) {
                        float3 shadow_org_o = xform_pt(shapes[k].world_to_obj, hit_point);
                        float3 shadow_dir_o = xform_vec(shapes[k].world_to_obj, intersection_to_light);

                        if (shapes[k].type == ShapeType.Sphere) {
                            Sphere maybe_sphere_obstacle = spheres[shapes[k].index];
                            float3 center = maybe_sphere_obstacle.center;
                            float radius = maybe_sphere_obstacle.radius;

                            float a = dot(shadow_dir_o, shadow_dir_o);
                            float b = -2.0 * (
                                dot(shadow_dir_o, center) - 
                                dot(shadow_org_o, shadow_dir_o));
                            float c = -2.0 * dot(shadow_org_o, center) + 
                                            dot(shadow_org_o, shadow_org_o) + 
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
                        } else {
                            TriangleMesh mesh = meshes[shapes[k].index];
                            int cur = mesh.bvh_root_index;
                            int bvh_end = bvh_nodes[mesh.bvh_root_index].next_index;
                            while (cur < bvh_end && !obstacle_hit) {
                                BVHNode node = bvh_nodes[cur];
                                if (!intersect_aabb(node.bbox_min, node.bbox_max,
                                                    shadow_org_o, shadow_dir_o, t_min, t_max)) {
                                    cur = node.next_index;
                                } else {
                                    if (node.is_leaf) {
                                        for (int t = node.triangle_begin; t < node.triangle_end; t++) {
                                            uint3 tri = triangles[t] + mesh.vertex_offset;
                                            float3 v0 = vertices[tri.x];
                                            float3 v1 = vertices[tri.y];
                                            float3 v2 = vertices[tri.z];
                                            float3 b_unused;
                                            float t_shadow;
                                            if (intersect_tri(v0, v1, v2, shadow_org_o, shadow_dir_o,
                                                            t_min, t_max, b_unused, t_shadow)) {
                                                obstacle_hit = true;
                                                break;
                                            }
                                        }
                                    }
                                    cur = cur + 1;
                                }
                            }
                            if (obstacle_hit) {
                                break;
                            }
                        }
                        
                    }

                    if (!obstacle_hit) {
                        float3 l = normalize(intersection_to_light);

                        total_light += shapes[hit_i].Kd * lights[j].intensity * 1 / pow(t_max, 2) * max(0.0, dot(n, l));
                    }
                }
            } else {
                float3 n_o = normalize(
                    hit_b.x * vertex_normals[hit_tri.x] +
                    hit_b.y * vertex_normals[hit_tri.y] +
                    hit_b.z * vertex_normals[hit_tri.z]
                );
                n = normalize(xform_vec(shapes[hit_i].obj_to_world, n_o));
                for (int j = 0; j < num_lights; j++) {
                    float3 intersection_to_light = lights[j].position - hit_point;
                    float3 shadow_dir = normalize(intersection_to_light);
                    float t_max = length(intersection_to_light);

                    bool obstacle_hit = false;
                    for (int k = 0; k < num_shapes; k++) {
                        float3 shadow_org_o = xform_pt(shapes[k].world_to_obj, hit_point);
                        float3 shadow_dir_o = xform_vec(shapes[k].world_to_obj, intersection_to_light);

                        if (shapes[k].type == ShapeType.Sphere) {
                            Sphere maybe_sphere_obstacle = spheres[shapes[k].index];
                            float3 center = maybe_sphere_obstacle.center;
                            float radius = maybe_sphere_obstacle.radius;

                            float a = dot(shadow_dir_o, shadow_dir_o);
                            float b = -2.0 * (
                                dot(shadow_dir_o, center) - 
                                dot(shadow_org_o, shadow_dir_o));
                            float c = -2.0 * dot(shadow_org_o, center) + 
                                            dot(shadow_org_o, shadow_org_o) + 
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
                        } else {
                            TriangleMesh mesh = meshes[shapes[k].index];
                            int cur = mesh.bvh_root_index;
                            int bvh_end = bvh_nodes[mesh.bvh_root_index].next_index;
                            while (cur < bvh_end && !obstacle_hit) {
                                BVHNode node = bvh_nodes[cur];
                                if (!intersect_aabb(node.bbox_min, node.bbox_max,
                                                    shadow_org_o, shadow_dir_o, t_min, t_max)) {
                                    cur = node.next_index;
                                } else {
                                    if (node.is_leaf) {
                                        for (int t = node.triangle_begin; t < node.triangle_end; t++) {
                                            uint3 tri = triangles[t] + mesh.vertex_offset;
                                            float3 v0 = vertices[tri.x];
                                            float3 v1 = vertices[tri.y];
                                            float3 v2 = vertices[tri.z];
                                            float3 b_unused;
                                            float t_shadow;
                                            if (intersect_tri(v0, v1, v2, shadow_org_o, shadow_dir_o,
                                                            t_min, t_max, b_unused, t_shadow)) {
                                                obstacle_hit = true;
                                                break;
                                            }
                                        }
                                    }
                                    cur = cur + 1;
                                }
                            }
                            if (obstacle_hit) {
                                break;
                            }
                        }
                        
                    }

                    if (!obstacle_hit) {
                        float3 l = normalize(intersection_to_light);

                        total_light += shapes[hit_i].Kd * lights[j].intensity * 1 / pow(t_max, 2) * max(0.0, dot(n, l));
                    }
                }
            }
            color += throughput * total_light;
            throughput *= shapes[hit_i].Kr;

            float3 reflected_dir = reflect(normalize(camera_to_point_ray), n);
            ray_origin = hit_point + EPSILON * reflected_dir;
            camera_to_point_ray = reflected_dir;
        }
    }
    image[tid] = float4(color, 1.0);
}
