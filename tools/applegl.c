/*
    Compiles and links GLSL programs with Apple's own OpenGL 4.1 (Metal)
    driver in an offscreen context — the same compiler Minecraft uses on this
    Mac. Used by tools/check.py after glslang.

    Usage: applegl LISTFILE
      LISTFILE lines: "<name>\t<vertex path>\t<fragment path>"
    Prints one block per program that fails (or has warnings) and exits 1 if
    any program failed to compile or link.

    Build: clang -O1 -Wno-deprecated-declarations -framework OpenGL \
           tools/applegl.c -o tools/.applegl
*/
#include <OpenGL/OpenGL.h>
#include <OpenGL/gl3.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static char *readFile(const char *path) {
    FILE *f = fopen(path, "rb");
    if (!f) return NULL;
    fseek(f, 0, SEEK_END);
    long n = ftell(f);
    fseek(f, 0, SEEK_SET);
    char *buf = malloc(n + 1);
    fread(buf, 1, n, f);
    buf[n] = 0;
    fclose(f);
    return buf;
}

static int compile(GLenum type, const char *path, GLuint *out, char *log, int logSize) {
    char *src = readFile(path);
    if (!src) { snprintf(log, logSize, "cannot read %s", path); return 0; }
    GLuint s = glCreateShader(type);
    const char *srcs[1] = { src };
    glShaderSource(s, 1, srcs, NULL);
    glCompileShader(s);
    GLint ok = 0;
    glGetShaderiv(s, GL_COMPILE_STATUS, &ok);
    glGetShaderInfoLog(s, logSize, NULL, log);
    free(src);
    *out = s;
    return ok;
}

int main(int argc, char **argv) {
    if (argc < 2) { fprintf(stderr, "usage: applegl LISTFILE\n"); return 2; }
    CGLPixelFormatAttribute attrs[] = {
        kCGLPFAOpenGLProfile, (CGLPixelFormatAttribute)kCGLOGLPVersion_GL4_Core,
        kCGLPFAAccelerated, 0
    };
    CGLPixelFormatObj pf; GLint npf;
    if (CGLChoosePixelFormat(attrs, &pf, &npf) != kCGLNoError || !pf) { fprintf(stderr, "no GL 4.1 pixel format\n"); return 2; }
    CGLContextObj ctx;
    if (CGLCreateContext(pf, NULL, &ctx) != kCGLNoError) { fprintf(stderr, "no GL context\n"); return 2; }
    CGLSetCurrentContext(ctx);

    FILE *list = fopen(argv[1], "r");
    if (!list) { fprintf(stderr, "cannot open %s\n", argv[1]); return 2; }
    char line[8192];
    int failed = 0, total = 0;
    static char vlog[65536], flog[65536], llog[65536];
    while (fgets(line, sizeof line, list)) {
        char *name = strtok(line, "\t\n");
        char *vpath = strtok(NULL, "\t\n");
        char *fpath = strtok(NULL, "\t\n");
        if (!name || !vpath || !fpath) continue;
        total++;
        GLuint vs = 0, fs = 0;
        vlog[0] = flog[0] = llog[0] = 0;
        int vok = compile(GL_VERTEX_SHADER, vpath, &vs, vlog, sizeof vlog);
        int fok = compile(GL_FRAGMENT_SHADER, fpath, &fs, flog, sizeof flog);
        int lok = 0;
        if (vok && fok) {
            GLuint p = glCreateProgram();
            glAttachShader(p, vs);
            glAttachShader(p, fs);
            glLinkProgram(p);
            GLint ok = 0;
            glGetProgramiv(p, GL_LINK_STATUS, &ok);
            glGetProgramInfoLog(p, sizeof llog, NULL, llog);
            lok = ok;
            glDeleteProgram(p);
        }
        if (vs) glDeleteShader(vs);
        if (fs) glDeleteShader(fs);
        int ok = vok && fok && lok;
        if (!ok) failed++;
        if (!ok || vlog[0] || flog[0] || llog[0]) {
            printf("### %s %s\n", ok ? "WARN" : "FAIL", name);
            if (vlog[0]) printf("[vertex] %s\n", vlog);
            if (flog[0]) printf("[fragment] %s\n", flog);
            if (llog[0]) printf("[link] %s\n", llog);
        }
    }
    fclose(list);
    printf("### applegl: %d programs, %d failed (%s)\n", total, failed, glGetString(GL_VERSION));
    CGLSetCurrentContext(NULL);
    CGLDestroyContext(ctx);
    return failed ? 1 : 0;
}
