#!/usr/bin/env python3
"""
Solstice offline shader checker.

Mimics what Iris does before handing code to the driver closely enough to catch
typos: expands #include (absolute = from shaders/, relative = from the file),
injects the Iris standard macros after #version, applies an option
configuration by rewriting lib/settings.glsl, then runs glslangValidator on
every program (vertex + fragment linked together).

It also lints for things that would break on macOS GL 4.1 or silently in Iris:
forbidden GL 4.2+ features, iris_ identifiers, unknown option names in
#ifdef, profiles / screens / lang entries that point at options that do not
exist.

This is a typo catcher, not proof. The game log is the real test.
"""
import hashlib
import itertools
import os
import re
import subprocess
import sys
import tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SHADERS = os.path.join(ROOT, "shaders")
SETTINGS_REL = "lib/settings.glsl"
GLSLANG = "glslangValidator"

# Iris standard macros (StandardMacros.java, Iris 26.1 branch) with values that
# match this Mac. Render stages follow WorldRenderingPhase ordinal order.
RENDER_STAGES = ["NONE", "SKY", "SUNSET", "CUSTOM_SKY", "SUN", "MOON", "STARS", "VOID",
                 "TERRAIN_SOLID", "TERRAIN_CUTOUT_MIPPED", "TERRAIN_CUTOUT", "ENTITIES",
                 "BLOCK_ENTITIES", "DESTROY", "OUTLINE", "DEBUG", "HAND_SOLID",
                 "TERRAIN_TRANSLUCENT", "TRIPWIRE", "PARTICLES", "CLOUDS", "RAIN_SNOW",
                 "WORLD_BORDER", "HAND_TRANSLUCENT"]
IRIS_MACROS = [
    ("MC_VERSION", "260102"), ("MC_MIPMAP_LEVEL", "4"), ("IRIS_VERSION", "11104"),
    ("MC_GL_VERSION", "410"), ("MC_GLSL_VERSION", "410"), ("MC_OS_MAC", ""),
    ("MC_GL_VENDOR_APPLE", ""), ("MC_GL_RENDERER_APPLE", ""), ("IS_IRIS", ""),
    ("IRIS_REQUIRES_SEPARATE_ENTITY_DRAWS", ""), ("MAX_COLOR_BUFFERS", "16"),
    ("IRIS_HAS_TRANSLUCENCY_SORTING", ""), ("IRIS_TAG_SUPPORT", "2"),
    ("MC_NORMAL_MAP", ""), ("MC_SPECULAR_MAP", ""), ("MC_RENDER_QUALITY", "1.0"),
    ("MC_SHADOW_QUALITY", "1.0"), ("MC_HAND_DEPTH", "0.125"),
] + [("MC_RENDER_STAGE_" + s, str(i)) for i, s in enumerate(RENDER_STAGES)]

STAGES = {".vsh": "vert", ".fsh": "frag"}
FORBIDDEN_FILES = (".csh", ".gsh", ".tcs", ".tes")
FORBIDDEN_TOKENS = [
    (r"\bimage(Load|Store|Atomic\w*)\b", "image load/store (GL 4.2)"),
    (r"\b[iu]?image[123]D\w*\b", "image uniforms (GL 4.2)"),
    (r"\blayout\s*\(\s*std430", "SSBO layout (GL 4.3)"),
    (r"\bbuffer\s+\w+\s*\{", "SSBO block (GL 4.3)"),
    (r"\batomic\w*\b", "atomics (GL 4.2+)"),
    (r"#extension\s+GL_ARB_compute", "compute (GL 4.3)"),
    (r"\bgl_(GlobalInvocationID|LocalInvocationID|WorkGroupID)\b", "compute built-ins"),
    (r"\b(iris_\w+|irisMain|moj_import)\b", "reserved Iris patcher identifier"),
]

errors = []
warnings = []


def rel(p):
    return os.path.relpath(p, ROOT)


# ---------------------------------------------------------------- options ---
BOOL_RE = re.compile(r"^(\s*)(//\s*)?#define\s+([A-Za-z_][A-Za-z0-9_]*)\s*//(.*)$")
VALUE_RE = re.compile(r"^(\s*)#define\s+([A-Za-z_][A-Za-z0-9_]*)\s+(\S+)\s*//\s*\[([^\]]*)\]")
CONST_RE = re.compile(r"^(\s*)const\s+(int|float|bool)\s+(\w+)\s*=\s*([^;]+);\s*//\s*\[([^\]]*)\]")


