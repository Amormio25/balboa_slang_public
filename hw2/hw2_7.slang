StructuredBuffer<float3> vertices;
StructuredBuffer<float3> vertex_normals;
StructuredBuffer<float2> vertex_uvs;
uniform float4x4 MVP;
uniform float4x4 model_matrix;
uniform float3x3 normal_matrix; // inverse transpose of the top-left 3x3 above
uniform float3 light_dir;
uniform float3 light_color;
uniform float3 camera_position;
uniform float3 Ks;
uniform float exponent;
Texture2D<float4> Kd_texture;
SamplerState Kd_sampler;

struct VertexOutput {
    float4 position : SV_Position;
    float3 world_position : TEXCOORD0;
    float3 world_normal : TEXCOORD1;
    float2 uv : TEXCOORD2;
};

[shader("vertex")]
VertexOutput vertex_main(uint vid : SV_VertexID) {
    VertexOutput output;
    // HW 2.7 TODO: implement
    float3 pos = vertices[vid];
    float3 n = vertex_normals[vid];

    output.position = mul(MVP, float4(pos, 1.0));
    output.world_position = mul(model_matrix, float4(pos, 1.0)).xyz;

    // normalize the normal to make it len 1 later on
    // these transformed normals the gpu will blend across triangle and fragment shader gets the world normal as input attribute
    output.world_normal = mul(normal_matrix, n);

    // LLM usage:
    // Model: ChatGPT GPT-6
    // I forgot what UV mapping was so I asked ChatGPT how it worked to help me understand how I might use it in this function, and my understanding was just that I needed to assign the already given uv for the vertex id to the output which we'll then send over to fragment main.
    output.uv = vertex_uvs[vid];
    return output;
}

[shader("fragment")]
float4 fragment_main(VertexOutput input) : SV_Target {
    // HW 2.7 TODO: implement

    // LLM usage:
    // Model: ChatGPT GPT-6
    // I used ChatGPT to explain some of the light concepts and what Kd and Ks were for example. Given the writeup I was still confused even with the provided formulas so I used it as like a conceptual teacher to understand better.
    // which way does surface face
    // wheres my light
    //      just one direction so it should be the same for each px
    // where am I "standing"
    // what color is the thing here

    // Kd is color of material at this px
    // Ks is like shinyness, and exponent is like how concentrated the shiny spot is
    // color ambient diffuse and specular 
    float3 Kd = Kd_texture.Sample(Kd_sampler, input.uv).rgb;

    float3 n = normalize(input.world_normal);
    float3 l = normalize(light_dir); // dir toward light
    float3 v = normalize(camera_position - input.world_position); // surface to camera

    float3 color_ambient = 0.2 * Kd;

    float nl = max(0.0, dot(n, l));
    float3 color_diffusion = Kd * light_color * nl;

    // only add the shininess when light hits front
    float3 color_specular = float3(0.0, 0.0, 0.0);
    // given formula
    if (nl > 0.0) {
        float3 r = reflect(-l, n);
        float rv = max(0.0, dot(r, v));
        // make it shinier if r and v are much closer
        color_specular = Ks * light_color * pow(rv, exponent);
    }

    float3 C = color_ambient + color_diffusion + color_specular;
    return float4(C, 1.0);
}
