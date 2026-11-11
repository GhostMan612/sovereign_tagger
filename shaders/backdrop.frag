#include <flutter/runtime_effect.glsl>

precision highp float;

uniform vec2 uSize;
uniform float uTime;
uniform vec4 uAccent;
uniform float uVariant;
uniform float uIntensity;

out vec4 fragColor;

float hash(vec2 p) {
  vec3 p3 = fract(vec3(p.xyx) * 0.1031);
  p3 += dot(p3, p3.yzx + 33.33);
  return fract((p3.x + p3.y) * p3.z);
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
  vec2 uv = frag / max(uSize, vec2(1.0));
  float aspect = uSize.x / max(uSize.y, 1.0);
  vec3 accent = uAccent.rgb;
  float v = uVariant;

  vec2 np = vec2(uv.x * aspect, uv.y);
  float n = noise(np * 3.1 + vec2(uTime * 0.032, -uTime * 0.024));
  vec3 col = accent * smoothstep(0.42, 0.98, n) * 0.14;

  float horizon = 0.68;
  col += accent * smoothstep(0.08, 0.0, abs(uv.y - horizon)) * 0.08;
  if (uv.y > horizon) {
    float d = (uv.y - horizon) / (1.0 - horizon);
    float z = 1.0 / max(d, 0.015);
    float gx = (uv.x - 0.5) * aspect * z * 3.2;
    float gz = z * 2.2 + uTime * 0.75;
    float wx = clamp(z * 3.2 * aspect / max(uSize.x, 1.0) * 1.5, 0.002, 0.5);
    float wz = clamp(z * z * 2.2 / max((1.0 - horizon) * uSize.y, 1.0) * 1.5, 0.002, 0.5);
    float grid = max(gridLine(gx, wx), gridLine(gz, wz));
    float fog = smoothstep(0.0, 0.45, d);
    col += accent * grid * fog * 0.34;
  }

  if (abs(v) < 0.5) {
    float column = floor(uv.x * 46.0);
    float speed = 0.16 + hash(vec2(column, 1.0)) * 0.36;
    float drop = fract(uv.y * 1.4 - uTime * speed + hash(vec2(column, 7.0)));
    float activeCol = step(0.70, hash(vec2(column, 3.0)));
    float tail = smoothstep(0.78, 1.0, drop) * activeCol;
    float tip = smoothstep(0.975, 1.0, drop) * activeCol;
    col += accent * tail * 0.32 + vec3(1.0) * tip * 0.22;
  }

  if (abs(v - 1.0) < 0.5) {
    vec2 ep = vec2(uv.x * aspect * 18.0 + sin(uv.y * 5.0 + uTime * 0.8) * 0.35, uv.y * 18.0 + uTime * 1.25);
    vec2 cell = floor(ep);
    float h = hash(cell);
    vec2 offset = vec2(hash(cell + 3.1), hash(cell + 7.7)) - 0.5;
    float dist = length(fract(ep) - 0.5 - offset * 0.6);
    float spark = smoothstep(0.095, 0.0, dist) * step(0.78, h);
    float flicker = 0.6 + 0.4 * sin(uTime * 6.0 + h * 40.0);
    col += mix(accent, vec3(1.0, 0.62, 0.25), 0.45) * spark * flicker * smoothstep(0.05, 0.92, uv.y) * 0.85;
  }

  if (abs(v - 2.0) < 0.5) {
    float band = smoothstep(0.985, 1.0, sin(uv.y * 36.0 - uTime * 1.8) * 0.5 + 0.5);
    float row = floor(uv.y * 26.0);
    float packet = fract(uv.x * 1.2 - uTime * (0.25 + hash(vec2(row, 5.0)) * 0.45) + hash(vec2(row, 9.0)));
    float streak = smoothstep(0.88, 1.0, packet) * step(0.76, hash(vec2(row, 2.0)));
    col += accent * (band * 0.16 + streak * 0.26);
  }

  if (abs(v - 3.0) < 0.5) {
    float w1 = sin(uv.x * aspect * 8.5 + uTime * 1.4) * 0.048 + sin(uv.x * aspect * 21.0 - uTime * 2.2) * 0.018;
    float w2 = cos(uv.x * aspect * 6.0 - uTime * 1.05) * 0.036 + sin(uv.x * aspect * 15.0 + uTime * 1.7) * 0.014;
    float l1 = smoothstep(0.007, 0.0, abs(uv.y - 0.36 - w1));
    float l2 = smoothstep(0.005, 0.0, abs(uv.y - 0.38 - w2));
    col += accent * (l1 * 0.42 + l2 * 0.22);
  }

  if (abs(v - 4.0) < 0.5) {
    vec2 center = vec2(0.5, 0.38);
    vec2 p = (uv - center) * vec2(aspect, 1.0);
    float r = length(p);
    float ring1 = smoothstep(0.006, 0.0, abs(r - (0.20 + 0.012 * sin(uTime * 0.9))));
    float ring2 = smoothstep(0.004, 0.0, abs(r - (0.31 - 0.010 * cos(uTime * 0.7))));
    vec2 mp = vec2(uv.x * aspect * 14.0, uv.y * 14.0 + uTime * 0.35);
    vec2 mc = floor(mp);
    float mh = hash(mc);
    float mote = smoothstep(0.08, 0.0, length(fract(mp) - 0.5)) * step(0.84, mh);
    col += accent * (ring1 * 0.30 + ring2 * 0.18 + mote * 0.40);
  }

  if (v > 4.5) {
    vec2 center = vec2(0.5, 0.44);
    vec2 p = (uv - center) * vec2(aspect, 1.0);
    float r = length(p);
    float waveRing = smoothstep(0.94, 1.0, sin(r * 34.0 - uTime * 2.0) * 0.5 + 0.5) * smoothstep(0.58, 0.06, r);
    col += accent * waveRing * 0.24;
  }

  float scan = 0.90 + 0.10 * sin(frag.y * 1.4 + uTime * 2.6);
  float vignette = smoothstep(1.22, 0.22, length((uv - 0.5) * vec2(aspect * 0.82, 1.0)));
  col *= scan * vignette * uIntensity;
  fragColor = vec4(col, 1.0);
}
