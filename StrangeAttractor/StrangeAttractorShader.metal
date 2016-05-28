//
//  StrangeAttractorShader.metal
//  StrangeAttractor
//
//  Created by Simon Gladman on 27/05/2016.
//  Copyright © 2016 Simon Gladman. All rights reserved.
//

#include <metal_stdlib>
using namespace metal;


kernel void strangeAttractorKernel(texture2d<float, access::write> outTexture [[texture(0)]],
                                   const device float3 *inPoints [[ buffer(0) ]],
                                   device float3 *outPoints [[ buffer(1) ]],
                                   constant float &angle [[ buffer(2) ]],
                                   uint id [[thread_position_in_grid]])
{
    const float3 previousPoint = inPoints[id - 1];
    float3 thisPoint = inPoints[id];
    
    if(id != 0 &&
       previousPoint.x != -1 && previousPoint.y != -1 && previousPoint.z != -1 &&
       thisPoint.x == -1 && thisPoint.y == -1 && thisPoint.y == -1)
    {
        float x = previousPoint.x;
        float y = previousPoint.y;
        float z = previousPoint.z;
        
        float sigma = 10.0;
        float beta = 8.0 / 3.0;
        float rho = 28.0;
        float divisor = 300.0;
        
        float stepx = sigma * (y - x);
        float stepy = x * (rho - z) - y;
        float stepz = x * y - beta * z;
        
        thisPoint.x = previousPoint.x + stepx / divisor;
        thisPoint.y = previousPoint.y + stepy / divisor;
        thisPoint.z = previousPoint.z + stepz / divisor;
    }
    else if (thisPoint.x == -1 && thisPoint.y == -1 && thisPoint.y == -1)
    {
        return;
    }

    float xpos = (thisPoint.x * sin(angle) + thisPoint.z * cos(angle)) * 20.0;
    
    outTexture.write(float4(1.0), uint2(640 + xpos, 640 + thisPoint.y * 20.0));

    outPoints[id] = thisPoint;
}