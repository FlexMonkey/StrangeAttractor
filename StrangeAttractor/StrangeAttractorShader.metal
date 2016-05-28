//
//  StrangeAttractorShader.metal
//  StrangeAttractor
//
//  Created by Simon Gladman on 27/05/2016.
//  Copyright © 2016 Simon Gladman. All rights reserved.
//
//  Thanks to https://www.behance.net/gallery/mathrules-strange-attractors/7618879 

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
    
    int width = int(targetTexture.get_width());
    int height = int(targetTexture.get_height());
    
    while (true)
    {
        if (x > 0 && y > 0 && x < width && y < height)
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
                                   constant float &scale [[ buffer(5) ]],
                                   constant uint &attractorTypeIndex [[ buffer(6) ]],
                                   uint id [[thread_position_in_grid]])
{
    float3 thisPoint = inPoints[id];
    
    if (id == pointIndex)
    {
        float divisor = 300.0;
        float3 previousPoint = inPoints[id - 1];
        float3 delta;

        if (attractorTypeIndex == 1)
        {
            // Chen Lee
            delta = {
                5 * previousPoint.x -  previousPoint.y * previousPoint.z,
                -10.0 * previousPoint.y + previousPoint.x * previousPoint.z,
                -0.38 * previousPoint.z + previousPoint.x * (previousPoint.y / 3.0)
            };
        }
        else if (attractorTypeIndex == 2)
        {
            // Halvorsen
            float a = 1.4;
            delta = {
                -a * previousPoint.x - 4 * previousPoint.y - 4 * previousPoint.z - previousPoint.y * previousPoint.y,
                -a * previousPoint.y - 4 * previousPoint.z - 4 * previousPoint.x - previousPoint.z * previousPoint.z,
                -a * previousPoint.z - 4 * previousPoint.x - 4 * previousPoint.y - previousPoint.x * previousPoint.x
            };
        }
        else if (attractorTypeIndex == 3)
        {
            // Lü Chen
            float alpha = -10.0;
            float beta = -4.0;
            float zeta = 18.1;
            delta = {
                -((alpha * beta * previousPoint.x) / (alpha + beta)) - previousPoint.y * previousPoint.z + zeta,
                alpha * previousPoint.y + previousPoint.x * previousPoint.z,
                beta * previousPoint.z + previousPoint.x * previousPoint.y
            };
        }
        else if (attractorTypeIndex == 4)
        {
            // Hadley
            float alpha = 0.2;
            float beta = 4.0;
            float zeta = 8;
            float d = 1.0;
            delta = {
               -previousPoint.y * previousPoint.y - previousPoint.z * previousPoint.z - alpha * previousPoint.x + alpha * zeta,
                previousPoint.x * previousPoint.y - beta * previousPoint.x * previousPoint.z - previousPoint.y * d,
                beta * previousPoint.x * previousPoint.y + previousPoint.x * previousPoint.z - previousPoint.z
            };
        }
        else if (attractorTypeIndex == 5)
        {
            // Rössler
            float alpha = 0.2;
            float beta = 0.2;
            float sigma = 5.7;
            delta = {
                -(previousPoint.y + previousPoint.z),
                previousPoint.x + alpha * previousPoint.y,
                beta + previousPoint.z * (previousPoint.x - sigma)
            };
        }
        else
        {
            // Lorenz (defalt)
            float sigma = 10.0;
            float beta = 8.0 / 3.0;
            float rho = 28.0;

            delta = {
                sigma * (previousPoint.y - previousPoint.x),
                previousPoint.x * (rho - previousPoint.z) - previousPoint.y,
                previousPoint.x * previousPoint.y - beta * previousPoint.z
            };
        }
        
        
        thisPoint = previousPoint + delta / divisor;
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