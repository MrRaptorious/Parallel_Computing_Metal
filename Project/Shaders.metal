#include <metal_stdlib>
#include "definitions.h"

using namespace metal;

// Settings to configure simulation
constant float moveSpeed = 2;
constant float turnSpeed = 1.0;
constant float sensorAngleDegrees = 50.0;
constant float sensorOffsetDst = 25.0;
constant int sensorSize = 3;
constant float senseWeight = 0.5;
constant float randomSteerStrength = 1.0;
constant float diffuseRate = .5;
constant float decayRate = 0.01;


// calculate the likeliness of traveling into the given direction
float sense(Agent agent, float sensorAngleOffset,texture2d<float, access::read_write> color_buffer) {
    int width = color_buffer.get_width();
    int height = color_buffer.get_height();
    float sensorAngle = agent.angle + sensorAngleOffset;
    float2 sensorDir = float2(cos(sensorAngle), sin(sensorAngle));
    
    float2 sensorPos = agent.position + sensorDir * sensorOffsetDst;
    int sensorCentreX = (int) sensorPos.x;
    int sensorCentreY = (int) sensorPos.y;
    
    float sum = 0;
    
    for (int offsetX = -sensorSize; offsetX <= sensorSize; offsetX ++) {
        for (int offsetY = -sensorSize; offsetY <= sensorSize; offsetY ++) {
            int sampleX = min(width - 1, max(0, sensorCentreX + offsetX));
            int sampleY = min(height - 1, max(0, sensorCentreY + offsetY));
            sum += dot(senseWeight, color_buffer.read(uint2(sampleX,sampleY)));
        }
    }
    
    return sum;
}

// function to create "randomness"
uint hash(uint state)
{
    state ^= 2747636409u;
    state *= 2654435769u;
    state ^= state >> 16;
    state *= 2654435769u;
    state ^= state >> 16;
    state *= 2654445769u;
    return state;
    
}

// scale to 0 1
float scaleToRange01(uint state)
{
    return state / 4294967295.0;
}

// compute shader to draw
kernel void updateTexture(texture2d<float, access::read_write> color_buffer [[texture(0)]],
                      device Agent *agents [[buffer(0)]],
                      uint2 grid_index [[thread_position_in_grid]])
{
    //    const int numAgents = NUMAGENTS;
    int width = color_buffer.get_width();
    int height = color_buffer.get_height();
    float4 originalCol = color_buffer.read(grid_index);
    
    // diffuse
    uint2 id = grid_index;
    
    if (id.x < 0 || id.x >= (uint)width || id.y < 0 || id.y >= (uint)height) {
        return;
    }
    
    float4 sum = 0;
    // 3x3 blur
    for (float offsetX = -1; offsetX <= 1; offsetX ++) {
        for (float offsetY = -1.0; offsetY <= 1; offsetY ++) {
            int sampleX = min(width-1.0, max(0.0, id.x + offsetX));
            int sampleY = min(height-1.0, max(0.0, id.y + offsetY));
            sum += color_buffer.read(uint2(sampleX,sampleY));
        }
    }

    float4 blurredCol = sum / 9;
    float diffuseWeight = saturate(diffuseRate);
    blurredCol = originalCol * (1 - diffuseWeight) + blurredCol * (diffuseWeight);
    
    color_buffer.write(max(0.0, blurredCol - decayRate), grid_index);
}

// compute shader to update each agent
kernel void updateAgent(texture2d<float, access::read_write> color_buffer [[texture(0)]],
                   device Agent *agents [[buffer(0)]],
                   device Agent *res [[buffer(1)]],
                   uint2 grid_index [[thread_position_in_grid]])
{
    uint2 id = grid_index;
    uint numAgents = NUMAGENTS;
    int width = color_buffer.get_width();
    int height = color_buffer.get_height();
    
    if (id.x >= numAgents)
    { return;}
    
    Agent agent = agents[id.x];
    
    // go in direction of sensory data
    float sensorAngleRad = sensorAngleDegrees * (3.1415 / 180);
    float weightForward = sense(agent, 0.0, color_buffer);
    float weightLeft = sense(agent, sensorAngleRad, color_buffer);
    float weightRight = sense(agent, -sensorAngleRad,color_buffer);
        
    // Continue in same direction
    if (weightForward > weightLeft && weightForward > weightRight) {
        agent.angle += 0;
    }
//    else if (weightForward < weightLeft && weightForward < weightRight) {
//        agent.angle += (randomSteerStrength - 0.5) * 2 * turnSpeed;
//    }
    // Turn right
    else if (weightRight > weightLeft) {
        agent.angle -= randomSteerStrength * turnSpeed;
    }
    // Turn left
    else if (weightLeft > weightRight) {
        agent.angle += randomSteerStrength * turnSpeed;
    }
    
    // Move agent based on direction and speed
    float2 direction = float2(cos(agent.angle), sin(agent.angle));
    float2 newPos = agent.position + direction * moveSpeed;
    
    // Clamp position to boundaries
    if ((newPos.x < 2 || newPos.x >= width-2) || (newPos.y < 2 || newPos.y >= height-2)) {
        uint random = hash(agent.position.y * width + agent.position.x + hash(id.x)) ;
        newPos.x = min(width-2.0, max(0.0, newPos.x)) ;
        newPos.y = min(height-2.0, max(0.0, newPos.y));
        
        float randomAngle = scaleToRange01(random) * (2 * 3.1415);
        
        agent.position = newPos;
        agent.angle = randomAngle;
    }
    else {
        agent.position = newPos;
    }
    
    res[id.x] = agent;
    
    // also draw agent
    int cellX = (int)agent.position.x;
    int cellY = (int)agent.position.y;
    
    
    float r = scaleToRange01(hash(grid_index.x+grid_index.y));
    float g = scaleToRange01(hash(grid_index.x+grid_index.y+10));
    float b = scaleToRange01(hash(grid_index.x+grid_index.y+100));
    float4 color = float4(r,g,b,1);

    
//    float4 color = float4(1.0, 1.0, 1.0, 1.0);

    color_buffer.write(color, uint2(cellX,cellY));
    
}
