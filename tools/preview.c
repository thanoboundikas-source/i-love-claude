/*
    Offscreen preview renderer. Draws fullscreen fragment shaders with
    Apple's OpenGL 4.1 driver and writes the RGBA8 result to a raw file.
    Driven by tools/preview.py, which builds test shaders from the pack's own
    lib/ code (sky, clouds, lighting, tonemap) so looks can be judged without
    launching Minecraft.

    Usage: preview FRAG.glsl WIDTH HEIGHT OUT.raw UNIFORMS.txt [POST.glsl [HDRFORMAT]]

    One pass (5 arguments, unchanged): FRAG draws straight into an RGBA8
    target, which is written to OUT.raw.

    Two passes (POST.glsl given), the game's HDR chain:
      1. FRAG writes linear HDR colour into a WIDTH x HEIGHT float texture
         (HDRFORMAT: rgba16f [default] or r11g11b10f), then glGenerateMipmap,
         the way Iris prepares a buffer declared colortexNMipmapEnabled
         (LINEAR_MIPMAP_LINEAR / LINEAR, clamp to edge).
      2. POST (normally the pack's real final.fsh) runs with that texture on
         its "colortex2" sampler and writes the RGBA8 result. FRAG's
         location 1 output (an R8 target, cleared to 1) is bound as
         "depthtex0": 1 = sky, less = geometry (final's sky mask).
    The uniform file is applied to both programs (names a program does not
    use are ignored); textures are loaded once and stay bound for both.

    UNIFORMS.txt lines:
      f  name v            float
      i  name v            int
      i2 name a b          ivec2
      v2 name x y          vec2 (also v3, v4)
      m4 name a0 .. a15    mat4, column-major
      t  name unit w h raw [linear]   RGBA8 texture from a raw file

    Draws are split into horizontal bands (scissor + glFinish) so a heavy
    preview shader at game resolution never trips the GPU watchdog.
*/
#include <OpenGL/OpenGL.h>
#include <OpenGL/gl3.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define MAX_LINES 1024
#define MAX_UNITS 32
#define HDR_UNIT 15
#define DEPTH_UNIT 14
#define BAND_ROWS 128

static char *readFile(const char *path, long *len) {
    FILE *f = fopen(path, "rb");
    if (!f) return NULL;
    fseek(f, 0, SEEK_END);
    long n = ftell(f);
    fseek(f, 0, SEEK_SET);
    char *buf = malloc(n + 1);
    fread(buf, 1, n, f);
    buf[n] = 0;
    fclose(f);
    if (len) *len = n;
    return buf;
}

static GLuint compile(GLenum type, const char *src, const char *what) {
    GLuint s = glCreateShader(type);
    glShaderSource(s, 1, &src, NULL);
    glCompileShader(s);
    GLint ok; glGetShaderiv(s, GL_COMPILE_STATUS, &ok);
    char log[16384]; glGetShaderInfoLog(s, sizeof log, NULL, log);
    if (!ok) { fprintf(stderr, "compile failed (%s):\n%s\n", what, log); exit(1); }
    return s;
}

static const char *VS =
    "#version 330 core\n"
    "out vec2 texcoord;\n"
    "void main(){ vec2 p = vec2((gl_VertexID & 1) * 2.0 - 1.0, (gl_VertexID >> 1) * 2.0 - 1.0);\n"
    "  texcoord = p * 0.5 + 0.5; gl_Position = vec4(p, 0.0, 1.0); }\n";

static GLuint buildProgram(const char *fragPath) {
    char *fsrc = readFile(fragPath, NULL);
    if (!fsrc) { fprintf(stderr, "cannot read %s\n", fragPath); exit(2); }
    GLuint prog = glCreateProgram();
    glAttachShader(prog, compile(GL_VERTEX_SHADER, VS, "vertex"));
    glAttachShader(prog, compile(GL_FRAGMENT_SHADER, fsrc, fragPath));
    glLinkProgram(prog);
    GLint ok; glGetProgramiv(prog, GL_LINK_STATUS, &ok);
    if (!ok) {
        char log[8192]; glGetProgramInfoLog(prog, sizeof log, NULL, log);
        fprintf(stderr, "link failed (%s):\n%s\n", fragPath, log);
        exit(1);
    }
    free(fsrc);
    return prog;
}

static char *uLines[MAX_LINES];
static int uCount = 0;
static GLuint texByUnit[MAX_UNITS];

