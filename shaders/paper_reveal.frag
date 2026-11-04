#include <flutter/runtime_effect.glsl>
uniform vec2 size;
uniform float progress;
uniform float shade;
uniform sampler2D paper;
uniform sampler2D distanceMask;
out vec4 fragColor;
void main() {
  vec2 uv = FlutterFragCoord().xy / size;
  vec4 color = texture(paper, uv);
  float distance = texture(distanceMask, uv).r;
  float fill = min(progress / .75, 1.01);
  float visible = 1.0 - smoothstep(fill - .012, fill, distance);
  if (progress >= .75) visible = 1.0;
  float settle = smoothstep(.75, 1.0, progress);
  vec3 ink = mix(vec3(color.a), color.rgb, settle) * shade;
  fragColor = vec4(ink, color.a) * visible;
}
