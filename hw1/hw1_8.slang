import hw1_common;

[shader("compute")]
[numthreads(8, 8, 1)]
void compute_main(uint2 tid : SV_DispatchThreadID,
                  uniform float3 background,
                  uniform int samples_per_axis,
                  StructuredBuffer<Shape> shapes,
                  uniform int num_shapes,
                  StructuredBuffer<Circle> circles,
                  StructuredBuffer<Polyline> polylines,
                  StructuredBuffer<QuadraticBezier> quadratic_beziers,
                  StructuredBuffer<float2> points,
                  RWTexture2D<float4> image) {
    uint width, height;
    image.GetDimensions(width, height);
    if (tid.x >= width || tid.y >= height) {
        return;
    }

    image[tid] = float4(background, 1.0);
    

    float4 total_color = float4(0);
    for (int j = 0; j < pow(samples_per_axis, 2); j++) {
        int row = j / samples_per_axis;
        int col = j % samples_per_axis;
        float4 start_color = float4(background, 1.0); 
        
        for (int i = num_shapes-1; i >= 0; i--) {
          
            Shape shape = shapes[i];
            float2 q = float2(tid.x + (col + 0.5) / samples_per_axis, height - tid.y - (row + 0.5) / samples_per_axis);
            float2 q_in_object_space = mul(shape.world_to_obj, float3(q, 1.0)).xy;

            
            if (shape.type == ShapeType.Circle) {
                Circle circle = circles[shape.index];
                float distance = length(q_in_object_space - circle.center);
                
                bool in_circle = distance < circle.radius;
                // to be in circle stroke means past radius - w/2 and < radius + w/2
                bool in_stroke = (distance >= circle.radius - shape.stroke_width / 2) && (distance <= circle.radius + shape.stroke_width / 2);
                
                
                if (shape.use_fill && in_circle) {
                    // image[tid] = float4(shape.fill_rgba);
                  
                    start_color = float4(
                        float3(shape.fill_rgba.rgb) * float(shape.fill_rgba.a) + float(1 - shape.fill_rgba.a) * start_color.rgb,
                        shape.fill_rgba.a + (1 - shape.fill_rgba.a) * start_color.a
                    );
                }

                if (shape.use_stroke && in_stroke) {
                    // image[tid] = float4(shape.stroke_rgba);
                    start_color = float4(
                        float3(shape.stroke_rgba.rgb) * float(shape.stroke_rgba.a) + float(1 - shape.stroke_rgba.a) * start_color.rgb,
                        shape.stroke_rgba.a + (1 - shape.stroke_rgba.a) * start_color.a
                    );
                }
            } else if (shape.type == ShapeType.Polyline) {
                Polyline polyline = polylines[shape.index];

                int count = 0;
                int num_points = polyline.pts_end - polyline.pts_begin + 1;

                // float2 q = float2(tid.x + 0.5, height - tid.y - 0.5);
                bool in_stroke = false;
                bool in_join = false;

                for (int i = polyline.pts_begin + 1; i < polyline.pts_end; i++) {
                    if (is_in_stroke(points[i-1], points[i], q_in_object_space, shape.stroke_width)) {
                        in_stroke = true;
                    }

                    // check for rounded joins everywhere except last two points
                    if (i < polyline.pts_end - 1 && is_in_join(points[i], q_in_object_space, shape.stroke_width)) {
                        in_join = true;
                    }

                    count += raycast(points[i-1], points[i], q_in_object_space);
                }

                if (polyline.closed) {

                    if (is_in_stroke(points[polyline.pts_end - 1], points[polyline.pts_begin], q_in_object_space, shape.stroke_width)) {
                        in_stroke = true;
                    }

                    // round cap for poly0 and poly-1
                    if (is_in_join(points[polyline.pts_begin], q_in_object_space, shape.stroke_width) || is_in_join(points[polyline.pts_end-1], q_in_object_space, shape.stroke_width)) {
                        in_join = true;
                    }

                    count += raycast(points[polyline.pts_end - 1], points[polyline.pts_begin], q_in_object_space);

                    if (count != 0 && shape.use_fill) {
                        // image[tid] = float4(shape.fill_rgba);
                        start_color = float4(
                            float3(shape.fill_rgba.rgb) * float(shape.fill_rgba.a) + float(1 - shape.fill_rgba.a) * start_color.rgb,
                            shape.fill_rgba.a + (1 - shape.fill_rgba.a) * start_color.a
                        );
                    }
                }

                if ((in_stroke || in_join) && shape.use_stroke) {
                    start_color = float4(
                        float3(shape.stroke_rgba.rgb) * float(shape.stroke_rgba.a) + float(1 - shape.stroke_rgba.a) * start_color.rgb,
                        shape.stroke_rgba.a + (1 - shape.stroke_rgba.a) * start_color.a
                    );
                } 
            } else if (shape.type == ShapeType.QuadraticBezier) {
                QuadraticBezier curve = quadratic_beziers[shape.index];
                int count = 0;
                bool in_stroke = false;
                bool in_join = false;

                for (int i = curve.pts_begin; i < curve.pts_end - 2; i += 2) {
                    float2 p0 = points[i];
                    float2 p1 = points[i+1];
                    float2 p2 = points[i+2];
                    
                    if (bezier_in_stroke(p0, p1, p2, q_in_object_space, shape.stroke_width)) {
                        in_stroke = true;
                    }
                    
                    if (i+2 < curve.pts_end &&
                        is_in_join(points[i+2], q_in_object_space, shape.stroke_width)) {
                            in_join = true;
                        }

                    count += bezier_raycast(p0, p1, p2, q_in_object_space);
                }

                if (curve.closed) {
                    float2 p0 = points[curve.pts_end - 2];
                    float2 p1 = points[curve.pts_end - 1];
                    float2 p2 = points[curve.pts_begin];

                    
                    if (bezier_in_stroke(p0, p1, p2, q_in_object_space, shape.stroke_width)) {
                        in_stroke = true;
                    }
                    
                    if (is_in_join(points[curve.pts_begin], q_in_object_space, shape.stroke_width) ||
                    is_in_join(points[curve.pts_end - 1], q_in_object_space, shape.stroke_width)) {
                        in_join = true;
                    }

                    count += bezier_raycast(p0, p1, p2, q_in_object_space);
                    
                    if (count != 0 && shape.use_fill) {
                        start_color = float4(
                            float3(shape.fill_rgba.rgb) * float(shape.fill_rgba.a) +
                            float(1 - shape.fill_rgba.a) * start_color.rgb,
                            shape.fill_rgba.a + (1 - shape.fill_rgba.a) * start_color.a
                        );
                    }
                }

                if ((in_stroke || in_join) && shape.use_stroke) {
                    start_color = float4(
                        float3(shape.stroke_rgba.rgb) * float(shape.stroke_rgba.a) +
                            float(1 - shape.stroke_rgba.a) * start_color.rgb,
                        shape.stroke_rgba.a + (1 - shape.stroke_rgba.a) * start_color.a
                    );
                }
            }
        }
        total_color += start_color;
    }
    image[tid] = total_color / float(pow(samples_per_axis, 2));
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

// just x or y something like that one coord
float eval_bezier1d(float s0, float s2, float s3, float t) {
    return (1.0 - t) * (1.0 - t) * s0 
            + 2.0 * (1.0 - t) * t * s2 + t * t * s3;
}

// get point on curve
float2 eval_bezier2d(float2 p0, float2 p1, float2 p2, float t) {
    return float2(
        eval_bezier1d(p0.x, p1.x, p2.x, t),
        eval_bezier1d(p0.y, p1.y, p2.y, t)
    );
}

int bezier_raycast_hit(float t, float2 p0, float2 p1, float2 p2, float2 q) {
    // outside our bounds
    if (t < 0.0 || t > 1.0) {
        return 0;
    }

    float x = eval_bezier1d(p0.x, p1.x, p2.x, t);

    // to the left, shouldn't count since raycast is to the right
    if (x - q.x < 0.0) {
        return 0;
    }

    float dy_dt = 2.0 * (1.0 - t) * (p1.y - p0.y) 
                + 2.0 * t * (p2.y - p1.y);

    // upwards
    if (dy_dt > 0.0) {
        return 1;
    }

    // downwards
    if (dy_dt < 0.0) {
        return -1;
    }
    return 0;
}

int bezier_raycast(float2 p0, float2 p1, float2 p2, float2 q) {
    float a = p0.y - 2.0 * p1.y + p2.y;
    float b = 2.0 * (p1.y - p0.y);
    float c = p0.y - q.y;
    float2 roots;

    if (!solve_quadratic(a, b, c, roots)) {
        return 0;
    }

    // now have t and can check if actually hits the curve
    int count = bezier_raycast_hit(roots.x, p0, p1, p2, q);

    // just in case fp errors copy one from solve helper, check if we got two roots if so check y
    if (abs(roots.x - roots.y) > 1e-6) {
        count += bezier_raycast_hit(roots.y, p0, p1, p2, q);
    }
    
    return count;
}

bool bezier_in_stroke(float2 p0, float2 p1, float2 p2, float2 q, float stroke_width) {
    // given eqs: ||q(t)-p||^2
    // derivative eventually is (q(t)-p) dot q'(t) = 0
    // from earlier q(t)-p = at^2 +bt + c since p(t) = p0(1-t)^2...
    // deriv is 2at+b
    // so its at2+bt+c dot 2at+b=0
    // 2 adota t^3
    // + 3 adotb t^2
    //  + 2a dotc + bdotb t
    // + bdotc

    float half_w = stroke_width / 2.0;
    // basically quick check endpoints since  solve cubic checks interior only
    if (length(eval_bezier2d(p0, p1, p2, 0.0) - q) < half_w) {
        return true;
    }
    if (length(eval_bezier2d(p0, p1, p2, 1.0) - q) < half_w) {
        return true;
    }

    float2 a = p0 - 2.0 * p1 + p2;
    float2 b = 2.0 * (p1 - p0);
    float2 c = p0 - q;

    float A = 2.0 * dot(a, a);
    float B = 3.0 * dot(a, b);
    float C = 2.0 * dot(a, c) + dot(b, b);
    float D = dot(b, c);

    float3 roots;
    // closest interior point to q possibly 3 values
    // roots holds the t values
    int n = solve_cubic(A, B, C, D, roots);

    if (n >= 1) {
        float t0 = roots.x;
        if (t0 >= 0.0 && t0 <= 1.0 && length(eval_bezier2d(p0, p1, p2, t0) - q) < half_w) {
            return true;
        }
    }

    if (n >= 2) {
        float t1 = roots.y;
        if (t1 >= 0.0 && t1 <= 1.0 && length(eval_bezier2d(p0, p1, p2, t1) - q) < half_w) {
            return true;
        }
    }

    if (n >= 3) {
        float t2 = roots.z;
        if (t2 >= 0.0 && t2 <= 1.0 && length(eval_bezier2d(p0, p1, p2, t2) - q) < half_w) {
            return true;
        }
    }

    return false;
}