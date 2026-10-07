import java.nio.file.*;
import java.util.*;
import net.irisshaders.iris.pipeline.transform.*;
import net.irisshaders.iris.gl.blending.*;
import net.irisshaders.iris.gl.state.ShaderAttributeInputs;
import net.irisshaders.iris.gl.texture.TextureType;
import net.irisshaders.iris.helpers.Tri;
import net.irisshaders.iris.shaderpack.texture.TextureStage;
import net.irisshaders.iris.shaderpack.preprocessor.JcppProcessor;
import it.unimi.dsi.fastutil.objects.*;

/** Runs Iris's real preprocessor + patcher on one program. args: mode name vsh fsh outdir */
public class Harness {
    public static void main(String[] a) throws Exception {
        String mode = a[0], name = a[1];
        String v = JcppProcessor.glslPreprocessSource(Files.readString(Path.of(a[2])), List.of());
        String f = JcppProcessor.glslPreprocessSource(Files.readString(Path.of(a[3])), List.of());
        Object2ObjectMap<Tri<String, TextureType, TextureStage>, String> tex = new Object2ObjectOpenHashMap<>();
        AlphaTest alpha = new AlphaTest(AlphaTestFunction.GREATER, 0.1f);
        var cfgField = net.irisshaders.iris.Iris.class.getDeclaredField("irisConfig");
        cfgField.setAccessible(true);
        if (cfgField.get(null) == null) cfgField.set(null, new net.irisshaders.iris.config.IrisConfig(Path.of(System.getProperty("java.io.tmpdir"), "iris-harness.properties"), Path.of(System.getProperty("java.io.tmpdir"), "iris-harness-excluded.json")));
        var f0 = TransformPatcher.class.getDeclaredField("transformer");
        f0.setAccessible(true);
        Object transformer = f0.get(null);
        java.lang.reflect.Method m = null;
        for (var mm : transformer.getClass().getMethods()) if (mm.getName().equals("transform") && mm.getParameterCount() == 2) m = mm;
        Path out = Path.of(a[4]); Files.createDirectories(out);
        List<Object[]> variants = new ArrayList<>();
        if (mode.equals("vanilla")) {
            for (int bits = 0; bits < 64; bits++) variants.add(new Object[]{bits});
        } else variants.add(new Object[]{-1});
        for (Object[] var : variants) {
            int bits = (Integer) var[0];
            net.irisshaders.iris.pipeline.transform.parameter.Parameters p;
            String tag = name;
            switch (mode) {
                case "sodium": p = new net.irisshaders.iris.pipeline.transform.parameter.SodiumParameters(Patch.SODIUM, tex, alpha, false); break;
                case "shadow": p = new net.irisshaders.iris.pipeline.transform.parameter.SodiumParameters(Patch.SODIUM, tex, alpha, true); tag = name + "_sodiumshadow"; break;
                case "vanilla":
                    boolean lines = (bits & 32) != 0;
                    p = new net.irisshaders.iris.pipeline.transform.parameter.VanillaParameters(Patch.VANILLA, tex, alpha, lines, false, false,
                        new ShaderAttributeInputs((bits & 1) != 0, (bits & 2) != 0, (bits & 4) != 0, (bits & 8) != 0, (bits & 16) != 0), false, false);
                    tag = name + "_v" + bits; break;
                default: p = new net.irisshaders.iris.pipeline.transform.parameter.TextureStageParameters(Patch.COMPOSITE, TextureStage.COMPOSITE_AND_FINAL, tex);
            }
            p.name = tag;
            EnumMap<PatchShaderType, String> inputs = new EnumMap<>(PatchShaderType.class);
            inputs.put(PatchShaderType.VERTEX, v);
            inputs.put(PatchShaderType.GEOMETRY, null);
            inputs.put(PatchShaderType.TESS_CONTROL, null);
            inputs.put(PatchShaderType.TESS_EVAL, null);
            inputs.put(PatchShaderType.FRAGMENT, f);
            try {
                @SuppressWarnings("unchecked") Map<PatchShaderType, String> r = (Map<PatchShaderType, String>) m.invoke(transformer, inputs, p);
                for (var e : r.entrySet()) if (e.getValue() != null) Files.writeString(out.resolve(tag + "." + e.getKey().name().toLowerCase()), e.getValue());
            } catch (java.lang.reflect.InvocationTargetException e) {
                System.out.println("FAIL " + tag + ": " + e.getCause());
            }
        }
        System.out.println("OK " + name);
    }
}
