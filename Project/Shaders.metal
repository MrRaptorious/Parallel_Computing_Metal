#include <metal_stdlib>
#include "definitions.h"

using namespace metal;

// Einstellungen um den Shader anzupassen

// Geschwindigkeit mit der sich die Agenten bewegen in Pixel pro frame
constant float moveSpeed = 2;

// variable um die drehgeschwindigkeit festzulegen
// gross = schnell die Richtung aendern
// klein = langsam die Richtung aendern
constant float turnSpeed = 1.0;

// Winkel in dem die Sensoren des Agenten angebracht sind
// 0 = alle 3 sensoren Zeigen nach vorne
// 90 = einer zeigt nach vorne, die zwei anderen zeigen 90 grad nach links / rechts
constant float sensorAngleDegrees = 50.0;

constant float sensorOffsetDst = 50.0;

// der Bereich den die Sensoren abdecken
// 3 = 3x3 = 9 pixel
// beeinflusst die Performance stark!
constant int sensorSize = 3;

// Gewicht um etwas zufall in die Wahl der Richtung zu bringen, um "Erkunden/Ausbreiten" zu simulieren
constant float randomSteerStrength = .4;

// Gewicht um "Blur" zu steuern, damit ein Pfad nicht nur 1px breit ist, sondern sich wie ein "Duft" verhaelt
constant float diffuseRate = .3;

// wird jeden frame von jedem pixel auf der Textur abgezogen, damit Pfade nicht für immer bleiben
// 0 = Pfade werden nicht geloescht
constant float decayRate = 0.006;


// Herz des Algorithmus, bestimmt für einen agenten
float sense(Agent agent, float sensorAngleOffset,texture2d<float, access::read_write> color_buffer) {
    int width = color_buffer.get_width();
    int height = color_buffer.get_height();
    float sensorAngle = agent.angle + sensorAngleOffset;
    float2 sensorDir = float2(cos(sensorAngle), sin(sensorAngle));
    
    float2 sensorPos = agent.position + sensorDir * sensorOffsetDst;
    int sensorCentreX = (int) sensorPos.x;
    int sensorCentreY = (int) sensorPos.y;
    
    float sum = 0;
    
    float4 sumcolor = float4(0,0,0,0);
    
    for (int offsetX = -sensorSize; offsetX <= sensorSize; offsetX ++) {
        for (int offsetY = -sensorSize; offsetY <= sensorSize; offsetY ++) {
            int sampleX = min(width - 1, max(0, sensorCentreX + offsetX));
            int sampleY = min(height - 1, max(0, sensorCentreY + offsetY));
            sumcolor += color_buffer.read(uint2(sampleX,sampleY));
        }
    }
    
    sumcolor = sumcolor * float4(agent.color,1);
    
    // Unterscheidung zwischen den einzelnen Sorten
    // falls man die gleiche sorte sieht dann mit 0.4 in die richtung, ansonsten mit 0
    if (agent.color.x > 0.8) {  // wenn es die roten sind
        if (sumcolor.x > 0.8)
            sum = 1;
    }
    else                        // wenn es die blauen sind
    {
        if (sumcolor.y > 0.8)
            sum = 0.4;
    }

    float r = agent.color.x - sumcolor.x;
    float g = agent.color.y - sumcolor.y;
    float b = agent.color.z - sumcolor.z;
    
    float c = sqrt(r*r + g*g + b*b);


    return (1 / (1 + c));
}

// Hash funktion um "Zufallswerte" zu generieren
// aus Stackoverflow
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

// Gehört zum hash dazu, damit es als zufallszahl von 0..1 genutz werden kann
float scaleToRange01(uint state)
{
    return state / 4294967295.0;
}