// Sets every uniform in the file on the current program. Textures are
// uploaded the first time they are seen and only re-pointed afterwards.
static void applyUniforms(GLuint prog) {
    for (int li = 0; li < uCount; li++) {
        const char *line = uLines[li];
        char kind[8], name[128];
        if (sscanf(line, "%7s %127s", kind, name) != 2) continue;
        GLint loc = glGetUniformLocation(prog, name);
        const char *rest = line; int skip = 2;
        while (skip && *rest) { while (*rest && *rest != ' ') rest++; while (*rest == ' ') rest++; skip--; }
        if (!strcmp(kind, "f")) { float v; sscanf(rest, "%f", &v); glUniform1f(loc, v); }
        else if (!strcmp(kind, "i")) { int v; sscanf(rest, "%d", &v); glUniform1i(loc, v); }
        else if (!strcmp(kind, "i2")) { int a, b; sscanf(rest, "%d %d", &a, &b); glUniform2i(loc, a, b); }
        else if (!strcmp(kind, "v2")) { float a, b; sscanf(rest, "%f %f", &a, &b); glUniform2f(loc, a, b); }
        else if (!strcmp(kind, "v3")) { float a, b, c; sscanf(rest, "%f %f %f", &a, &b, &c); glUniform3f(loc, a, b, c); }
        else if (!strcmp(kind, "v4")) { float a, b, c, d; sscanf(rest, "%f %f %f %f", &a, &b, &c, &d); glUniform4f(loc, a, b, c, d); }
        else if (!strcmp(kind, "m4")) {
            float m[16]; char *p = (char *)rest;
            for (int k = 0; k < 16; k++) m[k] = strtof(p, &p);
            glUniformMatrix4fv(loc, 1, GL_FALSE, m);
        } else if (!strcmp(kind, "t")) {
            int unit, tw, th; char path[2048], filt[32] = "";
            sscanf(rest, "%d %d %d %2047s %31s", &unit, &tw, &th, path, filt);
            if (unit < 0 || unit >= MAX_UNITS || unit == HDR_UNIT || unit == DEPTH_UNIT) { fprintf(stderr, "bad texture unit %d for %s\n", unit, name); continue; }
            if (!texByUnit[unit]) {
                long n; char *data = readFile(path, &n);
                if (!data) { fprintf(stderr, "no texture %s\n", path); continue; }
                GLuint tex; glGenTextures(1, &tex);
                glActiveTexture(GL_TEXTURE0 + unit);
                glBindTexture(GL_TEXTURE_2D, tex);
                glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA8, tw, th, 0, GL_RGBA, GL_UNSIGNED_BYTE, data);
                GLint f = strcmp(filt, "linear") ? GL_NEAREST : GL_LINEAR;
                glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, f);
                glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, f);
                glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_REPEAT);
                glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_REPEAT);
                texByUnit[unit] = tex;
                free(data);
            }
            glUniform1i(loc, unit);
        }
    }
}

static void drawBanded(int W, int H) {
    glViewport(0, 0, W, H);
    glEnable(GL_SCISSOR_TEST);
    for (int y = 0; y < H; y += BAND_ROWS) {
        glScissor(0, y, W, (H - y) < BAND_ROWS ? (H - y) : BAND_ROWS);
        glDrawArrays(GL_TRIANGLE_STRIP, 0, 4);
        glFinish();
    }
    glDisable(GL_SCISSOR_TEST);
}

static void checkFbo(const char *what) {
    GLenum st = glCheckFramebufferStatus(GL_FRAMEBUFFER);
    if (st != GL_FRAMEBUFFER_COMPLETE) { fprintf(stderr, "%s framebuffer incomplete: 0x%x\n", what, st); exit(2); }
}

