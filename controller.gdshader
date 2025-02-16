shader_type spatial;

uniform vec4 glass_color : source_color = vec4(1.0, 0.0, 0.0, 0.0);
uniform float roughness : hint_range(0.0, 1.0) = 0.01;
uniform float metallic : hint_range(0.0, 1.0) = 0.5;
uniform float emission_strength : hint_range(0.0, 5.0) = 3.0;
uniform float pulse_speed : hint_range(0.1, 5.0) = 1.0; // Controls how fast the pulse occurs
uniform float pulse_intensity : hint_range(0.0, 1.0) = 0.5; // Controls how strong the pulse is
uniform float cloudiness : hint_range(0.0, 1.0) = 0.4;
uniform float refraction_strength : hint_range(0.0, 1.0) = 0.5;
uniform float specular : hint_range(0.0, 1.0) = 0.8;
uniform float ior : hint_range(1.0, 3.0) = 1.45;
uniform sampler2D SCREEN_TEXTURE : hint_screen_texture, filter_linear_mipmap;
uniform vec3 fresnel_color : source_color = vec3(0.8, 0.9, 1.0);
//uniform vec3 fresnel_color : source_color = vec3(0.0, 0.0, 0.0);

void fragment() {
    // Calculate fresnel effect
    float fresnel = pow(1.0 - dot(NORMAL, VIEW), 5.0);
    
    // Calculate pulsing effect
    float pulse = (sin(TIME * pulse_speed) * 0.5 + 0.5) * pulse_intensity;
    
    // Refraction calculation
    vec3 world_normal = normalize(mat3(VIEW_MATRIX) * NORMAL);
    vec2 ref_ofs = SCREEN_UV - world_normal.xy * refraction_strength;
    vec3 refraction = texture(SCREEN_TEXTURE, ref_ofs).rgb;
    
    // Base color and transparency
    ALBEDO = mix(glass_color.rgb, refraction, refraction_strength);
    ALPHA = glass_color.a;
    
    // Enhanced reflection properties
    METALLIC = metallic + fresnel * 0.5;
    ROUGHNESS = roughness * (1.0 - fresnel * 0.5);
    SPECULAR = specular;
    
    // Add emission with fresnel enhancement and pulse
    float emission_pulse = emission_strength * (1.0 + pulse);
    EMISSION = glass_color.rgb * emission_pulse + fresnel_color * fresnel * emission_pulse;
    
    // Add noise for cloudiness
    float noise = fract(sin(dot(VERTEX.xy + TIME * 0.1, vec2(12.9898, 78.233))) * 43758.5453);
    ALPHA *= mix(1.0, noise, cloudiness);
    
    // IOR-based refraction
    vec3 refracted = refract(VIEW, NORMAL, 1.0 / ior);
    NORMAL_MAP = normalize(mix(NORMAL, refracted, refraction_strength));
}

void light() {
    // Enhanced specular highlights
    //float spec = pow(max(dot(reflect(-LIGHT, NORMAL), VIEW), 0.0), 32.0);
    //SPECULAR_LIGHT += spec * LIGHT_COLOR * specular;
    
    // Diffuse lighting
    //float ndotl = dot(NORMAL, LIGHT);
    //DIFFUSE_LIGHT += max(ndotl, 0.0) * LIGHT_COLOR;
}