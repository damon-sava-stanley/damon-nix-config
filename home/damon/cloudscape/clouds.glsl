
    // Adapted from the browser study for Shadertoy/Papertoy.
    #define resolution iResolution.xy
    #define time (iTime * 0.2)
    #define dark uDark
    const float definition = 0.4;

    float hash(vec2 p) {
      return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
    }
    float noise(vec2 p) {
      vec2 i = floor(p), f = fract(p);
      vec2 u = f*f*(3.0-2.0*f);
      return mix(mix(hash(i), hash(i+vec2(1,0)), u.x),
                 mix(hash(i+vec2(0,1)), hash(i+vec2(1,1)), u.x), u.y);
    }
    float fbm(vec2 p) {
      float value = 0.0;
      float amplitude = 0.5;
      mat2 turn = mat2(0.8, -0.6, 0.6, 0.8);
      for (int i = 0; i < 5; i++) {
        value += amplitude * noise(p);
        p = turn * p * 2.03 + vec2(13.1, 7.7);
        amplitude *= 0.5;
      }
      return value;
    }
    float clouds(vec2 p, float t) {
      // Slow deformation, separate from the prevailing wind.
      vec2 warp = vec2(fbm(p * 0.65 + vec2(t * 0.07, 7.0)),
                       fbm(p * 0.65 + vec2(19.0, -t * 0.05)));
      return fbm(p + 1.35 * warp);
    }
    void mainImage(out vec4 fragColor, in vec2 fragCoord) {
      vec2 uv = fragCoord / resolution;
      vec2 p = (uv - 0.5) * vec2(resolution.x / resolution.y, 1.0);
      float t = time * 0.018;
      // Flattened billows rather than uniform smoke; no horizon line.
      vec2 q = p * vec2(3.0, 4.4) + vec2(-t, 0.08*t) + vec2(4.8, 9.2);
      float body = clouds(q, t);
      float above = clouds(q + vec2(-0.06, 0.11), t);
      float coverage = smoothstep(0.34, 0.63, body);
      float distant = smoothstep(0.36, 0.69,
        fbm(p * vec2(2.4, 3.6) + vec2(-t * 0.45, 30.0)));
      // Broad density shading plus a soft directional rim gives rounded banks.
      float edgeLight = clamp(0.5 + (body - above) * 3.8, 0.0, 1.0);
      float shade = clamp(0.28 + (body - 0.42) * 1.8 + edgeLight * 0.38, 0.0, 1.0);
      vec3 lightSky = mix(vec3(0.396, 0.482, 0.514), vec3(0.576, 0.631, 0.631), uv.y);
      vec3 darkSky = mix(vec3(0.0, 0.169, 0.212), vec3(0.027, 0.212, 0.259), uv.y);
      vec3 sky = mix(lightSky, darkSky, dark);
      vec3 shadow = mix(vec3(0.576, 0.631, 0.631), vec3(0.027, 0.212, 0.259), dark);
      vec3 mid = mix(vec3(0.933, 0.910, 0.835), vec3(0.345, 0.431, 0.459), dark);
      vec3 highlight = mix(vec3(0.992, 0.965, 0.890), vec3(0.514, 0.580, 0.588), dark);
      vec3 cloudColor = mix(shadow, mid, smoothstep(0.15, 0.7, shade));
      cloudColor = mix(cloudColor, highlight, smoothstep(0.65, 1.0, shade) * 0.65);
      vec3 color = mix(sky, mid, distant * 0.22);
      color = mix(color, cloudColor, coverage * 0.94);
      vec3 quiet = mix(vec3(0.72, 0.76, 0.73), vec3(0.06, 0.22, 0.26), dark);
      color = mix(quiet, color, definition);
      fragColor = vec4(clamp(color, 0.0, 1.0), 1.0);
    }
