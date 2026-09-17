shader_type canvas_item;

// An .aseprite file goes straight into this uniform. Imported with Import As: Aseprite Texture it
// is an ordinary Texture2D, so a shader takes it like any other. Put this material on a node and
// pass examples/shadow.aseprite here to see it.
// filter_nearest keeps the pixels crisp whatever the project default is.
uniform sampler2D aseprite_texture : source_color, filter_nearest;
uniform vec4 tint : source_color = vec4(0.35, 0.55, 1.0, 1.0);

void fragment() {
	// Only the alpha of the imported file is read, so the shape comes from Aseprite and the
	// colour from the shader: if the texture failed to import, nothing is drawn at all.
	float coverage = texture(aseprite_texture, UV).a;
	COLOR = vec4(tint.rgb, coverage * tint.a);
}
