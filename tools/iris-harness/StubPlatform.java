import java.nio.file.*;
import net.irisshaders.iris.platform.IrisPlatformHelpers;

/** Minimal platform so Iris classes load outside the game (harness only). */
public class StubPlatform implements IrisPlatformHelpers {
    public boolean isModLoaded(String modId) { return false; }
    public String getVersion() { return "1.11.4"; }
    public boolean isDevelopmentEnvironment() { return false; }
    public Path getGameDir() { return Path.of(System.getProperty("java.io.tmpdir"), "iris-harness-game"); }
    public Path getConfigDir() { return getGameDir().resolve("config"); }
    public int compareVersions(String a, String b) { return 0; }
    public net.minecraft.client.KeyMapping registerKeyBinding(net.minecraft.client.KeyMapping k) { return k; }
    public boolean useELS() { return false; }
    public net.minecraft.world.level.block.state.BlockState getBlockAppearance(net.minecraft.client.renderer.block.BlockAndTintGetter l,
        net.minecraft.world.level.block.state.BlockState s, net.minecraft.core.Direction d, net.minecraft.core.BlockPos p) { return s; }
    public com.mojang.blaze3d.textures.TextureFormat mojangDepthFormat(net.irisshaders.iris.gl.texture.DepthBufferFormat f) { return null; }
}
