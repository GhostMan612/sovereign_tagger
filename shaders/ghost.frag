#include <flutter/runtime_effect.glsl>

precision highp float;

uniform vec2 uSize;
uniform float uTime;
uniform vec4 uAccent;
uniform vec4 uEmotionCol;
uniform vec2 uGaze;
uniform float uPresence;
uniform float uBlink;
uniform float uMouth;
uniform float uListen;
uniform float uThink;
uniform float uGlitch;
uniform float uEmotionId;
uniform float uBeat;

out vec4 fragColor;

float hash21(vec2 p) {
  return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
}

float smin(float a, float b, float k) {
  float h = clamp(0.5 + 0.5 * (b - a) / max(k, 0.0001), 0.0, 1.0);
  return mix(b, a, h) - k * h * (1.0 - h);
}

float smax(float a, float b, float k) {
  return -smin(-a, -b, k);
}

float sdCapsule(vec3 p, vec3 a, vec3 b, float r) {
  vec3 pa = p - a;
  vec3 ba = b - a;
  float h = clamp(dot(pa, ba) / max(dot(ba, ba), 0.0001), 0.0, 1.0);
  return length(pa - ba * h) - r;
}

vec3 toGhostLocal(vec3 p) {
  float hover = sin(uTime * 2.2) * 0.055 + uBeat * 0.065;
  vec3 q = p - vec3(0.0, hover, 0.0);

  float twist = (1.0 - clamp(uPresence, 0.0, 1.0)) * 5.2 * q.y;
  float ct = cos(twist);
  float st = sin(twist);
  q.xz = mat2(ct, -st, st, ct) * q.xz;

  float roll = -uGaze.x * 0.12 - uListen * 0.16 + sin(uTime * 34.0) * 0.14 * uGlitch;
  float cr = cos(roll);
  float sr = sin(roll);
  q.xy = mat2(cr, -sr, sr, cr) * q.xy;

  float yaw = clamp(uGaze.x, -1.0, 1.0) * 0.48 + sin(uTime * 1.1) * 0.08;
  float cy = cos(yaw);
  float sy = sin(yaw);
  q = vec3(q.x * cy - q.z * sy, q.y, q.x * sy + q.z * cy);

  float pitch = clamp(uGaze.y, -1.0, 1.0) * 0.30;
  float cp = cos(pitch);
  float sp = sin(pitch);
  q = vec3(q.x, q.y * cp + q.z * sp, -q.y * sp + q.z * cp);

  float breathe = 1.0 + 0.028 * sin(uTime * 2.6) + 0.05 * uBeat;
  return q / max(breathe, 0.2);
}

float mapGhost(vec3 p) {
  vec3 q = toGhostLocal(p);

  float flare = smoothstep(0.22, -0.56, q.y);
  vec3 bodyP = q;
  bodyP.xz /= (1.0 + flare * 0.28);

  float core = sdCapsule(bodyP, vec3(0.0, -0.34, 0.0), vec3(0.0, 0.20, 0.0), 0.375);

  float safeZ = abs(q.z) < 0.0001 ? 0.0001 : q.z;
  float angle = atan(q.x, safeZ);
  float clothWave = sin(angle * 5.0 + uTime * 2.8 + q.y * 4.0) * 0.032 * flare;
  core += clothWave;

  float skirtWave = -0.49
      + 0.055 * sin(q.x * 9.5 + uTime * 4.6)
      + 0.045 * cos(q.z * 8.5 - uTime * 3.8);
  core = smax(core, skirtWave - q.y, 0.075);

  vec3 visorBox = (q - vec3(0.0, 0.165, 0.345)) / vec3(0.245, 0.135, 0.11);
  float visorCarve = (length(max(abs(visorBox) - vec3(0.55, 0.45, 0.35), 0.0)) - 0.38) * 0.14;
  core = smax(core, -visorCarve, 0.035);

  float talkBob = sin(uTime * 18.0) * 0.045 * uMouth;
  vec3 lHandCenter = vec3(
    -0.50 + 0.10 * uThink + 0.04 * uListen,
    -0.06 + sin(uTime * 2.9 + 1.1) * 0.045 + 0.12 * uListen + 0.08 * uThink + talkBob,
    0.19 + 0.08 * uThink
  );
  vec3 rHandCenter = vec3(
    0.50 - 0.10 * uThink,
    -0.06 + sin(uTime * 2.9 + 2.7) * 0.045 + 0.08 * uThink - talkBob,
    0.19 + 0.08 * uThink
  );
  float hands = min(length(q - lHandCenter) - 0.095, length(q - rHandCenter) - 0.095);

  return smin(core, hands, 0.08);
}

