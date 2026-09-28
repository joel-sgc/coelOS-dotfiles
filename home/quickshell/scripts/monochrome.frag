// Grayscale screen shader for Hyprland's decoration:screen_shader option
// (toggled from LauncherPanel.qml's "Monochrome" entry). Standard Hyprland
// screen-shader boilerplate (v_texcoord/tex are the names Hyprland's own
// renderer binds) with a luminance-weighted desaturation rather than a
// flat (r+g+b)/3 average, so relative brightness between colors still
// reads correctly once desaturated.
#version 300 es
precision highp float;
in vec2 v_texcoord;
out vec4 fragColor;
uniform sampler2D tex;

void main() {
    vec4 pixColor = texture(tex, v_texcoord);
    float gray = dot(pixColor.rgb, vec3(0.299, 0.587, 0.114));
    fragColor = vec4(gray, gray, gray, pixColor.a);
}
