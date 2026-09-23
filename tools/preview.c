/*
    Offscreen preview renderer. Draws one fullscreen fragment shader with
    Apple's OpenGL 4.1 driver and writes the RGBA8 result to a raw file.
    Driven by tools/preview.py, which builds test shaders from the pack's own
    lib/ code (sky, clouds, lighting, tonemap) so looks can be judged without
    launching Minecraft.

    Usage: preview FRAG.glsl WIDTH HEIGHT OUT.raw UNIFORMS.txt
    UNIFORMS.txt lines:
      f  name v            float
      i  name v            int
      v2 name x y          vec2 (also v3, v4)
      m4 name a0 .. a15    mat4, column-major
      t  name unit w h raw [linear]   RGBA8 texture from a raw file
*/
#include <OpenGL/OpenGL.h>
#include <OpenGL/gl3.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

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

static GLuint compile(GLenum type, const char *src) {
    GLuint s = glCreateShader(type);
    glShaderSource(s, 1, &src, NULL);
    glCompileShader(s);
    GLint ok; glGetShaderiv(s, GL_COMPILE_STATUS, &ok);
    char log[16384]; glGetShaderInfoLog(s, sizeof log, NULL, log);
    if (!ok) { fprintf(stderr, "compile failed:\n%s\n", log); exit(1); }
    return s;
}

static const char *VS =
    "#version 330 core\n"
    "out vec2 texcoord;\n"
    "void main(){ vec2 p = vec2((gl_VertexID & 1) * 2.0 - 1.0, (gl_VertexID >> 1) * 2.0 - 1.0);\n"
    "  texcoord = p * 0.5 + 0.5; gl_Position = vec4(p, 0.0, 1.0); }\n";

int main(int argc, char **argv) {
    if (argc < 6) { fprintf(stderr, "usage: preview FRAG W H OUT.raw UNIFORMS\n"); return 2; }
    int W = atoi(argv[2]), H = atoi(argv[3]);
    CGLPixelFormatAttribute attrs[] = { kCGLPFAOpenGLProfile, (CGLPixelFormatAttribute)kCGLOGLPVersion_GL4_Core, kCGLPFAAccelerated, 0 };
    CGLPixelFormatObj pf; GLint npf;
    if (CGLChoosePixelFormat(attrs, &pf, &npf) || !pf) { fprintf(stderr, "no pixel format\n"); return 2; }
    CGLContextObj ctx; CGLCreateContext(pf, NULL, &ctx); CGLSetCurrentContext(ctx);

    char *fsrc = readFile(argv[1], NULL);
    if (!fsrc) { fprintf(stderr, "cannot read %s\n", argv[1]); return 2; }
    GLuint prog = glCreateProgram();
    glAttachShader(prog, compile(GL_VERTEX_SHADER, VS));
    glAttachShader(prog, compile(GL_FRAGMENT_SHADER, fsrc));
    glLinkProgram(prog);
    GLint ok; glGetProgramiv(prog, GL_LINK_STATUS, &ok);
    if (!ok) { char log[8192]; glGetProgramInfoLog(prog, sizeof log, NULL, log); fprintf(stderr, "link failed:\n%s\n", log); return 1; }
    glUseProgram(prog);

    FILE *uf = fopen(argv[5], "r");
    char line[4096];
    while (uf && fgets(line, sizeof line, uf)) {
        char kind[8], name[128];
        if (sscanf(line, "%7s %127s", kind, name) != 2) continue;
        GLint loc = glGetUniformLocation(prog, name);
        char *rest = line; int skip = 2;
        while (skip && *rest) { while (*rest && *rest != ' ') rest++; while (*rest == ' ') rest++; skip--; }
        if (!strcmp(kind, "f")) { float v; sscanf(rest, "%f", &v); glUniform1f(loc, v); }
        else if (!strcmp(kind, "i")) { int v; sscanf(rest, "%d", &v); glUniform1i(loc, v); }
        else if (!strcmp(kind, "v2")) { float a, b; sscanf(rest, "%f %f", &a, &b); glUniform2f(loc, a, b); }
        else if (!strcmp(kind, "v3")) { float a, b, c; sscanf(rest, "%f %f %f", &a, &b, &c); glUniform3f(loc, a, b, c); }
        else if (!strcmp(kind, "v4")) { float a, b, c, d; sscanf(rest, "%f %f %f %f", &a, &b, &c, &d); glUniform4f(loc, a, b, c, d); }
        else if (!strcmp(kind, "m4")) {
            float m[16]; char *p = rest;
            for (int k = 0; k < 16; k++) m[k] = strtof(p, &p);
            glUniformMatrix4fv(loc, 1, GL_FALSE, m);
        } else if (!strcmp(kind, "t")) {
            int unit, tw, th; char path[2048], filt[32] = "";
            sscanf(rest, "%d %d %d %2047s %31s", &unit, &tw, &th, path, filt);
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
            glUniform1i(loc, unit);
            free(data);
        }
    }
    if (uf) fclose(uf);

    GLuint fbo, rb;
    glGenFramebuffers(1, &fbo); glBindFramebuffer(GL_FRAMEBUFFER, fbo);
    glGenRenderbuffers(1, &rb); glBindRenderbuffer(GL_RENDERBUFFER, rb);
    glRenderbufferStorage(GL_RENDERBUFFER, GL_RGBA8, W, H);
    glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_RENDERBUFFER, rb);
    GLuint vao; glGenVertexArrays(1, &vao); glBindVertexArray(vao);
    glViewport(0, 0, W, H);
    glDrawArrays(GL_TRIANGLE_STRIP, 0, 4);
    unsigned char *px = malloc((size_t)W * H * 4);
    glReadPixels(0, 0, W, H, GL_RGBA, GL_UNSIGNED_BYTE, px);
    FILE *o = fopen(argv[4], "wb"); fwrite(px, 1, (size_t)W * H * 4, o); fclose(o);
    GLenum err = glGetError();
    if (err) fprintf(stderr, "GL error 0x%x\n", err);
    return 0;
}
