#include <flutter/runtime_effect.glsl>
uniform vec2 viewport;
uniform vec3 eye;
uniform vec3 forwardRay;
uniform vec3 rightRay;
uniform vec3 upRay;
uniform float tanHalfFov;
uniform vec4 bounds;
uniform vec3 baseColor;
uniform vec3 highlightColor;
uniform float opacity;
uniform float margin;
uniform float softness;
uniform float cloudScale;
uniform float contrast;
uniform float drift;
uniform float height;
uniform float elapsed;
uniform float reveal;
uniform vec4 focusRect;
uniform float hasFocus;
uniform sampler2D oldMask;
uniform sampler2D newMask;
uniform sampler2D noiseMap;
out vec4 fragColor;

vec4 filtered_old(vec2 uv) {
  vec2 pixel=uv*256.0-.5;
  vec2 cell=floor(pixel), f=fract(pixel);
  vec2 a=(cell+.5)/256.0;
  vec2 stepSize=vec2(1.0/256.0);
  return mix(mix(texture(oldMask,a),texture(oldMask,a+vec2(stepSize.x,0.0)),f.x),
             mix(texture(oldMask,a+vec2(0.0,stepSize.y)),texture(oldMask,a+stepSize),f.x),f.y);
}
vec4 filtered_new(vec2 uv) {
  vec2 pixel=uv*256.0-.5;
  vec2 cell=floor(pixel), f=fract(pixel);
  vec2 a=(cell+.5)/256.0;
  vec2 stepSize=vec2(1.0/256.0);
  return mix(mix(texture(newMask,a),texture(newMask,a+vec2(stepSize.x,0.0)),f.x),
             mix(texture(newMask,a+vec2(0.0,stepSize.y)),texture(newMask,a+stepSize),f.x),f.y);
}
vec4 filtered_noise(vec2 uv) {
  vec2 pixel=uv*128.0-.5;
  vec2 cell=floor(pixel), f=fract(pixel);
  vec2 a=(cell+.5)/128.0;
  vec2 stepSize=vec2(1.0/128.0);
  return mix(mix(texture(noiseMap,fract(a)),texture(noiseMap,fract(a+vec2(stepSize.x,0.0))),f.x),
             mix(texture(noiseMap,fract(a+vec2(0.0,stepSize.y))),texture(noiseMap,fract(a+stepSize)),f.x),f.y);
}
float distanceAt(vec2 p, bool previous) {
  vec2 uv=(p-bounds.xy)/bounds.zw;
  vec2 clamped=clamp(uv,vec2(.5/256.0),vec2(1.0-.5/256.0));
  float outside=length((uv-clamped)*bounds.zw);
  vec4 encoded=previous ? filtered_old(clamped) : filtered_new(clamped);
  return (encoded.r+encoded.g/255.0)*32.0+outside;
}
void main() {
  vec2 screen=FlutterFragCoord().xy/viewport;
  vec2 ndc=vec2(screen.x*2.0-1.0,1.0-screen.y*2.0);
  vec3 ray=forwardRay+rightRay*ndc.x*(viewport.x/viewport.y)*tanHalfFov+upRay*ndc.y*tanHalfFov;
  float denominator=min(ray.y,-0.0001);
  vec3 ground=eye+ray*(-eye.y/denominator);
  vec2 p=vec2(ground.x,-ground.z);
  float after=smoothstep(margin,margin+softness,distanceAt(p,false));
  float before=reveal>=1.0 ? after : smoothstep(margin,margin+softness,distanceAt(p,true));
  float fog=mix(before,after,reveal);
  if(ray.y>=0.0) fog=1.0;
  if(hasFocus>0.5) {
    vec2 outside=max(max(focusRect.xy-p,p-focusRect.zw),vec2(0.0));
    fog=min(fog,smoothstep(0.0,.3,length(outside)));
  }
  vec3 upper=eye+ray*((height-eye.y)/denominator);
  vec2 q=vec2(upper.x,-upper.z);
  vec2 wind=vec2(elapsed*drift,elapsed*drift*.37);
  float n=filtered_noise(fract((p+wind)/(cloudScale*8.0))).r;
  float m=filtered_noise(fract((q-wind*.63)/(cloudScale*4.3)+.31)).g;
  float cloud=clamp(.5+(n+m-1.0)*contrast*2.0,0.0,1.0);
  // Noise changes tint, never leaks opaque hidden terrain or covers clear land.
  float alpha=fog*opacity;
  vec3 color=mix(baseColor,highlightColor,cloud);
  fragColor=vec4(color*alpha,alpha);
}
