/*
    Shared uniforms (matrices, time, weather, camera). Samplers are NOT here —
    each program declares only the samplers it actually reads, so Iris never
    sees stray shadow/colortex references it would act on.
*/

uniform float viewWidth;
uniform float viewHeight;
uniform float near;
uniform float far;

uniform int frameCounter;
uniform float frameTimeCounter;
uniform int worldTime;
uniform int worldDay;
uniform int moonPhase;
uniform float sunAngle;

uniform vec3 sunPosition;
uniform vec3 moonPosition;
uniform vec3 shadowLightPosition;
uniform vec3 upPosition;

uniform float rainStrength;
uniform float wetness;
uniform float thunderStrength;
uniform int isEyeInWater;
uniform ivec2 eyeBrightnessSmooth;
uniform float nightVision;
uniform float blindness;
uniform float darknessFactor;
uniform float eyeAltitude;
uniform float cloudHeight;

uniform vec3 cameraPosition;
uniform vec3 previousCameraPosition;

uniform mat4 gbufferModelView;
uniform mat4 gbufferModelViewInverse;
uniform mat4 gbufferProjection;
uniform mat4 gbufferProjectionInverse;
uniform mat4 gbufferPreviousModelView;
uniform mat4 gbufferPreviousProjection;
uniform mat4 shadowModelView;
uniform mat4 shadowModelViewInverse;
uniform mat4 shadowProjection;
uniform mat4 shadowProjectionInverse;

uniform vec3 fogColor;
uniform vec3 skyColor;