def parse_options(settings_text):
    bools, values, consts = {}, {}, {}
    for line in settings_text.splitlines():
        m = VALUE_RE.match(line)
        if m:
            values[m.group(2)] = (m.group(3), m.group(4).split())
            continue
        m = CONST_RE.match(line)
        if m:
            consts[m.group(3)] = (m.group(4).strip(), m.group(5).split())
            continue
        m = BOOL_RE.match(line)
        if m:
            bools[m.group(3)] = m.group(2) is None
    return bools, values, consts


def apply_config(settings_text, cfg_bools, cfg_values):
    out = []
    for line in settings_text.splitlines():
        m = VALUE_RE.match(line)
        if m and m.group(2) in cfg_values:
            name = m.group(2)
            line = re.sub(r"(#define\s+" + name + r"\s+)(\S+)", r"\g<1>" + cfg_values[name], line, count=1)
            out.append(line)
            continue
        m = CONST_RE.match(line)
        if m and m.group(3) in cfg_values:
            name = m.group(3)
            line = re.sub(r"(=\s*)([^;]+)(;)", r"\g<1>" + cfg_values[name] + r"\g<3>", line, count=1)
            out.append(line)
            continue
        m = BOOL_RE.match(line)
        if m and m.group(3) in cfg_bools:
            indent, name, rest = m.group(1), m.group(3), m.group(4)
            on = cfg_bools[name]
            line = indent + ("" if on else "//") + "#define " + name + " //" + rest
        out.append(line)
    return "\n".join(out) + "\n"


def read_properties_lines(path):
    """Joins backslash continuations, strips comments. Keeps preprocessor lines."""
    if not os.path.exists(path):
        return []
    lines, buf = [], ""
    for raw in open(path, encoding="utf-8").read().splitlines():
        s = raw.strip()
        if buf:
            s = buf + " " + s
            buf = ""
        if s.endswith("\\"):
            buf = s[:-1].strip()
            continue
        if not s:
            continue
        lines.append(s)
    return lines


def parse_profiles(props_lines):
    profiles = {}
    for s in props_lines:
        if s.startswith("#"):
            continue
        m = re.match(r"^profile\.(\w+)\s*=\s*(.*)$", s)
        if m:
            profiles[m.group(1)] = m.group(2).split()
    return profiles


def resolve_profile(name, profiles, seen=None):
    seen = seen or set()
    if name in seen:
        errors.append(f"shaders.properties: profile loop through {name}")
        return {}, {}
    seen.add(name)
    b, v = {}, {}
    for tok in profiles.get(name, []):
        if tok.startswith("profile."):
            bb, vv = resolve_profile(tok[len("profile."):], profiles, seen)
            b.update(bb)
            v.update(vv)
        elif tok.startswith("!program."):
            continue
        elif tok.startswith("!"):
            b[tok[1:]] = False
        elif "=" in tok or ":" in tok:
            k, val = re.split(r"[=:]", tok, maxsplit=1)
            v[k] = val
        else:
            b[tok] = True
    return b, v


# --------------------------------------------------------------- includes ---
INCLUDE_RE = re.compile(r'^\s*#include\s+"([^"]+)"')


def expand(path, overrides, stack=()):
    """Returns a list of (line_text, "file:line") so errors can be mapped back."""
    if path in stack:
        raise RuntimeError("include cycle: " + " -> ".join(rel(p) for p in stack + (path,)))
    relpath = os.path.relpath(path, SHADERS)
    if relpath in overrides:
        text = overrides[relpath]
    else:
        text = open(path, encoding="utf-8").read()
    out = []
    for n, line in enumerate(text.splitlines(), 1):
        m = INCLUDE_RE.match(line)
        if m:
            inc = m.group(1)
            target = os.path.join(SHADERS, inc.lstrip("/")) if inc.startswith("/") else os.path.join(os.path.dirname(path), inc)
            target = os.path.normpath(target)
            if not os.path.exists(target):
                raise RuntimeError(f"{rel(path)}:{n}: missing include {inc}")
            out.extend(expand(target, overrides, stack + (path,)))
        else:
            out.append((line, f"{os.path.relpath(path, SHADERS)}:{n}"))
    return out


