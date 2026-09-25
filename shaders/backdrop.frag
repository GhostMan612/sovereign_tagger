#include <flutter/runtime_effect.glsl>

precision mediump float;

uniform vec2 uSize;
uniform float uTime;
uniform vec4 uAccent;
uniform float uVariant;
uniform float uIntensity;

out vec4 fragColor;

float hash(vec2 p) {
  return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
  vec2 i = floor(p);
  vec2 f = fract(p);
  vec2 u = f * f * (3.0 - 2.0 * f);
  return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

float gridLine(float v, float width) {
  float f = abs(fract(v + 0.5) - 0.5);
  return 1.0 - smoothstep(width * 0.5, width, f);
}

void main() {
  vec2 frag = FlutterFragCoord().xy;
  vec2 uv = frag / uSize;
  float aspect = uSize.x / max(uSize.y, 1.0);
  vec3 accent = uAccent.rgb;
  float v = uVariant;

  vec2 np = vec2(uv.x * aspect, uv.y);
  float n = noise(np * 2.6 + vec2(uTime * 0.035, -uTime * 0.025)) * 0.65 + noise(np * 6.0 - vec2(uTime * 0.05, uTime * 0.04)) * 0.35;
  vec3 col = accent * smoothstep(0.42, 1.0, n) * 0.20;

  float horizon = 0.64;
  col += accent * smoothstep(0.09, 0.0, abs(uv.y - horizon)) * 0.10;
  if (uv.y > horizon) {
    float d = (uv.y - horizon) / (1.0 - horizon);
    float z = 1.0 / max(d, 0.015);
    float gx = (uv.x - 0.5) * aspect * z * 3.2;
    float gz = z * 2.2 + uTime * 0.8;
    float wx = clamp(z * 3.2 * aspect / uSize.x * 1.6, 0.002, 0.5);
    float wz = clamp(z * z * 2.2 / ((1.0 - horizon) * uSize.y) * 1.6, 0.002, 0.5);
    float grid = max(gridLine(gx, wx), gridLine(gz, wz));
    float fog = smoothstep(0.0, 0.45, d);
    col += accent * grid * fog * 0.5;
  }

  if (abs(v) < 0.5) {
    float column = floor(uv.x * 48.0);
    float speed = 0.15 + hash(vec2(column, 1.0)) * 0.35;
    float drop = fract(uv.y * 1.5 - uTime * speed + hash(vec2(column, 7.0)));
    float lit = smoothstep(0.9, 1.0, drop) * step(0.72, hash(vec2(column, 3.0)));
    col += accent * lit * 0.35;
  }

  if (abs(v - 1.0) < 0.5) {
    vec2 ep = vec2(uv.x * aspect * 18.0, uv.y * 18.0 + uTime * 1.2);
    vec2 cell = floor(ep);
    float h = hash(cell);
    vec2 offset = vec2(hash(cell + 3.1), hash(cell + 7.7)) - 0.5;
    float dist = length(fract(ep) - 0.5 - offset * 0.6);
    float spark = smoothstep(0.09, 0.0, dist) * step(0.8, h);
    float flicker = 0.6 + 0.4 * sin(uTime * 6.0 + h * 40.0);
    col += mix(accent, vec3(1.0, 0.55, 0.2), 0.6) * spark * flicker * smoothstep(0.05, 0.9, uv.y) * 0.9;
  }

  if (abs(v - 2.0) < 0.5) {
    float band = smoothstep(0.985, 1.0, sin(uv.y * 40.0 - uTime * 1.6) * 0.5 + 0.5);
    col += accent * band * 0.18;
  }

  if (abs(v - 3.0) < 0.5) {
    float wave = sin(uv.x * aspect * 9.0 + uTime * 1.3) * 0.05 + sin(uv.x * aspect * 23.0 - uTime * 2.1) * 0.02;
    float line = smoothstep(0.006, 0.0, abs(uv.y - 0.35 - wave));
    col += accent * line * 0.45;
  }

  float scan = 0.88 + 0.12 * sin(frag.y * 1.4 + uTime * 3.0);
  float vignette = smoothstep(1.15, 0.25, length((uv - 0.5) * vec2(aspect * 0.8, 1.0)));
  col *= scan * vignette * uIntensity;
  fragColor = vec4(col, 1.0);
}
