shader_type spatial;

uniform sampler2D heightmap;
uniform float height_scale = 200.0;
uniform sampler2D grass_tex;
uniform sampler2D rock_tex;

void vertex() {
    float h = texture(heightmap, UV).r;
    VERTEX.y += h * height_scale;
}
void fragment() {
    vec2 uv = VERTEX.xz * 0.1; 

    vec4 grass = texture(grass_tex, uv);

    ALBEDO = grass.rgb;
}