def inject_macros(lines, extra_macros):
    for i, (line, _) in enumerate(lines):
        if line.strip().startswith("#version"):
            if line.strip() != "#version 330 compatibility":
                errors.append(f"{lines[i][1]}: #version must be '330 compatibility', found '{line.strip()}'")
            macros = [(f"#define {k} {v}".rstrip(), "<iris macro>") for k, v in IRIS_MACROS + extra_macros]
            return lines[: i + 1] + macros + lines[i + 1:]
    errors.append("no #version line")
    return lines


def map_errors(out, file_maps):
    """Rewrites 'ERROR: <tmpfile>:<line>:' / 'ERROR: 0:<line>:' to original file:line."""
    res = []
    for l in out.splitlines():
        m = re.match(r"^(ERROR|WARNING): (\S+?):(\d+): (.*)$", l)
        if m:
            fname, ln = m.group(2), int(m.group(3))
            lm = file_maps.get(os.path.basename(fname))
            if lm and 1 <= ln <= len(lm):
                l = f"{m.group(1)}: {lm[ln - 1]}: {m.group(4)}"
        res.append(l)
    return "\n".join(res)


# ----------------------------------------------------------------- lints ---
def strip_comments(src):
    src = re.sub(r"/\*.*?\*/", lambda m: "\n" * m.group(0).count("\n"), src, flags=re.S)
    return re.sub(r"//[^\n]*", "", src)


def lint_source(name, src, known_macros):
    code = strip_comments(src)
    for pat, why in FORBIDDEN_TOKENS:
        m = re.search(pat, code)
        if m:
            errors.append(f"{name}: forbidden on macOS GL 4.1 / Iris: {why} ('{m.group(0)}')")
    # for-loop bounds must be compile-time: literal, ALL_CAPS macro or const
    for m in re.finditer(r"\bfor\s*\(([^;]*);([^;]*);", code):
        cond = m.group(2).strip()
        cm = re.match(r"^\w+\s*(<|<=|>|>=|!=)\s*(.+)$", cond)
        if cm:
            bound = cm.group(2).strip()
            if not re.match(r"^[-+]?\d+(\.\d*)?$|^[A-Z_][A-Z0-9_]*$|^k[A-Z]\w*$", bound):
                warnings.append(f"{name}: for-loop bound '{bound}' is not a literal/macro/kConst (dynamic loop bound?)")
    # smoothstep(edge0, edge1, x) with edge0 >= edge1 is undefined in GLSL and
    # Metal. Write 1.0 - smoothstep(edge1, edge0, x) instead.
    for m in re.finditer(r"\bsmoothstep\s*\(\s*([-+]?\d*\.?\d+)\s*,\s*([-+]?\d*\.?\d+)\s*,", code):
        if float(m.group(1)) >= float(m.group(2)):
            errors.append(f"{name}: smoothstep({m.group(1)}, {m.group(2)}, ...) has edge0 >= edge1 (undefined on Apple GPUs)")
    # #ifdef on names nothing defines = probably a typo
    for m in re.finditer(r"#\s*(?:ifdef|ifndef)\s+(\w+)|defined\s*\(?\s*(\w+)", code):
        n = m.group(1) or m.group(2)
        if n not in known_macros and not n.startswith("GL_") and not n.startswith("IRIS_FEATURE_"):
            warnings.append(f"{name}: #ifdef on unknown macro '{n}' (typo?)")


def collect_defines(all_files, option_names):
    names = set(k for k, _ in IRIS_MACROS)
    for f in all_files:
        text = open(f, encoding="utf-8").read()
        for m in re.finditer(r"#\s*define\s+(\w+)", text):
            names.add(m.group(1))
        # Iris makes any value-less "#define X" that is tested with #ifdef a
        # menu option. Internal macros must carry a value.
        for n, line in enumerate(text.splitlines(), 1):
            m = re.match(r"^\s*#\s*define\s+(\w+)\s*$", line)
            if m and m.group(1) not in option_names:
                errors.append(f"{rel(f)}:{n}: '#define {m.group(1)}' has no value -> Iris would show it as a menu "
                              f"option. Write '#define {m.group(1)} 1'.")
    return names



