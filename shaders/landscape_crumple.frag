#version 460 core
#include <flutter/runtime_effect.glsl>

// Used only while baking the terrain atlas, never in the camera paint path.
uniform vec2 uWorldOrigin;
uniform float uScale;
uniform float uStrength;
uniform float uShadow;
uniform vec3 uPaper;
uniform float uDensity;
uniform float uDistribution;
uniform sampler2D uFoldMap;
out vec4 fragColor;

float hash(vec2 p) {
  vec3 q = fract(vec3(p.xyx) * 0.1031);
  q += dot(q, q.yzx + 33.33);
  return fract((q.x + q.y) * q.z);
}

float noise(vec2 p) {
  vec2 cell = floor(p), f = fract(p);
  f = f * f * (3.0 - 2.0 * f);
  return mix(mix(hash(cell), hash(cell + vec2(1, 0)), f.x),
             mix(hash(cell + vec2(0, 1)), hash(cell + vec2(1, 1)), f.x), f.y);
}

void main() {
  vec2 world = FlutterFragCoord().xy + uWorldOrigin;
  vec2 uv = fract(world / (4.0 * uScale));
  // World-locked coverage, independent of fold scale and camera. Evaluated only
  // when baking atlas slots. The extremes are exactly smooth / fully folded.
  vec2 p = world * (uDistribution < 0.5 ? 0.7 : 2.4) + vec2(17.3, -9.8);
  float field = 0.75 * noise(p) + 0.25 * noise(p * 2.03 + 4.7);
  float threshold = mix(1.12, -0.12, uDensity);
  float coverage = smoothstep(threshold - 0.12, threshold + 0.12, field);
  float strength = uStrength * coverage;
  vec3 fold = texture(uFoldMap, uv).rgb;
  vec2 slope = (fold.rg * 255.0 - 128.0) / 85.0 * strength;
  vec3 normal = normalize(vec3(-slope, 1.0));
  vec3 light = normalize(vec3(-0.45, -0.55, 0.85));
  float diffuse = max(0.0, dot(normal, light));
  // Normalize against flat paper so overall scene lighting is applied once.
  float shade = (0.40 + 0.60 * diffuse) / (0.40 + 0.60 * light.z);
  float cavity = fold.b * 0.5 * 0.23 * uShadow * strength;
  fragColor = vec4(clamp(uPaper * shade * max(0.0, 1.0-cavity), 0.0, 1.0), 1.0);
}
