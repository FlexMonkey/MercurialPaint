//
//  Shaders.metal
//  MercurialPaint
//
//  Created by Simon Gladman on 04/12/2015.
//  Copyright © 2015 Simon Gladman. All rights reserved.
//

#include <metal_stdlib>
using namespace metal;

float rand(int x, int y, int z);

// Generate a random float in the range [0.0f, 1.0f] using x, y, and z (based on the xor128 algorithm)
float rand(int x, int y, int z)
{
    int seed = x + y * 57 + z * 241;
    seed= (seed<< 13) ^ seed;
    return (( 1.0 - ( (seed * (seed * seed * 15731 + 789221) + 1376312589) & 2147483647) / 1073741824.0f) + 1.0f) / 2.0f;
}

// mercurialPaintShader

kernel void mercurialPaintShader(texture2d<float, access::write> outTexture [[texture(0)]],
                                 const device int *inParticles [[ buffer(0) ]],
                                 
                                 constant int &xPosition [[ buffer(1) ]],
                                 constant int &yPosition [[ buffer(2) ]],
                                 
                                 uint id [[thread_position_in_grid]])
{
    if (xPosition < 0 || yPosition < 0)
    {
        return;
    }
    
    const int randomSeed = inParticles[id];
    
    const float randomAngle = rand(randomSeed, xPosition, yPosition) * 6.283185;
    
    const float randomRadius = rand(randomSeed, yPosition, xPosition) * 40;
    
    const int writeAtX = xPosition + int(sin(randomAngle) * randomRadius);
    const int writeAtY = yPosition + int(cos(randomAngle) * randomRadius);
    
    outTexture.write(float4(1, 1, 1, 1), uint2(writeAtX, writeAtY));
}