# ------------------------------------------------------- Apple GL compiler ---
# Second opinion from Apple's real driver (OpenGL 4.1 Metal, same as the game).
# Iris converts compatibility-profile code to core before compiling; we do the
# same for the handful of legacy built-ins Solstice uses, then compile + link
# in an offscreen context with tools/applegl.c.
APPLEGL_SRC = os.path.join(ROOT, "tools", "applegl.c")
APPLEGL_BIN = os.path.join(ROOT, "tools", ".applegl")

CORE_VERTEX_DECLS = [
    "in vec3 solPosition;", "in vec4 solColor;", "in vec2 solUV0;", "in ivec2 solUV2;", "in vec3 solNormal;",
    "uniform mat4 solModelView;", "uniform mat4 solProjection;", "uniform mat3 solNormalMatrix;",
    "uniform mat4 solTexMat0;", "uniform mat4 solTexMat1;",
]
CORE_REPLACEMENTS = [
    (r"\bftransform\s*\(\s*\)", "(solProjection * solModelView * vec4(solPosition, 1.0))"),
    (r"\bgl_ModelViewProjectionMatrix\b", "(solProjection * solModelView)"),
    (r"\bgl_ModelViewMatrix\b", "solModelView"),
    (r"\bgl_ProjectionMatrix\b", "solProjection"),
    (r"\bgl_NormalMatrix\b", "solNormalMatrix"),
    (r"\bgl_TextureMatrix\s*\[\s*0\s*\]", "solTexMat0"),
    (r"\bgl_TextureMatrix\s*\[\s*1\s*\]", "solTexMat1"),
    (r"\bgl_Vertex\b", "vec4(solPosition, 1.0)"),
    (r"\bgl_Color\b", "solColor"),
    (r"\bgl_MultiTexCoord0\b", "vec4(solUV0, 0.0, 1.0)"),
    (r"\bgl_MultiTexCoord[12]\b", "vec4(vec2(solUV2), 0.0, 1.0)"),
    (r"\bgl_Normal\b", "solNormal"),
]


def to_core(lines, stage):
    """lines: list of (text, origin) after macro injection. Returns same shape."""
    out = []
    for text, origin in lines:
        t = text
        if t.strip() == "#version 330 compatibility":
            out.append(("#version 330 core", origin))
            continue
        for pat, rep in CORE_REPLACEMENTS:
            t = re.sub(pat, rep, t)
        out.append((t, origin))
    if stage == "vert":
        # after the #version line and the macro block
        i = next(k for k, (t, _) in enumerate(out) if t.startswith("#version"))
        while i + 1 < len(out) and out[i + 1][1] == "<iris macro>":
            i += 1
        out = out[: i + 1] + [(d, "<core decls>") for d in CORE_VERTEX_DECLS] + out[i + 1:]
    return out


def build_applegl():
    if os.path.exists(APPLEGL_BIN) and os.path.getmtime(APPLEGL_BIN) >= os.path.getmtime(APPLEGL_SRC):
        return True
    r = subprocess.run(["clang", "-O1", "-Wno-deprecated-declarations", "-framework", "OpenGL",
                        APPLEGL_SRC, "-o", APPLEGL_BIN], capture_output=True, text=True)
    if r.returncode != 0:
        warnings.append("could not build tools/applegl.c (Apple GL check skipped): " + r.stderr[:300])
        return False
    return True


def run_applegl(jobs, tmp):
    """jobs: list of (label, vpath, fpath, vmap, fmap, cname). Returns failures dict."""
    listfile = os.path.join(tmp, "applegl.list")
    with open(listfile, "w") as f:
        for i, (label, vp, fp, _, _, _) in enumerate(jobs):
            f.write(f"{i}\t{vp}\t{fp}\n")
    r = subprocess.run([APPLEGL_BIN, listfile], capture_output=True, text=True)
    out = r.stdout + r.stderr
    fails, warns = {}, {}
    blocks = re.split(r"^### ", out, flags=re.M)
    summary = ""
    for b in blocks:
        if not b.strip():
            continue
        if b.startswith("applegl:"):
            summary = b.strip()
            continue
        head, _, body = b.partition("\n")
        kind, idx = head.split()[0], int(head.split()[1])
        label, vp, fp, vmap, fmap, cname = jobs[idx]
        mapped = []
        section = None
        for l in body.splitlines():
            m = re.match(r"^\[(vertex|fragment|link)\] ?(.*)$", l)
            if m:
                section, l = m.group(1), m.group(2)
            if not l.strip():
                continue
            mm = re.match(r"^(ERROR|WARNING): 0:(\d+): (.*)$", l)
            lm = vmap if section == "vertex" else fmap
            if mm and lm and 1 <= int(mm.group(2)) <= len(lm):
                l = f"{mm.group(1)}: {lm[int(mm.group(2)) - 1]}: {mm.group(3)}"
            mapped.append(f"  [{section}] {l}")
        msg = "\n".join(mapped)
        (fails if kind == "FAIL" else warns).setdefault((label, msg), []).append(cname)
    return fails, warns, summary