vec3 calcNormal(vec3 p) {
  vec2 e = vec2(0.0035, -0.0035);
  vec3 g = e.xyy * mapGhost(p + e.xyy) +
      e.yyx * mapGhost(p + e.yyx) +
      e.yxy * mapGhost(p + e.yxy) +
      e.xxx * mapGhost(p + e.xxx);
  return normalize(g + vec3(0.0, 0.0, 0.00001));
}

vec4 evalVisorFace(vec3 q, vec3 glowCol) {
  float frontMask = smoothstep(0.16, 0.28, q.z);
  vec2 vp = vec2(q.x / 0.26, (q.y - 0.165) / 0.145);
  float visorDist = length(max(abs(vp) - vec2(0.56, 0.44), 0.0)) - 0.42;
  float visorGlass = (1.0 - smoothstep(-0.04, 0.05, visorDist)) * frontMask;

  float happyW = 1.0 - smoothstep(0.35, 0.85, abs(uEmotionId - 1.0));
  float sarcW = 1.0 - smoothstep(0.35, 0.85, abs(uEmotionId - 2.0));
  float openEye = clamp(1.0 - uBlink, 0.07, 1.0) * (1.0 + 0.16 * uListen);

  float eyeGlow = 0.0;
  float glint = 0.0;
  for (int side = 0; side < 2; side++) {
    float sx = side == 0 ? -1.0 : 1.0;
    vec2 ec = vec2(sx * 0.118, 0.195);
    vec2 ep = q.xy - ec;

    float arcCurve = happyW * (-3.6 * ep.x * ep.x + 0.012);
    float browTilt = sarcW * (side == 0 ? (ep.x * 0.35 + 0.012) : (-ep.x * 0.22 - 0.004));
    vec2 defP = vec2(ep.x / 0.046, (ep.y - arcCurve - browTilt) / (0.060 * openEye));
    float dOval = length(defP) - 1.0;

    if (sarcW > 0.01 && side == 0) {
      dOval = max(dOval, (ep.y - 0.010) * 14.0 * sarcW - (1.0 - sarcW));
    }
    if (happyW > 0.25) {
      float archInner = length(vec2(ep.x / 0.038, (ep.y + 0.028 - arcCurve) / max(0.042 * openEye, 0.01))) - 1.0;
      dOval = mix(dOval, max(dOval, -archInner), happyW * 0.78);
    }

    float eMask = 1.0 - smoothstep(-0.18, 0.22, dOval);
    float eHalo = exp(-max(dOval, 0.0) * 2.8) * 0.55;
    eyeGlow += (eMask + eHalo) * frontMask;

    float gDist = length(ep - vec2(-0.014, 0.018 * openEye));
    glint += smoothstep(0.016, 0.003, gDist) * step(0.35, openEye) * (1.0 - happyW * 0.6) * frontMask;
  }

  vec2 mp = q.xy - vec2(0.0, 0.092);
  float smileCurve = mix(0.9, 3.2, happyW) * mp.x * mp.x - sarcW * mp.x * 0.28;
  float idleLine = abs(mp.y - smileCurve) - 0.0085;
  idleLine = max(idleLine, abs(mp.x) - 0.055);
  float idleMouth = (1.0 - smoothstep(0.0, 0.009, idleLine)) * (1.0 - smoothstep(0.05, 0.25, uMouth));

  float waveBar = 0.010 + (0.036 * uMouth) * (0.55 + 0.45 * cos(mp.x * 58.0 + uTime * 26.0)) * (1.0 - smoothstep(0.0, 0.085, abs(mp.x)));
  float talkDist = max(abs(mp.y) - waveBar, abs(mp.x) - 0.078);
  float talkMouth = (1.0 - smoothstep(0.0, 0.010, talkDist)) * smoothstep(0.03, 0.14, uMouth);
  float mouthEmit = (idleMouth + talkMouth * 1.25) * frontMask;

  float blush = 0.0;
  if (happyW > 0.05) {
    float bl = exp(-length((q.xy - vec2(-0.185, 0.115)) / vec2(0.045, 0.024)) * 2.2);
    float br = exp(-length((q.xy - vec2(0.185, 0.115)) / vec2(0.045, 0.024)) * 2.2);
    blush = (bl + br) * happyW * 0.55 * frontMask;
  }

  vec3 visorCol = vec3(0.02, 0.03, 0.05);
  vec3 emitCol = mix(glowCol, vec3(1.0), 0.42) * clamp(eyeGlow + mouthEmit, 0.0, 1.5)
      + vec3(1.0) * clamp(glint, 0.0, 1.0)
      + vec3(1.0, 0.36, 0.68) * blush;
  return vec4(visorCol + emitCol, visorGlass);
}