int main(int argc, char **argv) {
    if (argc < 6) { fprintf(stderr, "usage: preview FRAG W H OUT.raw UNIFORMS [POST [rgba16f|r11g11b10f]]\n"); return 2; }
    int W = atoi(argv[2]), H = atoi(argv[3]);
    const char *postPath = argc > 6 ? argv[6] : NULL;
    const char *hdrFmt = argc > 7 ? argv[7] : "rgba16f";
    CGLPixelFormatAttribute attrs[] = { kCGLPFAOpenGLProfile, (CGLPixelFormatAttribute)kCGLOGLPVersion_GL4_Core, kCGLPFAAccelerated, 0 };
    CGLPixelFormatObj pf; GLint npf;
    if (CGLChoosePixelFormat(attrs, &pf, &npf) || !pf) { fprintf(stderr, "no pixel format\n"); return 2; }
    CGLContextObj ctx; CGLCreateContext(pf, NULL, &ctx); CGLSetCurrentContext(ctx);

    GLuint prog = buildProgram(argv[1]);
    GLuint post = postPath ? buildProgram(postPath) : 0;

    FILE *uf = fopen(argv[5], "r");
    char line[4096];
    while (uf && uCount < MAX_LINES && fgets(line, sizeof line, uf)) uLines[uCount++] = strdup(line);
    if (uf) fclose(uf);

    GLuint vao; glGenVertexArrays(1, &vao); glBindVertexArray(vao);

    // Final RGBA8 target (read back into OUT.raw).
    GLuint outFbo, rb;
    glGenFramebuffers(1, &outFbo); glBindFramebuffer(GL_FRAMEBUFFER, outFbo);
    glGenRenderbuffers(1, &rb); glBindRenderbuffer(GL_RENDERBUFFER, rb);
    glRenderbufferStorage(GL_RENDERBUFFER, GL_RGBA8, W, H);
    glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_RENDERBUFFER, rb);
    checkFbo("output");

    if (!post) {
        glUseProgram(prog);
        applyUniforms(prog);
        drawBanded(W, H);
    } else {
        // Pass 1: scene -> HDR texture.
        GLenum internal = GL_RGBA16F;
        if (!strcmp(hdrFmt, "r11g11b10f")) internal = GL_R11F_G11F_B10F;
        else if (strcmp(hdrFmt, "rgba16f")) { fprintf(stderr, "unknown HDR format %s\n", hdrFmt); return 2; }
        GLuint hdr; glGenTextures(1, &hdr);
        glActiveTexture(GL_TEXTURE0 + HDR_UNIT);
        glBindTexture(GL_TEXTURE_2D, hdr);
        glTexImage2D(GL_TEXTURE_2D, 0, internal, W, H, 0, GL_RGBA, GL_FLOAT, NULL);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
        glBindTexture(GL_TEXTURE_2D, 0);   // not bound while it is the render target

        // depthtex0 stand-in written by FRAG's location 1 (1 = sky, <1 = geometry).
        GLuint depth; glGenTextures(1, &depth);
        glActiveTexture(GL_TEXTURE0 + DEPTH_UNIT);
        glBindTexture(GL_TEXTURE_2D, depth);
        glTexImage2D(GL_TEXTURE_2D, 0, GL_R8, W, H, 0, GL_RED, GL_UNSIGNED_BYTE, NULL);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
        glBindTexture(GL_TEXTURE_2D, 0);

        GLuint hdrFbo; glGenFramebuffers(1, &hdrFbo); glBindFramebuffer(GL_FRAMEBUFFER, hdrFbo);
        glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, hdr, 0);
        glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT1, GL_TEXTURE_2D, depth, 0);
        GLenum bufs[2] = { GL_COLOR_ATTACHMENT0, GL_COLOR_ATTACHMENT1 };
        glDrawBuffers(2, bufs);
        checkFbo("HDR");
        GLfloat one[4] = { 1.0f, 1.0f, 1.0f, 1.0f };
        glClearBufferfv(GL_COLOR, 1, one);
        glUseProgram(prog);
        applyUniforms(prog);
        drawBanded(W, H);
        glActiveTexture(GL_TEXTURE0 + DEPTH_UNIT);
        glBindTexture(GL_TEXTURE_2D, depth);

        // Mip chain for bloom, as Iris does before a program that asks for it.
        glActiveTexture(GL_TEXTURE0 + HDR_UNIT);
        glBindTexture(GL_TEXTURE_2D, hdr);
        glGenerateMipmap(GL_TEXTURE_2D);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR_MIPMAP_LINEAR);

        // Pass 2: post (final.fsh) -> RGBA8.
        glBindFramebuffer(GL_FRAMEBUFFER, outFbo);
        glUseProgram(post);
        applyUniforms(post);
        glUniform1i(glGetUniformLocation(post, "colortex2"), HDR_UNIT);
        glUniform1i(glGetUniformLocation(post, "depthtex0"), DEPTH_UNIT);
        drawBanded(W, H);
    }

    unsigned char *px = malloc((size_t)W * H * 4);
    glReadPixels(0, 0, W, H, GL_RGBA, GL_UNSIGNED_BYTE, px);
    FILE *o = fopen(argv[4], "wb"); fwrite(px, 1, (size_t)W * H * 4, o); fclose(o);
    GLenum err = glGetError();
    if (err) fprintf(stderr, "GL error 0x%x\n", err);
    return 0;
}
