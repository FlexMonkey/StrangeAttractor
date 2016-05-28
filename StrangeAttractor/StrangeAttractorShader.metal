//
//  StrangeAttractorShader.metal
//  StrangeAttractor
//
//  Created by Simon Gladman on 27/05/2016.
//  Copyright © 2016 Simon Gladman. All rights reserved.
//

#include <metal_stdlib>
using namespace metal;

void drawLine(texture2d<float, access::write> targetTexture, uint2 start, uint2 end, float3 color);

void drawLine(texture2d<float, access::write> targetTexture, uint2 start, uint2 end, float3 color)
{
    int x = int(start.x);
    int y = int(start.y);
    
    int dx = abs(x - int(end.x));
    int dy = abs(y - int(end.y));
    
    int sx = start.x < end.x ? 1 : -1;
    int sy = start.y < end.y ? 1 : -1;
    
    int err = (dx > dy ? dx : -dy) / 2;
    
    while (true)
    {
        if (x > 0 && y > 0)
        {
            targetTexture.write(float4(color, 1.0), uint2(x, y));
        }
        
        if (x == int(end.x) && y == int(end.y))
        {
            break;
        }
        
        int e2 = err;
        
        if (e2 > -dx)
        {
            err -= dy;
            x += sx;
        }
        
        if (e2 < dy)
        {
            err += dx;
            y += sy;
        }
    }
}

kernel void strangeAttractorKernel(texture2d<float, access::write> outTexture [[texture(0)]],
                                   const device float3 *inPoints [[ buffer(0) ]],
                                   device float3 *outPoints [[ buffer(1) ]],
                                   constant float &angle [[ buffer(2) ]],
                                   constant uint &pointIndex [[ buffer(3) ]],
                                   constant uint &center [[ buffer(4) ]],
                                   uint id [[thread_position_in_grid]])
{
    float scale = 20.0;
    float3 thisPoint = inPoints[id];
    
    if(id == pointIndex)
    {
        const float3 previousPoint = inPoints[id - 1];
        
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
    else if (id < 1 || id > pointIndex)
    {
        return;
    }

    float startX = (inPoints[id - 1].x * sin(angle) + inPoints[id - 1].z * cos(angle)) * scale;
    uint2 startPoint = uint2(center + startX, center + inPoints[id - 1].y * scale);
    
    float endX = (thisPoint.x * sin(angle) + thisPoint.z * cos(angle)) * scale;
    uint2 endPoint = uint2(center + endX, center + thisPoint.y * scale);
    
    drawLine(outTexture, startPoint, endPoint, float3(1.0));
    
    outPoints[id] = thisPoint;
}