// Funktion um die Textur zu updaten, wird für jeden pixel seperat aufgerufen
kernel void updateTexture(texture2d<float, access::read_write> color_buffer [[texture(0)]],
                      device Agent *agents [[buffer(0)]],
                      uint2 grid_index [[thread_position_in_grid]])
{
    int width = color_buffer.get_width();
    int height = color_buffer.get_height();
    float4 originalCol = color_buffer.read(grid_index);
    
    uint2 id = grid_index;
    
    // sicherstellen, dass Zugriffe innerhalb der Textur statfinden
    // kein out of bounds
    if (id.x < 0 || id.x >= (uint)width || id.y < 0 || id.y >= (uint)height) {
        return;
    }
    
    // Blur ueber eine 3x3 bereich
    // blur ist nur ein Durchschnitt
    float4 sum = 0;
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
    
    // Farbe des Pixels anpassen, mit der gewichtung durch decayRate
    color_buffer.write(max(0.0, blurredCol - decayRate), grid_index);
}

// Funktion wie ein Compute-Shader
// wird fuer jeden Agenten einzelnd aufgerufen
// updated agent und Zeichnet neue farbe des Agenten auf die Textur
// liegen 2 Agenten auf der gleichen stelle ist nicht sichergestellt das beide ihre farbe auf die Textur schreiben können
// der der als letztes auf die Textur schreibt hat "gewonnen"
kernel void updateAgent(texture2d<float, access::read_write> color_buffer [[texture(0)]],
                   device Agent *agents [[buffer(0)]],
                   device Agent *res [[buffer(1)]],
                   uint2 grid_index [[thread_position_in_grid]])
{
    
// ##### Schritt 1 Agenten Updaten ######
    uint2 id = grid_index;
    uint numAgents = NUMAGENTS;
    int width = color_buffer.get_width();
    int height = color_buffer.get_height();
    
    // wie in Cuda mit der Thread id bestimmen welcher Teil der Daten verarbeitet werden soll
    if (id.x >= numAgents)
    { return;}
    Agent agent = agents[id.x];
    
    // Gewichtungen fuer jeden sensor (links, mitte, rechts) mit der "sense" Funktion berechnen
    float sensorAngleRad = sensorAngleDegrees * (3.1415 / 180);
    float weightForward = sense(agent, 0.0, color_buffer);
    float weightLeft = sense(agent, sensorAngleRad, color_buffer);
    float weightRight = sense(agent, -sensorAngleRad,color_buffer);
        
    // Wenn Gewicht zur mitte am groessten, fortfahren wie gewohnt, keine aenderung am winkel
    if (weightForward > weightLeft && weightForward > weightRight) {
        agent.angle += 0;
    }
    //  Nach Rechts
    else if (weightRight > weightLeft) {
        agent.angle -= randomSteerStrength * turnSpeed;
    }
    // Nach Links
    else if (weightLeft > weightRight) {
        agent.angle += randomSteerStrength * turnSpeed;
    }
    
    // Agenten in Richtung seines neuen Winkels und dessen Bewegungsgeschwindigkeit bewegen (geschwindigkeit ist fuer alle geilch (moveSpeed))
    float2 direction = float2(cos(agent.angle), sin(agent.angle));
    float2 newPos = agent.position + direction * moveSpeed;
    
    // Sicherstellen, dass ein Agent immer innerhalb der Textur bleibt
    // ein Abprallen an der Wand wird simuliert, indem ein zufälliger neuer Winkel generiert wird wenn
    // sich der Agent an der Wand befindet
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
    
    // geupdateten Agenten im Puffer fuer Ergebnis abspeichern, sodas die CPU diese informationen erhalten kann
    res[id.x] = agent;
    
// ##### Schritt 2 Agenten auf der Textur Vermerken / Zeichnen ######
    
    // Position berechnen
    int cellX = (int)agent.position.x;
    int cellY = (int)agent.position.y;
    
    // zufällige farbe anhand der position des Agenten
    float r = scaleToRange01(hash(grid_index.x+grid_index.y));
    float g = scaleToRange01(hash(grid_index.x+grid_index.y+10));
    float b = scaleToRange01(hash(grid_index.x+grid_index.y+100));

    
    // Farbe des Agenten als neue auf der Textur nutzen
    // Agent hat RGB Farbe, Textur erwartet aber RGBA
    float4 color = float4(agent.color, 1.0);

    // Farbe schlussendlich auf Textur bringen
    color_buffer.write(color, uint2(cellX,cellY));
}