# ------------------------------------------------------------------- main ---
def programs():
    found = {}
    for dirpath, dirnames, filenames in os.walk(SHADERS):
        reldir = os.path.relpath(dirpath, SHADERS)
        if reldir.split(os.sep)[0] in ("lib", "program", "textures"):
            continue
        for fn in filenames:
            base, ext = os.path.splitext(fn)
            if ext in FORBIDDEN_FILES:
                errors.append(f"{rel(os.path.join(dirpath, fn))}: {ext} shaders are not allowed (GL 4.1 / no geometry shaders)")
            if ext in STAGES:
                key = os.path.normpath(os.path.join(reldir, base))
                found.setdefault(key, {})[ext] = os.path.join(dirpath, fn)
    return found


def run_glslang(files):
    cmd = [GLSLANG, "-l"] + files
    r = subprocess.run(cmd, capture_output=True, text=True)
    return r.returncode, (r.stdout + r.stderr)


def check_properties(bools, values, consts):
    props = read_properties_lines(os.path.join(SHADERS, "shaders.properties"))
    names = set(bools) | set(values) | set(consts)
    for s in props:
        if s.startswith("#"):
            continue
        m = re.match(r"^(screen(?:\.\w+)?|sliders)\s*=\s*(.*)$", s)
        if m and not m.group(1).endswith(".columns"):
            for tok in m.group(2).split():
                if tok in ("<empty>", "<profile>", "*") or (tok.startswith("[") and tok.endswith("]")):
                    continue
                if tok not in names:
                    errors.append(f"shaders.properties: {m.group(1)} lists unknown option '{tok}'")
    profiles = parse_profiles(props)
    for pname in profiles:
        b, v = resolve_profile(pname, profiles)
        for k in b:
            if k not in bools:
                errors.append(f"profile.{pname}: '{k}' is not a boolean option")
        for k, val in v.items():
            allowed = values.get(k, consts.get(k, (None, None)))[1]
            if allowed is None:
                errors.append(f"profile.{pname}: '{k}' is not a value option")
            elif val not in allowed:
                errors.append(f"profile.{pname}: {k}={val} is not in its value list {allowed}")
    lang = os.path.join(SHADERS, "lang", "en_us.lang")
    if os.path.exists(lang):
        text = open(lang, encoding="utf-8").read()
        for n in sorted(names):
            if f"option.{n}=" not in text and f"option.{n} =" not in text:
                warnings.append(f"en_us.lang: no label for option {n}")
    return profiles


