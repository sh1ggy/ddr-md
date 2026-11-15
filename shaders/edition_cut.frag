// The tier's foil cut: ten facet patterns, shifted with the light and faded
// away from it. Drawn with BlendMode.overlay over the art.
#version 460 core
#include <flutter/runtime_effect.glsl>

uniform vec2 uSize;
uniform vec2 uLight; // 0–1 across the card
uniform float uTier; // 1–10
uniform float uPower;

out vec4 fragColor;

const float PI = 3.14159265;

vec4 W(float a) { return vec4(a, a, a, a); }
vec4 B(float a) { return vec4(0, 0, 0, a); }

// This pixel inside its tile, the tiles sized [size] of the card and shifted
// with the light as a background positioned at it.
vec2 tile(vec2 p, vec2 size, out vec2 box) {
  box = size * uSize;
  vec2 offset = (uSize - box) * uLight;
  return mod(p - offset, box);
}

// Degrees clockwise from the top, from [from], about [at] of the box.
float conic(vec2 t, vec2 box, vec2 at, float from) {
  vec2 d = t - at * box;
  float a = degrees(atan(d.x, -d.y));
  return mod(a - from, 360.0);
}

// Pixels along a linear gradient at [angle] degrees across the box, and
// that as a fraction of the gradient's length.
float along(vec2 t, vec2 box, float angle) {
  float r = radians(angle);
  vec2 dir = vec2(sin(r), -cos(r));
  float len = abs(box.x * dir.x) + abs(box.y * dir.y);
  return dot(t - box * .5, dir) + len * .5;
}
float linear(vec2 t, vec2 box, float angle) {
  float r = radians(angle);
  return along(t, box, angle) /
      (abs(box.x * sin(r)) + abs(box.y * cos(r)));
}

// Four colours evenly round a circle, the first again at 360.
vec4 quarters(float a, vec4 c0, vec4 c1, vec4 c2, vec4 c3) {
  float q = a / 90.0;
  if (q < 1.0) return mix(c0, c1, q);
  if (q < 2.0) return mix(c1, c2, q - 1.0);
  if (q < 3.0) return mix(c2, c3, q - 2.0);
  return mix(c3, c0, q - 3.0);
}

vec4 screen(vec4 s, vec4 d) { return s + d - s * d; }

vec4 cut(vec2 p) {
  vec2 box;
  int tier = int(uTier + .5);
  float px = uSize.x / 490.0;
  if (tier == 1) {
    vec2 t = tile(p, vec2(1.7), box);
    float f = linear(t, box, 120.0);
    if (f < .15 || f > .85) return vec4(0);
    if (f < .46) return mix(vec4(0), W(.4), (f - .15) / .31);
    if (f < .52) return mix(W(.4), B(.267), (f - .46) / .06);
    return mix(B(.267), vec4(0), (f - .52) / .33);
  }
  if (tier == 2) {
    vec2 t = tile(p, vec2(1.8), box);
    float f = fract(linear(t, box, 125.0) / .5) * .5;
    if (f < .25) return vec4(0);
    return f < .42 ? W(.6) : B(.333);
  }
  if (tier == 3) {
    vec2 t = tile(p, vec2(1.2), box);
    float a = conic(t, box, vec2(.3, .6), 25.0);
    if (a < 55.0) return W(.6);
    if (a < 120.0) return B(.4);
    if (a < 180.0) return W(.267);
    if (a < 260.0) return B(.2);
    if (a < 300.0) return W(.733);
    return B(.333);
  }
  if (tier == 4) {
    vec2 t = tile(p, vec2(.85), box);
    return quarters(conic(t, box, vec2(.5), 45.0), W(.667), B(.4), W(.133),
        B(.533));
  }
  if (tier == 5) {
    vec2 t = tile(p, vec2(.64, .75), box);
    float a = mod(conic(t, box, vec2(.4, .6), 30.0), 180.0);
    return a < 60.0 ? W(.667) : a < 120.0 ? B(.4) : W(.133);
  }
  if (tier == 6) {
    vec2 t = tile(p, vec2(.49), box);
    vec4 facets = quarters(conic(t, box, vec2(.5), 45.0), W(.6), B(.467),
        W(.2), B(.467));
    float f = mod(along(p, uSize, 125.0), 13.0 * px);
    return screen(facets, f < 12.0 * px ? vec4(0) : W(.502));
  }
  if (tier == 7) {
    vec2 t = tile(p, vec2(.4, .53), box);
    float a = mod(conic(t, box, vec2(.25, .7), 15.0), 120.0);
    return a < 25.0 ? W(.6) : a < 65.0 ? B(.467) : a < 100.0 ? W(.2) : B(.267);
  }
  if (tier == 8) {
    vec2 t = tile(p, vec2(.27), box);
    float a = conic(t, box, vec2(.5), 0.0);
    return a < 90.0 ? W(.733) : a < 180.0 ? B(.467) : a < 270.0 ? W(.333)
        : B(.267);
  }
  if (tier == 9) {
    vec2 t = tile(p, vec2(.23), box);
    return mod(conic(t, box, vec2(.5), 45.0), 90.0) < 45.0 ? W(.667) : B(.467);
  }
  vec2 t = tile(p, vec2(.13), box);
  vec4 facets = quarters(conic(t, box, vec2(.5), 45.0), W(.733), B(.467),
      W(.267), B(.533));
  float f = mod(along(p, uSize, 115.0), 4.0 * px);
  return screen(facets, f < .5 * px ? W(.6) : vec4(0));
}

void main() {
  vec2 p = FlutterFragCoord().xy;
  // Brightest at the light, gone by the far corners.
  vec2 c = uLight * uSize;
  vec2 r = sqrt(2.0) * max(c, uSize - c);
  float d = length((p - c) / r);
  float mask = d < .08 ? 1.0
      : d < .48 ? mix(1.0, .733, (d - .08) / .4)
      : d < .92 ? mix(.733, 0.0, (d - .48) / .44)
      : 0.0;
  fragColor = cut(p) * mask * uPower;
}
