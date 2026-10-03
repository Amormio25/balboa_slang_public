import hw1_common;

[shader("compute")]
[numthreads(8, 8, 1)]
void compute_main(uint2 tid : SV_DispatchThreadID,
                  uniform float3 background,
                  uniform int /*samples_per_axis*/, // ignore for now
                  StructuredBuffer<Shape> shapes,
                  uniform int num_shapes,
                  StructuredBuffer<Circle> circles,
                  StructuredBuffer<Polyline> polylines,
                  StructuredBuffer<QuadraticBezier> /*quadratic_beziers*/, // ignore for now
                  StructuredBuffer<float2> points,
                  RWTexture2D<float4> image) {
    uint width, height;
    image.GetDimensions(width, height);
    if (tid.x >= width || tid.y >= height) {
        return;
    }

    image[tid] = float4(background, 1.0);
    // TODO: your code here

    // render multiple shapes in a scene
    // scene is just like the bg, shapes, order of shapes, etc
    // Shape is like the shared stuff between each shape
    // for Shape.type=circle, Shape struct gives us index of circle inside the 
    //      circles buffer (which contains circle specific info)
    // for Shape.type=polylines, it gives us index of polyline shape inside the
    //      polylines buffer. polylines buffer gives us start and end indices
    //      of that polyline's points inside the points buffer
    // first shape rendered first, later shapes rendered on top of it givesus
    //      ordering

    // for shape in shapes
    //      if shape is circle
    //          get index into circles buff
    //          border stroke if applicable
    //          given circle center, no need to raycast simply check px location
    //      if shape is polyline
    //          get index into polylines buf
    //          get start and end indices of points for this polyline
    //          border stroke if applicable
    //          do same stuff as in 1_2
    for (int i = num_shapes-1; i >= 0; i--) {
        Shape shape = shapes[i];
        float2 q = float2(tid.x + 0.5, height - tid.y - 0.5);

        if (shape.type == ShapeType.Circle) {
            Circle circle = circles[shape.index];
            float distance = length(q - circle.center);

            bool in_circle = distance < circle.radius;
            // to be in circle stroke means past radius - w/2 and < radius + w/2
            bool in_stroke = (distance >= circle.radius - shape.stroke_width / 2) && (distance <= circle.radius + shape.stroke_width / 2);


            if (shape.use_fill && in_circle) {
                image[tid] = float4(shape.fill_rgba);
            }

            if (shape.use_stroke && in_stroke) {
                image[tid] = float4(shape.stroke_rgba);
            }
        } else if (shape.type == ShapeType.Polyline) {
            Polyline polyline = polylines[shape.index];

            int count = 0;
            int num_points = polyline.pts_end - polyline.pts_begin + 1;

            // float2 q = float2(tid.x + 0.5, height - tid.y - 0.5);
            bool in_stroke = false;
            bool in_join = false;

            for (int i = polyline.pts_begin + 1; i < polyline.pts_end; i++) {
                if (is_in_stroke(points[i-1], points[i], q, shape.stroke_width)) {
                    in_stroke = true;
                }

                // check for rounded joins everywhere except last two points
                if (i < polyline.pts_end - 1 && is_in_join(points[i], q, shape.stroke_width)) {
                    in_join = true;
                }

                count += raycast(points[i-1], points[i], q);
            }

            if (polyline.closed) {

                if (is_in_stroke(points[polyline.pts_end - 1], points[polyline.pts_begin], q, shape.stroke_width)) {
                    in_stroke = true;
                }

                // round cap for poly0 and poly-1
                if (is_in_join(points[polyline.pts_begin], q, shape.stroke_width) || is_in_join(points[polyline.pts_end-1], q, shape.stroke_width)) {
                    in_join = true;
                }

                count += raycast(points[polyline.pts_end - 1], points[polyline.pts_begin], q);

                if (count != 0 && shape.use_fill) {
                    image[tid] = float4(shape.fill_rgba);
                }
            }

            if (in_stroke && shape.use_stroke) {
                image[tid] = float4(shape.stroke_rgba);
            }
            if (in_join && shape.use_stroke) {
                image[tid] = float4(shape.stroke_rgba);
            }
        }
        
    }
}

bool is_in_stroke(float2 p0, float2 p1, float2 q, float stroke_width) {
    float2 vec = p1 - p0;
    float distance = length(vec);
    if (distance == 0.0) {
        return false;
    }

    float l = dot((vec), (q - p0) / distance);

    float2 q_prime = p0 + l * (vec / distance);
    float projection = length(q - q_prime);

    return l >= 0 && l <= distance && projection < stroke_width / 2;
}

bool is_in_join(float2 p, float2 q, float stroke_width) {
    float2 vec = q - p;
    float distance = length(vec);

    if (distance <= stroke_width / 2) {
        return true;
    }

    return false;
}

int raycast(float2 p0, float2 p1, float2 q) {
    float2 vec = p1 - p0;
    if (vec.y == 0) return 0;

    float t = (q.y - p0.y) / (vec.y);
    float s = -q.x + p0.x + t * vec.x;

    int count = 0;
    if (s >= 0 && t >= 0 && t <= 1) {
        if (vec.y > 0) {
            count += 1;
        } else if (vec.y < 0) {
            count -= 1;
        }
    }
    return count;
}