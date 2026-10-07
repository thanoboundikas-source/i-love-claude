/*
    Vanilla sky geometry (sky disc, sun/moon quads, stars). The Overworld sky
    is drawn procedurally in the deferred pass instead, so these programs
    draw nothing. They exist so nothing falls back to a program that would
    write garbage.
*/

void main() {
    gl_Position = ftransform();
}