def main():
    if subprocess.run(["which", GLSLANG], capture_output=True).returncode != 0:
        print("glslangValidator not found. Install with: brew install glslang")
        return 2

    settings_path = os.path.join(SHADERS, SETTINGS_REL)
    settings_text = open(settings_path, encoding="utf-8").read()
    bools, values, consts = parse_options(settings_text)
    profiles = check_properties(bools, values, consts)

    all_src = [os.path.join(dp, f) for dp, _, fs in os.walk(SHADERS) for f in fs if f.endswith((".glsl", ".vsh", ".fsh"))]
    known = collect_defines(all_src, set(bools) | set(values) | set(consts))

    # Configurations: defaults, each profile, all toggles off, all on, each
    # toggle flipped alone, and each value option at its min and max.
    default_b = dict(bools)
    configs = [("defaults", {}, {})]
    for p in profiles:
        b, v = resolve_profile(p, profiles)
        configs.append((f"profile {p}", b, v))
    configs.append(("all toggles off", {k: False for k in bools}, {}))
    configs.append(("all toggles on", {k: True for k in bools}, {}))
    for p in profiles:
        b, v = resolve_profile(p, profiles)
        bb = {k: False for k in bools}
        configs.append((f"profile {p} + all toggles off", bb, v))
    for k in bools:
        configs.append((f"{k}={'off' if default_b[k] else 'on'}", {k: not default_b[k]}, {}))
    for k, (dv, allowed) in list(values.items()) + list(consts.items()):
        for val in {allowed[0], allowed[-1]}:
            if val != dv:
                configs.append((f"{k}={val}", {}, {k: val}))

    progs = programs()
    if not progs:
        errors.append("no programs found")
    for key, stages in progs.items():
        if ".vsh" not in stages or ".fsh" not in stages:
            errors.append(f"{key}: needs both .vsh and .fsh (has {sorted(stages)})")

    tmp = tempfile.mkdtemp(prefix="solstice-check-")
    use_apple = "--no-apple" not in sys.argv and build_applegl()
    apple_jobs = []
    seen = {}
    compiled = 0
    failures = {}
    for cname, cb, cv in configs:
        overrides = {SETTINGS_REL: apply_config(settings_text, cb, cv)}
        for key, stages in sorted(progs.items()):
            files, srcs, maps, full_lines = [], [], [], []
            for ext in (".vsh", ".fsh"):
                if ext not in stages:
                    continue
                try:
                    lines = expand(stages[ext], overrides)
                except RuntimeError as e:
                    errors.append(str(e))
                    continue
                lines = inject_macros(lines, [])
                srcs.append("\n".join(t for t, _ in lines) + "\n")
                maps.append([o for _, o in lines])
                full_lines.append(lines)
            if len(srcs) != 2:
                continue
            h = hashlib.sha1("\0".join(srcs).encode()).hexdigest()
            if h in seen:
                continue
            seen[h] = True
            safe = key.replace(os.sep, "__")
            file_maps = {}
            for ext, src, lm in zip((".vsh", ".fsh"), srcs, maps):
                fn = f"{safe}.{h[:8]}.{STAGES[ext]}"
                p = os.path.join(tmp, fn)
                open(p, "w").write(src)
                files.append(p)
                file_maps[fn] = lm
                if cname == "defaults":
                    lint_source(f"{key}{ext}", src, known)
            rc, out = run_glslang(files)
            compiled += 1
            if use_apple:
                cfiles, cmaps = [], []
                for ext, lm_lines in zip((".vsh", ".fsh"), full_lines):
                    stage = STAGES[ext]
                    core = to_core(lm_lines, stage)
                    cp = os.path.join(tmp, f"{safe}.{h[:8]}.core.{stage}")
                    open(cp, "w").write("\n".join(t for t, _ in core) + "\n")
                    cfiles.append(cp)
                    cmaps.append([o for _, o in core])
                apple_jobs.append((key, cfiles[0], cfiles[1], cmaps[0], cmaps[1], cname))
            if rc != 0:
                out = map_errors(out, file_maps)
                msg = "\n".join(l for l in out.splitlines() if l.strip() and not l.startswith(tmp) and "No code generated" not in l and not l.endswith(tmp))
                msg = msg.replace(tmp + "/", "")
                failures.setdefault((key, msg), []).append(cname)

    apple_summary = "Apple GL check skipped"
    if use_apple and apple_jobs:
        afails, awarns, apple_summary = run_applegl(apple_jobs, tmp)
        for (key, msg), cnames in sorted(afails.items()):
            shown = ", ".join(cnames[:6]) + (f" (+{len(cnames) - 6} more)" if len(cnames) > 6 else "")
            errors.append(f"[Apple GL] {key} fails in [{shown}]:\n{msg}")
        for (key, msg), cnames in sorted(awarns.items()):
            if "--apple-warnings" in sys.argv:
                warnings.append(f"[Apple GL] {key} warnings:\n{msg}")

    for (key, msg), cnames in sorted(failures.items()):
        shown = ", ".join(cnames[:6]) + (f" (+{len(cnames) - 6} more)" if len(cnames) > 6 else "")
        errors.append(f"{key} fails in [{shown}]:\n{msg}")

    # de-duplicate warnings
    uniq_w = sorted(set(warnings))
    for w in uniq_w:
        print("WARN ", w)
    for e in errors:
        print("ERROR", e)
    print(f"\n{len(progs)} programs, {len(configs)} option configs, {compiled} unique compiles, "
          f"{len(errors)} errors, {len(uniq_w)} warnings")
    print(apple_summary)
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
