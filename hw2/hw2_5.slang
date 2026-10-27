[shader("compute")]
[numthreads(64, 1, 1)]
void clear_buffers(uint tid : SV_DispatchThreadID,
                   uniform uint num_pixels,
                   RWStructuredBuffer<uint> depth_buffer,
                   RWStructuredBuffer<uint> triangle_id_buffer) {
    if (tid >= num_pixels)
        return;

    depth_buffer[tid] = 0xffffffff;
    triangle_id_buffer[tid] = 0xffffffff;
}

[shader("compute")]
[numthreads(64, 1, 1)]
void transform_vertices(
    uint tid : SV_DispatchThreadID,
    uniform uint num_vertices,
    uniform uint vertex_offset,
    uniform float4x4 MVP,
    StructuredBuffer<float3> vertices,
    RWStructuredBuffer<float3> projected_vertices)
{
    if (tid >= num_vertices)
        return;

    uint i = vertex_offset + tid;
    float4 p = mul(MVP, float4(vertices[i], 1.0));
    projected_vertices[i] = p.xyz / p.w;
}

[shader("compute")]
[numthreads(64, 1, 1)]
void rasterize_depth(
        uint tid : SV_DispatchThreadID,
        uniform uint num_triangles,
        uniform uint width,
        uniform uint height,
        uniform float s,
        uniform float a,
        StructuredBuffer<uint3> faces,
        // A projected vertex store the screen space coordinates
        // in xy, and the inverse depth in z.
        StructuredBuffer<float3> projected_vertices,
        RWStructuredBuffer<uint> depth_buffer) {
    // HW 2.5 TODO
    if (tid >= num_triangles) {
        return;
    }

    uint3 face = faces[tid];
    float3 pv0 = projected_vertices[face.x];
    float3 pv1 = projected_vertices[face.y];
    float3 pv2 = projected_vertices[face.z];
    float2 sp0 = pv0.xy;
    float2 sp1 = pv1.xy;
    float2 sp2 = pv2.xy;

    // similar stuff as before, the z is already the invdepth
    float inv_depth0 = pv0.z;
    float inv_depth1 = pv1.z;
    float inv_depth2 = pv2.z;

    // like our aabb boounding box
    int xmin = int(floor(min(min(sp0.x, sp1.x), sp2.x)));
    int ymin = int(floor(min(min(sp0.y, sp1.y), sp2.y)));
    int xmax = int(ceil(max(max(sp0.x, sp1.x), sp2.x)));
    int ymax = int(ceil(max(max(sp0.y, sp1.y), sp2.y)));

    float area_012 = tri_area(sp0, sp1, sp2);
    if (area_012 == 0.0) {
        return;
    }

    // check each pixel in the bounding box
    for (int py = ymin; py <= ymax; py++) {
        for (int px = xmin; px <= xmax; px++) {
            // outside the box
            if (px < 0 || py < 0 || uint(px) >= width || uint(py) >= height) {
                continue;
            }

            // am i in the triangle (inside box still) repeats
            float2 p = float2(px + 0.5, py + 0.5);

            float2 edge0 = sp1 - sp0;
            float2 edge1 = sp2 - sp1;
            float2 edge2 = sp0 - sp2;

            float2 normal0 = float2(edge0.y, -edge0.x);
            float2 normal1 = float2(edge1.y, -edge1.x);
            float2 normal2 = float2(edge2.y, -edge2.x);

            float result0 = dot(p - sp0, normal0);
            float result1 = dot(p - sp1, normal1);
            float result2 = dot(p - sp2, normal2);

            bool all_positive = result0 >= 0 && result1 >= 0 && result2 >= 0;
            bool all_negative = result0 <= 0 && result1 <= 0 && result2 <= 0;
            if (!all_positive && !all_negative) {
                continue;
            }

            // projected calculations so copied over, main thing is the atomic operation below, check dpeth of pixel on triangle (like how much the px is pulled by the vertices or the contributions of the vertices on this px, whereas projected_vertices is just the sp coordinates and depth of vertices)
            float b0_prime = tri_area(p, sp1, sp2) / area_012;
            float b1_prime = tri_area(sp0, p, sp2) / area_012;
            float b2_prime = tri_area(sp0, sp1, p) / area_012;
            float B = 1.0 / ((b0_prime / (-inv_depth0)) +
                             (b1_prime / (-inv_depth1)) +
                             (b2_prime / (-inv_depth2)));

            float b0 = b0_prime * B / (-inv_depth0);
            float b1 = b1_prime * B / (-inv_depth1);
            float b2 = b2_prime * B / (-inv_depth2);

            float z0 = -1.0 / inv_depth0;
            float z1 = -1.0 / inv_depth1;
            float z2 = -1.0 / inv_depth2;
            float pz = b0 * z0 + b1 * z1 + b2 * z2;
            float depth = -pz;
            uint idx = uint(py) * width + uint(px);

            // basically got closest depth per pixel but not yet from which triangle
            InterlockedMin(depth_buffer[idx], asuint(depth));
        }
    }
}

