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

    image[tid] = float4(1.0);
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




    // start with edges
    // THIS CURRENTLY DOESN"T KEEP TRACK OF DIRECTION NEEDED FOR NZ RULE
    // might be able to during fill test by simply getting difference in y
    // pink example is more like nz rule so that must be it
    int count = 0;
    for (int i = 1; i < num_polyline; i++) {
        float2 vec = polyline[i] - polyline[i-1];

        float distance = length(vec);

        float2 q = tid.xy + float2(0.5, 0.5);
        // distance from p0 to q_prime
        float l = dot((vec), (q - polyline[i-1])) / distance;

        // point on line closest to q
        float2 q_prime = polyline[i-1] + l * (vec / distance);

        float projection = length(q - q_prime);

        if (l > 0 && l < distance && projection < stroke_width / 2 &&           
                use_stroke_color) {
            image[tid] = float4(stroke_color, 1.0);
        }

        // ray casting
        float t = (q.y - polyline[i-1].y) / (vec.y);
        float s = -q.x + polyline[i-1].x + dot(t, vec.x);

        // if s>=0 and 0<=t<=1 then ray intersects with line
        if (s >= 0 && t >= 0 && t <= 1) {
            if (vec.y > 0) {
                count += 1;
            } else if (vec.y < 0) {
                count -= 1;
            } // else do nothing we're on horizontal line I think
        }

    }

    // ALSO STILL NEED TOA CCOUNT FOR JOINS AND CAPS
    // connect if closed, and fill color only if closed
    // ALSO RECALL if point is exactly on edge line no need to check
    if (is_closed) {
        float2 vec = polyline[num_polyline - 1] - polyline[0];
        float distance = length(vec);

        float2 q = tid.xy + float2(0.5, 0.5);
        float l = dot((vec), (q - polyline[0])) / distance;

        float2 q_prime = polyline[0] + l * (vec / distance);
        float projection = length(q - q_prime);

        if (l > 0 && l < distance && projection < stroke_width / 2 &&           
                use_stroke_color) {
            image[tid] = float4(stroke_color, 1.0);
        }

        // ray casting for inside check, also account for hitting vertex 
        if (count != 0 && use_fill_color) {
            image[tid] = float4(fill_color, 1.0);
        }
        
    }


}
