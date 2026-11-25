struct BVHNode {
    float3 bbox_min;
    float3 bbox_max;

    // which BVH node we should skip
    // to if this node is totally not
    // intersecting the ray
    // if next_index < 0, then we don't
    // have the next node to skip to
    int next_index;

    uint triangle_begin;
    uint triangle_end;

    bool is_leaf;
};

float point_aabb_distance(float3 x, float3 bmin, float3 bmax) {
    return length(x - clamp(x, bmin, bmax));
}

struct ClosestPoint {
    float3 position;
    float3 bary;
};

// From https://iquilezles.org/articles/distfunctions/
ClosestPoint closest_point_triangle(
        float3 p, float3 a, float3 b, float3 c) {
    float3 ba = b - a, pa = p - a;
    float3 cb = c - b, pb = p - b;
    float3 ac = a - c, pc = p - c;
    float3 nor = cross(ba, ac);

    float t0 = clamp(dot(ba, pa) / dot(ba, ba), 0.0, 1.0);
    float t1 = clamp(dot(cb, pb) / dot(cb, cb), 0.0, 1.0);
    float t2 = clamp(dot(ac, pc) / dot(ac, ac), 0.0, 1.0);

    float3 q0 = a + ba * t0;
    float3 q1 = b + cb * t1;
    float3 q2 = c + ac * t2;

    if (sign(dot(cross(ba, nor), pa)) +
        sign(dot(cross(cb, nor), pb)) +
        sign(dot(cross(ac, nor), pc)) < 2.0) {

        float d0 = dot(p - q0, p - q0);
        float d1 = dot(p - q1, p - q1);
        float d2 = dot(p - q2, p - q2);

        if (d0 < d1 && d0 < d2)
            return {q0, float3(1.0 - t0, t0, 0.0)};
        if (d1 < d2)
            return {q1, float3(0.0, 1.0 - t1, t1)};
        return {q2, float3(t2, 0.0, 1.0 - t2)};
    }

    float inv_nor2 = 1.0 / dot(nor, nor);
    float3 q = p - nor * (dot(nor, pa) * inv_nor2);

    float wb = dot(cross(pa, ac), nor) * inv_nor2;
    float wc = dot(cross(pa, ba), nor) * inv_nor2;
    return {q, float3(1.0 - wb - wc, wb, wc)};
}


[shader("compute")]
[numthreads(64, 1, 1)]
void detect_collision(uint tid : SV_DispatchThreadID,
                      StructuredBuffer<float3> positions,
                      StructuredBuffer<float> inv_masses,
                      StructuredBuffer<float4> planes,
                      StructuredBuffer<float4> spheres,
                      StructuredBuffer<float3> mesh_vertices,
                      StructuredBuffer<float3> mesh_vertex_normals,
                      StructuredBuffer<uint3> mesh_triangles,
                      StructuredBuffer<BVHNode> bvh_nodes,
                      RWStructuredBuffer<float4> contact_planes,
                      uniform uint num_particles,
                      uniform uint num_planes,
                      uniform uint num_spheres,
                      uniform uint num_bvh_nodes,
                      uniform float collision_distance,
                      uniform float contact_margin) {
    if (tid >= num_particles) {
        return;
    }
    // TODO: HW 4.6. Your code below.

    if (inv_masses[tid] == 0.0) {
        contact_planes[tid] = float4(0.0);
        return;
    }

    float3 pos = positions[tid];
    float threshold = contact_margin + collision_distance;

    float min_sdf = 1e30;
    float3 best_n = float3(0.0);
    float best_d = 0.0;

    for (uint i = 0; i < num_planes; i++) {
        float4 pl = planes[i];
        float3 n = normalize(pl.xyz);
        float d = pl.w;
        float sdf = dot(n, pos) - d;
        if (sdf < min_sdf) {
            min_sdf = sdf;
            best_n = n;
            best_d = d;
        }
    }

    for (uint j = 0; j < num_spheres; j++) {
        float4 sp = spheres[j];
        float3 center = sp.xyz;
        float radius = sp.w;
        float3 to_pos = pos - center;
        float dist = length(to_pos);
        float sdf = dist - radius;

        if (sdf < min_sdf) {
            min_sdf = sdf;
            float3 n = (dist > 1e-8) ? (to_pos / dist) : float3(0.0, 1.0, 0.0);
            float3 surf_pt = center + n * radius;
            best_n = n;
            best_d = dot(n, surf_pt);
        }
    }

    if (num_bvh_nodes > 0) {
        float min_mesh_dist = threshold;
        int best_tri = -1;
        float3 best_bary = float3(0.0);

        int node_idx = 0;
        while (node_idx >= 0 && node_idx < int(num_bvh_nodes)) {
            BVHNode node = bvh_nodes[node_idx];
            float box_dist = point_aabb_distance(pos, node.bbox_min, node.bbox_max);

            if (box_dist >= min_mesh_dist) {
                node_idx = node.next_index;
                continue;
            }

            if (node.is_leaf) {
                for (uint t = node.triangle_begin; t < node.triangle_end; t++) {
                    uint3 tri = mesh_triangles[t];
                    float3 p0 = mesh_vertices[tri.x];
                    float3 p1 = mesh_vertices[tri.y];
                    float3 p2 = mesh_vertices[tri.z];

                    ClosestPoint cp = closest_point_triangle(pos, p0, p1, p2);
                    float dist = length(pos - cp.position);

                    if (dist < min_mesh_dist) {
                        min_mesh_dist = dist;
                        best_tri = int(t);
                        best_bary = cp.bary;
                    }
                }
            }

            node_idx += 1;
        }

        if (best_tri >= 0) {
            uint3 tri = mesh_triangles[best_tri];
            float3 p0 = mesh_vertices[tri.x];
            float3 p1 = mesh_vertices[tri.y];
            float3 p2 = mesh_vertices[tri.z];

            float3 n0 = mesh_vertex_normals[tri.x];
            float3 n1 = mesh_vertex_normals[tri.y];
            float3 n2 = mesh_vertex_normals[tri.z];

            float3 ng = normalize(cross(p1 - p0, p2 - p0));
            float3 ns = normalize(best_bary.x * n0 + best_bary.y * n1 + best_bary.z * n2);
            if (dot(ng, ns) < 0.0) {
                ng = -ng;
            }

            float d_tri = dot(ng, p0);
            float mesh_sdf = dot(ng, pos) - d_tri;

            if (mesh_sdf < min_sdf) {
                min_sdf = mesh_sdf;
                best_n = ng;
                best_d = d_tri;
            }
        }
    }

    if (min_sdf < threshold) {
        contact_planes[tid] = float4(best_n, best_d + collision_distance);
    } else {
        contact_planes[tid] = float4(0.0);
    }
}
