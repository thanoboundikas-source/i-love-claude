/*
    Buffer formats and clearing. Iris reads these directives from the
    shader source (docs: Constants > buffer_format / buffer_clear). Formats
    must sit in a block comment, one per line. Included by deferred1 and
    final, which always run. Layout is documented in CLAUDE.md.

const int colortex0Format = RGBA8;
const int colortex1Format = RGBA16;
const int colortex2Format = R11F_G11F_B10F;
const int colortex3Format = RGBA16F;
const int colortex4Format = RGBA16F;
const int colortex5Format = RGBA16F;
const int colortex6Format = RGBA8;
const int shadowcolor0Format = RGBA8;
*/

// colortex2 (scene) is fully rewritten by deferred1 every frame, colortex3/4
// by their passes; colortex5 is the TAA history and must persist.
const bool colortex2Clear = false;
const bool colortex3Clear = false;
const bool colortex4Clear = false;
const bool colortex5Clear = false;
const vec4 colortex0ClearColor = vec4(0.0, 0.0, 0.0, 0.0);
const vec4 colortex1ClearColor = vec4(0.0, 0.0, 0.0, 0.0);
const vec4 colortex6ClearColor = vec4(0.0, 0.0, 0.0, 0.0);
