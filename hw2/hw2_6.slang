StructuredBuffer<float3> vertices;
StructuredBuffer<float3> vertex_colors;
uniform float4x4 MVP;

struct VertexOutput {
    float4 position : SV_Position;
    float3 color : COLOR0;
};

[shader("vertex")]
VertexOutput vertex_main(uint vid : SV_VertexID) {
    VertexOutput output;
    // HW 2.6: your code here
    float3 pos = vertices[vid];
    // this mvp now transforms into clip space and not screen space so we don't have the divide by ws as gpu expects 4d homogenous coord/position
    output.position = mul(MVP, float4(pos, 1.0));
    output.color = vertex_colors[vid];
    return output;
}

[shader("fragment")]
float4 fragment_main(VertexOutput input) : SV_Target {
    // HW 2.6: your code here
    return float4(input.color, 1.0);
}
