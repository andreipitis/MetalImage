//
//  DisplayShaders.metal
//  MetalImage
//
//  Created by Andrei-Sergiu Pițiș on 19/05/2017.
//  Copyright © 2017 Andrei-Sergiu Pițiș. All rights reserved.
//

#include <metal_stdlib>
using namespace metal;

struct VertexOut {
    float4 position [[position]];
    float2 textureCoorinates;
};

vertex VertexOut basic_vertex(const device packed_float2* vertex_array [[ buffer(0) ]], const device packed_float2* texture_array [[ buffer(1) ]], unsigned int vid [[ vertex_id ]]) {
    float x = vertex_array[vid][0];
    float y = vertex_array[vid][1];
    
    float texX = texture_array[vid][0];
    float texY = texture_array[vid][1];
    
    VertexOut vertexData = VertexOut();
    vertexData.position = float4(x, y, 0.0, 1.0);
    vertexData.textureCoorinates = float2(texX, texY);
    return vertexData;
}

fragment half4 basic_fragment(VertexOut fragmentIn [[stage_in]], texture2d<float, access::sample> tex2d [[texture(0)]]) {
    constexpr sampler sampler2d(filter::linear);
    
    return half4(tex2d.sample(sampler2d, fragmentIn.textureCoorinates));
}

constant half3 kRec709Luma = half3(0.2126, 0.7152, 0.0722);

// Grayscale compute shader
kernel void basic_compute(texture2d<half, access::read>  inTexture   [[ texture(0) ]],
                          texture2d<half, access::write> outTexture  [[ texture(1) ]],
                          uint2                          gid         [[ thread_position_in_grid ]])
{
    if((gid.x < outTexture.get_width()) && (gid.y < outTexture.get_height()))
    {
        half4 inColor  = inTexture.read(gid);
        half  gray     = dot(inColor.rgb, kRec709Luma);
        half4 outColor = half4(gray, gray, gray, 1.0);
        
        outTexture.write(outColor, gid);
    }
}

// Grayscale compute shader
kernel void basic_compute2(texture2d<half, access::read>  inTexture   [[ texture(0) ]],
                          texture2d<half, access::write> outTexture  [[ texture(1) ]],
                          uint2                          gid         [[ thread_position_in_grid ]])
{
    if((gid.x < outTexture.get_width()) && (gid.y < outTexture.get_height()))
    {
        half4 inColor  = inTexture.read(gid);
        half  gray     = dot(inColor.rgb, half3(0.5, 0.5, 0.5));
        half4 outColor = half4(gray, gray, gray, 1.0);

        outTexture.write(outColor, gid);
    }
}