float tri_area(float2 a, float2 b, float2 c) {
    float2 u = b - a;
    float2 v = c - a;
    return u.x * v.y - u.y * v.x;
}

[shader("compute")]
[numthreads(64, 1, 1)]
void rasterize_id(
        uint tid : SV_DispatchThreadID,
        uniform uint num_triangles,
        uniform uint width,
        uniform uint height,
        uniform float s,
        uniform float a,
        StructuredBuffer<uint3> faces,
        StructuredBuffer<float3> projected_vertices,
        RWStructuredBuffer<uint> depth_buffer,
        RWStructuredBuffer<uint> triangle_id_buffer) {
    // HW 2.5 TODO
    if (tid >= num_triangles) {
        return;
    }

    // LLM usage:
    // Model: ChatGPT GPT-6
    // For help understanding the things conceptually and how they were as code I used ChatGPT. One large confusion I had was why do we have projected vertices if we seem to already be doing all the barycentric calculations to get the contribution of vertices on pixels. I also asked for explanations on what asuint is and the reasoning behind getting depth and having to atomically update.
    uint3 face = faces[tid];
    float3 pv0 = projected_vertices[face.x];
    float3 pv1 = projected_vertices[face.y];
    float3 pv2 = projected_vertices[face.z];
    float2 sp0 = pv0.xy;
    float2 sp1 = pv1.xy;
    float2 sp2 = pv2.xy;

    // similar stuff as before, the z is already the invdepth
    float inv_depth0 = pv0.z;
    float inv_depth1 = pv1.z;
    float inv_depth2 = pv2.z;

    // like our aabb boounding box
    int xmin = int(floor(min(min(sp0.x, sp1.x), sp2.x)));
    int ymin = int(floor(min(min(sp0.y, sp1.y), sp2.y)));
    int xmax = int(ceil(max(max(sp0.x, sp1.x), sp2.x)));
    int ymax = int(ceil(max(max(sp0.y, sp1.y), sp2.y)));

    float area_012 = tri_area(sp0, sp1, sp2);
    if (area_012 == 0.0) {
        return;
    }

    // check each pixel in the bounding box
    for (int py = ymin; py <= ymax; py++) {
        for (int px = xmin; px <= xmax; px++) {
            // outside the box
            if (px < 0 || py < 0 || uint(px) >= width || uint(py) >= height) {
                continue;
            }

            // am i in the triangle (inside box still) repeats
            float2 p = float2(px + 0.5, py + 0.5);

            float2 edge0 = sp1 - sp0;
            float2 edge1 = sp2 - sp1;
            float2 edge2 = sp0 - sp2;

            float2 normal0 = float2(edge0.y, -edge0.x);
            float2 normal1 = float2(edge1.y, -edge1.x);
            float2 normal2 = float2(edge2.y, -edge2.x);

            float result0 = dot(p - sp0, normal0);
            float result1 = dot(p - sp1, normal1);
            float result2 = dot(p - sp2, normal2);

            bool all_positive = result0 >= 0 && result1 >= 0 && result2 >= 0;
            bool all_negative = result0 <= 0 && result1 <= 0 && result2 <= 0;
            if (!all_positive && !all_negative) {
                continue;
            }

            // projected calculations so copied over, main thing is the atomic operation below, check dpeth of pixel on triangle (like how much the px is pulled by the vertices or the contributions of the vertices on this px, whereas projected_vertices is just the sp coordinates and depth of vertices)
            float b0_prime = tri_area(p, sp1, sp2) / area_012;
            float b1_prime = tri_area(sp0, p, sp2) / area_012;
            float b2_prime = tri_area(sp0, sp1, p) / area_012;
            float B = 1.0 / ((b0_prime / (-inv_depth0)) +
                             (b1_prime / (-inv_depth1)) +
                             (b2_prime / (-inv_depth2)));

            float b0 = b0_prime * B / (-inv_depth0);
            float b1 = b1_prime * B / (-inv_depth1);
            float b2 = b2_prime * B / (-inv_depth2);

            float z0 = -1.0 / inv_depth0;
            float z1 = -1.0 / inv_depth1;
            float z2 = -1.0 / inv_depth2;
            float pz = b0 * z0 + b1 * z1 + b2 * z2;
            float depth = -pz;

            // image is like 2d arr, this is like row * size of row + col gives us index into 1d arr
            uint idx = uint(py) * width + uint(px);

            // basically got closest depth per pixel but not yet from which triangle
            // so at this pixel, if im same depth layer try to put my id atomically (possible several qualify, but handled)
            if (asuint(depth) == depth_buffer[idx]) {
                InterlockedMin(triangle_id_buffer[idx], tid);
            }        
        }
    }
}

