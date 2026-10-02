import hw1_common;

[shader("compute")]
[numthreads(8, 8, 1)]
void compute_main(uint2 tid : SV_DispatchThreadID,
                  StructuredBuffer<float2> polyline,
                  uniform int num_polyline,
                  uniform bool is_closed,
                  uniform bool use_fill_color,
                  uniform float3 fill_color,
                  uniform bool use_stroke_color,
                  uniform float3 stroke_color,
                  uniform float stroke_width,
                  RWTexture2D<float4> image) {
    uint width, height;
    image.GetDimensions(width, height);
    if (tid.x >= width || tid.y >= height) {
        return;
    }

    image[tid] = float4(0.5, 0.5, 0.5, 1.0);

    // TODO: your code here
        // polyline is the sequence of points
        //      each consec point is edge, last->first if is_closed true
        // num_polylines gives us number of points in polyline, open is N-1 edges
        // is_closed lets us know if we can have fill color and if lsat connects first
        // use_fill_color if need to color (could just be shape that's
        //      not colored)
        // fill_color is the color to fill with if applicable
        // use_stroke_color if they want to color the stroke or even show it
        // stroke_color color
        // stroke_width for width remember the w/2 thing

        // high level todo
        // use polyline buffer of points to draw the edges
        // use is_closed to see if p1 connects to pn
        // for each pixel check
        //      if its in stroke
        //      if its in interior of shape 
        //          (here need to use the ray cast method and even/odd or nonzero
        //          for coloring)
        //      what color






        // triangle and star currently breaks
        // second ref stroke isn't thick enough

        // ALSO STILL NEED TOA CCOUNT FOR JOINS AND CAPS
        // connect if closed, and fill color only if closed
        // ALSO RECALL if point is exactly on edge line no need to check

    int count = 0;
    float2 q = float2(tid.x + 0.5, height - tid.y - 0.5);
    bool in_stroke = false;
    bool in_join = false;
    for (int i = 1; i < num_polyline; i++) {
        if (is_in_stroke(polyline[i-1], polyline[i], q, stroke_width)) {
            in_stroke = true;
        }

        // check for rounded joins everywhere except last two points
        if (i < num_polyline - 1 && is_in_join(polyline[i], q, stroke_width)) {
            in_join = true;
        }

        count += raycast(polyline[i-1], polyline[i], q);
    }

    if (is_closed) {

        if (is_in_stroke(polyline[num_polyline - 1], polyline[0], q, stroke_width)) {
            in_stroke = true;
        }

        // round cap for poly0 and poly-1
        if (is_in_join(polyline[0], q, stroke_width) || is_in_join(polyline[num_polyline-1], q, stroke_width)) {
            in_join = true;
        }

        count += raycast(polyline[num_polyline - 1], polyline[0], q);

        if (count != 0 && use_fill_color) {
            image[tid] = float4(fill_color, 1.0);
        }
    }

    if (in_stroke && use_stroke_color) {
        image[tid] = float4(stroke_color, 1.0);
    }
    if (in_join && use_stroke_color) {
        image[tid] = float4(stroke_color, 1.0);
    }


    // vertices since mine from star and second polyline are getting cut off



    


    // 
        // int count = 0;
        // if (is_closed) {
        //     float2 vec = polyline[num_polyline - 1] - polyline[0];
        //     float distance = length(vec);

        //     float2 q = float2(tid.x + 0.5, height - tid.y - 0.5);
        //     float l = dot((vec), (q - polyline[0])) / distance;

        //     float2 q_prime = polyline[0] + l * (vec / distance);
        //     float projection = length(q - q_prime);

        //     // ray cast on last edge
        //     if (vec.y != 0) { // not on horizontal edge
        //         float t = (q.y - polyline[0].y) / (vec.y);
        //         float s = -q.x + polyline[0].x + t * vec.x;
                
                
        //         // if s>=0 and 0<=t<=1 then ray intersects with line
        //         if (s >= 0 && t >= 0 && t <= 1) {
        //             if (vec.y > 0) {
        //                 count += 1;
        //             } else if (vec.y < 0) {
        //                 count -= 1;
        //             } // else do nothing we're on horizontal line I think
        //         }
        //     }

        //     if (l >= 0 && l <= distance && projection < stroke_width / 2 && use_stroke_color) {
        //         image[tid] = float4(stroke_color, 1.0);
        //     }
        // }

        // // start with edges
        // // THIS CURRENTLY DOESN"T KEEP TRACK OF DIRECTION NEEDED FOR NZ RULE
        // // might be able to during fill test by simply getting difference in y
        // // pink example is more like nz rule so that must be it
        // for (int i = 1; i < num_polyline; i++) {
        //     float2 vec = polyline[i] - polyline[i-1];

        //     float distance = length(vec);

        //     float2 q = float2(tid.x + 0.5, height - tid.y - 0.5);
        //     // distance from p0 to q_prime
        //     float l = dot((vec), (q - polyline[i-1])) / distance;

        //     // point on line closest to q
        //     float2 q_prime = polyline[i-1] + l * (vec / distance);

        //     float projection = length(q - q_prime);

        //     if (l >= 0 && l <= distance && projection < stroke_width / 2 && use_stroke_color) {

        //         image[tid] = float4(stroke_color, 1.0);
        //     }

        //     // ray casting
        //     if (vec.y == 0) {
        //         continue; // we're on horizontal edge
        //     }
        //     float t = (q.y - polyline[i-1].y) / (vec.y);
        //     float s = -q.x + polyline[i-1].x + t * vec.x;
            

        //     // if s>=0 and 0<=t<=1 then ray intersects with line
        //     if (s >= 0 && t >= 0 && t <= 1) {
        //         if (vec.y > 0) {
        //             count += 1;
        //         } else if (vec.y < 0) {
        //             count -= 1;
        //         } // else do nothing we're on horizontal line I think
        //     }

        // }

        // if (is_closed) {
        //     if (count != 0 && use_fill_color) {
        //         image[tid] = float4(fill_color, 1.0);
        //     }
        // }

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

// for a closed triangle, all three vertices are joins for an open polyline, the first and last points are caps, the points in between are joins.