void main() {
  vec2 frag = FlutterFragCoord().xy;
  float minDim = max(min(uSize.x, uSize.y), 1.0);
  vec2 p2d = (frag - 0.5 * uSize) / (0.5 * minDim);
  vec2 uv = vec2(p2d.x, -p2d.y);

  float edgeFade = smoothstep(1.02, 0.78, length(uv));
  float pres = clamp(uPresence, 0.0, 1.2);
  vec4 outCol = vec4(0.0);
  if (edgeFade > 0.001 && pres > 0.001) {
    float sliceY = floor(uv.y * 18.0 + uTime * 22.0);
    float sliceShift = (hash21(vec2(sliceY, floor(uTime * 16.0))) - 0.5) * 0.16 * uGlitch;
    vec2 glitchUv = vec2(uv.x + sliceShift, uv.y);

    vec3 accent = uAccent.rgb;
    vec3 glowCol = mix(accent, uEmotionCol.rgb, clamp(uEmotionCol.a, 0.0, 1.0));
    vec3 ghostTint = mix(vec3(0.92, 0.96, 1.0), glowCol, 0.24);

    vec3 ro = vec3(0.0, 0.02, 2.35);
    vec3 rd = normalize(vec3(glitchUv.x, glitchUv.y, -1.88));

    float bSph = dot(ro, rd);
    float cSph = dot(ro, ro) - 0.9216;
    float discSph = bSph * bSph - cSph;
    float approxDist = max(sqrt(max(cSph - bSph * bSph, 0.0)) - 0.44, 0.0);

    float t = 1.15;
    float hit = 0.0;
    float minDist = approxDist;
    if (discSph > 0.0) {
      float sqSph = sqrt(discSph);
      t = max(1.15, -bSph - sqSph);
      float tMax = min(3.25, -bSph + sqSph);
      float marchMin = 10.0;
      for (int i = 0; i < 20; i++) {
        vec3 pos = ro + rd * t;
        float d = mapGhost(pos);
        marchMin = min(marchMin, d);
        float stepHit = step(d, 0.0035) * step(t, tMax);
        hit = max(hit, stepHit);
        float stopStep = max(hit, step(tMax, t));
        t += mix(max(d * 0.82, 0.012), 0.0, stopStep);
      }
      minDist = mix(approxDist, marchMin, smoothstep(0.0, 0.10, discSph));
    }

    vec3 bodyRgb = vec3(0.0);
    float bodyAlpha = 0.0;

    if (hit > 0.5) {
      vec3 hitPos = ro + rd * t;
      vec3 nrm = calcNormal(hitPos);
      vec3 q = toGhostLocal(hitPos);

      vec3 lightDir = normalize(vec3(-0.45, 0.75, 0.85));
      vec3 backLight = normalize(vec3(0.55, -0.35, -0.65));
      float diff = max(dot(nrm, lightDir), 0.0);
      float backDiff = max(dot(nrm, backLight), 0.0);
      float fresnel = pow(clamp(1.0 - dot(nrm, -rd), 0.0, 1.0), 2.35);

      float soulCore = exp(-length(q - vec3(0.0, 0.02, 0.05)) * 4.2) * (0.65 + 0.35 * sin(uTime * 4.0));
      float scanline = 0.90 + 0.10 * sin(frag.y * 1.8 - uTime * 7.0);
      float skirtFade = smoothstep(-0.56, -0.22, q.y);

      vec3 shellCol = ghostTint * (0.34 + 0.52 * diff)
          + glowCol * (fresnel * 1.35 + soulCore * 0.70 + backDiff * 0.28);
      shellCol *= scanline;

      vec4 visor = evalVisorFace(q, glowCol);
      float vMask = visor.a;
      float glassSpec = pow(clamp(dot(reflect(-lightDir, nrm), -rd), 0.0, 1.0), 18.0) * vMask;
      vec3 visorFinal = visor.rgb + vec3(0.55, 0.75, 1.0) * glassSpec * 0.45;

      bodyRgb = mix(shellCol, visorFinal, vMask * 0.94);

      if (uGlitch > 0.03) {
        float band = step(0.76, hash21(vec2(floor(q.y * 24.0), floor(uTime * 20.0))));
        bodyRgb = mix(bodyRgb, vec3(1.0, 0.18, 0.35), band * uGlitch * 0.55);
      }

      float matBeam = smoothstep(-0.65, 0.65, q.y + (pres * 1.5 - 0.75));
      bodyAlpha = mix(0.68 + 0.26 * fresnel, 0.96, vMask) * (0.45 + 0.55 * skirtFade) * clamp(pres, 0.0, 1.0) * matBeam;
    }

    float auraWeight = exp(-max(minDist, 0.0) * 7.5) * 0.52 * clamp(pres, 0.0, 1.0);
    vec3 auraRgb = glowCol;

    if (uGlitch > 0.04) {
      float chromaL = exp(-max(length(uv - vec2(-0.045 * uGlitch, 0.04)) - 0.36, 0.0) * 9.0) * uGlitch * 0.45;
      float chromaR = exp(-max(length(uv - vec2(0.045 * uGlitch, 0.04)) - 0.36, 0.0) * 9.0) * uGlitch * 0.45;
      auraRgb = mix(auraRgb, vec3(1.0, 0.2, 0.4), chromaL) + vec3(0.0, 0.9, 1.0) * chromaR;
      auraWeight = clamp(auraWeight + (chromaL + chromaR) * 0.5, 0.0, 0.85);
    }

    vec3 fxPremult = vec3(0.0);
    float fxAlpha = 0.0;

    if (uListen > 0.02) {
      float r = length(uv - vec2(0.0, 0.05));
      for (int k = 0; k < 2; k++) {
        float fk = float(k);
        float phase = fract(uTime * 0.85 + fk * 0.5);
        float ringR = 0.42 + phase * 0.44;
        float ring = smoothstep(0.026, 0.0, abs(r - ringR)) * (1.0 - phase) * uListen;
        fxPremult += mix(glowCol, vec3(1.0, 0.3, 0.4), 0.35) * ring * 0.65;
        fxAlpha += ring * 0.65;
      }
    }

    if (uThink > 0.02) {
      for (int k = 0; k < 4; k++) {
        float ang = uTime * 3.4 + float(k) * 1.5707963;
        vec3 orbWorld = vec3(cos(ang) * 0.56, 0.44 + sin(ang * 2.0) * 0.05, sin(ang) * 0.42);
        float orbT = length(orbWorld - ro);
        float occluded = (hit > 0.5 && t < orbT) ? 0.18 : 1.0;
        vec2 proj = vec2(orbWorld.x, orbWorld.y - 0.02) * (1.88 / max(2.35 - orbWorld.z, 0.5));
        float dOrb = length(glitchUv - proj);
        float spark = smoothstep(0.075, 0.010, dOrb) * uThink * occluded;
        fxPremult += mix(vec3(0.3, 1.0, 1.0), vec3(1.0), 0.45) * spark * 0.85;
        fxAlpha += spark * 0.85;
      }
    }

    float shadowPedestal = exp(-length((uv - vec2(0.0, -0.74)) / vec2(0.36, 0.065)) * 2.2) * 0.34 * clamp(pres, 0.0, 1.0);
    fxPremult += glowCol * shadowPedestal;
    fxAlpha += shadowPedestal;

    vec3 totalPremult = bodyRgb * bodyAlpha
        + auraRgb * auraWeight * (1.0 - bodyAlpha * 0.72)
        + fxPremult * (1.0 - bodyAlpha * 0.35);
    float totalAlpha = clamp(bodyAlpha + auraWeight * (1.0 - bodyAlpha) + fxAlpha * 0.75, 0.0, 1.0) * edgeFade;
    totalPremult = min(totalPremult * edgeFade, vec3(totalAlpha));
    outCol = vec4(totalPremult, totalAlpha);
  }
  fragColor = outCol;
}