[shader("compute")]
[numthreads(8, 8, 1)]
void shade(
        uint2 tid : SV_DispatchThreadID,
        uniform uint width,
        uniform uint height,
        uniform float s,
        uniform float a,
        StructuredBuffer<uint3> faces,
        StructuredBuffer<float3> vertex_colors,
        StructuredBuffer<float3> projected_vertices,
        StructuredBuffer<uint> triangle_id_buffer,
        RWTexture2D<float4> image) {
    if (tid.x >= width || tid.y >= height) {
        return;
    }

    // HW 2.5 TODO
    // for pixel check for valid face, if  so get the vertices with inv
    // depth and colors
    // mostly same implementation
    uint idx = tid.y * width + tid.x;
    uint face_id = triangle_id_buffer[idx];
    if (face_id == 0xffffffff) {
        return;
    }

    uint3 face = faces[face_id];
    float3 pv0 = projected_vertices[face.x];
    float3 pv1 = projected_vertices[face.y];
    float3 pv2 = projected_vertices[face.z];

    float2 sp0 = pv0.xy;
    float2 sp1 = pv1.xy;
    float2 sp2 = pv2.xy;

    float inv_depth0 = pv0.z;
    float inv_depth1 = pv1.z;
    float inv_depth2 = pv2.z;

    float3 c0 = vertex_colors[face.x];
    float3 c1 = vertex_colors[face.y];
    float3 c2 = vertex_colors[face.z];

    float2 p = float2(tid.x + 0.5, tid.y + 0.5);
    float area_012 = tri_area(sp0, sp1, sp2);
    if (area_012 == 0.0) {
        return;
    }

    float b0_prime = tri_area(p, sp1, sp2) / area_012;
    float b1_prime = tri_area(sp0, p, sp2) / area_012;
    float b2_prime = tri_area(sp0, sp1, p) / area_012;
    float B = 1.0 / ((b0_prime / (-inv_depth0)) +
                    (b1_prime / (-inv_depth1)) +
                    (b2_prime / (-inv_depth2)));

    float b0 = b0_prime * B / (-inv_depth0);
    float b1 = b1_prime * B / (-inv_depth1);
    float b2 = b2_prime * B / (-inv_depth2);

    float3 color = b0 * c0 + b1 * c1 + b2 * c2;
    image[tid] = float4(color, 1.0);
}
