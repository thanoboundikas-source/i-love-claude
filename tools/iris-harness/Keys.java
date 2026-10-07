import java.nio.file.*;
import java.util.*;
import net.irisshaders.iris.pipeline.transform.*;
import net.irisshaders.iris.pipeline.programs.ShaderKey;
import net.irisshaders.iris.shaderpack.loading.ProgramId;
import net.irisshaders.iris.gl.state.ShaderAttributeInputs;
import net.irisshaders.iris.gl.texture.TextureType;
import net.irisshaders.iris.helpers.Tri;
import net.irisshaders.iris.shaderpack.texture.TextureStage;
import net.irisshaders.iris.shaderpack.preprocessor.JcppProcessor;
import it.unimi.dsi.fastutil.objects.*;

/** For every Iris ShaderKey (gbuffers draw type): resolve the pack program with Iris's fallback
 *  chain, build the real attribute inputs, run Iris's patcher, write the result.
 *  args: srcdir(with <prog>.vsh/.fsh, e.g. from check dump) folderPrefix outdir */
public class Keys {
    public static void main(String[] a) throws Exception {
        Path src = Path.of(a[0]); String prefix = a[1]; Path out = Path.of(a[2]); Files.createDirectories(out);
        var cfgField = net.irisshaders.iris.Iris.class.getDeclaredField("irisConfig");
        cfgField.setAccessible(true);
        cfgField.set(null, new net.irisshaders.iris.config.IrisConfig(Path.of(System.getProperty("java.io.tmpdir"), "iris-harness.properties"), Path.of(System.getProperty("java.io.tmpdir"), "iris-harness-excluded.json")));
        var f0 = TransformPatcher.class.getDeclaredField("transformer"); f0.setAccessible(true);
        Object transformer = f0.get(null);
        java.lang.reflect.Method m = null;
        for (var mm : transformer.getClass().getMethods()) if (mm.getName().equals("transform") && mm.getParameterCount() == 2) m = mm;
        Object2ObjectMap<Tri<String, TextureType, TextureStage>, String> tex = new Object2ObjectOpenHashMap<>();
        for (ShaderKey key : ShaderKey.values()) {
            ProgramId pid = key.getProgram();
            if (pid == null) continue;
            String grp = pid.getGroup().name();
            ProgramId resolved = pid;
            while (resolved != null && !Files.exists(src.resolve(prefix + resolved.getSourceName() + ".vsh"))) resolved = resolved.getFallback().orElse(null);
            if (resolved == null) { System.out.println("NOPROG " + key); continue; }
            if (grp.equals("Dh")) continue;
            boolean isLines = pid == ProgramId.Line && Files.exists(src.resolve(prefix + "gbuffers_line.vsh"));
            boolean shadow = grp.equals("Shadow");
            String v = JcppProcessor.glslPreprocessSource(Files.readString(src.resolve(prefix + resolved.getSourceName() + ".vsh")), List.of());
            String f = JcppProcessor.glslPreprocessSource(Files.readString(src.resolve(prefix + resolved.getSourceName() + ".fsh")), List.of());
            ShaderAttributeInputs inputs = new ShaderAttributeInputs(key.getVertexFormat(), key.shouldIgnoreLightmap(), isLines, key.isGlint(), key.isText(), key == ShaderKey.IE_COMPAT);
            var p = new net.irisshaders.iris.pipeline.transform.parameter.VanillaParameters(Patch.VANILLA, tex, key.getAlphaTest(), isLines, key == ShaderKey.CLOUDS, true, inputs, false, false);
            String tag = prefix + key.name() + "__" + resolved.getSourceName();
            p.name = tag;
            EnumMap<PatchShaderType, String> in = new EnumMap<>(PatchShaderType.class);
            in.put(PatchShaderType.VERTEX, v); in.put(PatchShaderType.GEOMETRY, null); in.put(PatchShaderType.TESS_CONTROL, null);
            in.put(PatchShaderType.TESS_EVAL, null); in.put(PatchShaderType.FRAGMENT, f);
            try {
                @SuppressWarnings("unchecked") Map<PatchShaderType, String> r = (Map<PatchShaderType, String>) m.invoke(transformer, in, p);
                for (var e : r.entrySet()) if (e.getValue() != null) Files.writeString(out.resolve(tag + "." + e.getKey().name().toLowerCase()), e.getValue());
            } catch (java.lang.reflect.InvocationTargetException e) {
                System.out.println("TRANSFORM-FAIL " + tag + ": " + e.getCause());
            }
        }
    }
}
