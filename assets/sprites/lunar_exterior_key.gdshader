shader_type canvas_item;

void fragment() {
	// Los sprites de la base tienen el fondo exterior pintado en este tono.
	vec3 exterior = vec3(30.0, 28.0, 43.0) / 255.0;
	vec3 pixel = texture(TEXTURE, UV).rgb;
	if (all(lessThan(abs(pixel - exterior), vec3(0.001)))) {
		COLOR.a = 0.0;
	}
}
