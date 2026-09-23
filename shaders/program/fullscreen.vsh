/*
    Shared vertex stage for every fullscreen (composite-style) pass.
    Iris draws one quad over the pass's render target; texcoord spans 0..1
    over that target regardless of its size.
*/

out vec2 texcoord;

void main() {
    gl_Position = ftransform();
    texcoord = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;
}
