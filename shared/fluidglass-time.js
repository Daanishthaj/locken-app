// Liquid-glass clock digits for Locken's focus timer, shared by the Mac app (LockenTestApp/WebComponents) and the
// Windows app (windows/src), so both draw exactly the same timer.
//
// The digits are glass: their edges bend and shine, and one number melts into the next. Moving the pointer over them
// drops droplets of glass that merge, split and dissolve back into the digits. Written for Locken from the published
// techniques (Gray-Scott reaction-diffusion for the droplets, a height-field glass shader); no third-party
// fluid-glass code is used.
//
//   const glass = createFluidGlassTime(hostElement, { text: '24:59', accent: '#8B5CF6' });
//   glass.update({ text: '24:58' });   // morphs to the new digits
//   glass.supported                    // false when WebGL2 float rendering is missing (nothing is drawn)
//
// The host must be a sized, positioned element. If WebGL2 isn't available and `fallbackText` isn't false, the digits are
// shown as plain text in the host instead, so the timer is always readable.

const DEFAULT_TUNE = {
  feed: 0.0367, kill: 0.0649,   // Gray-Scott "spots" regime: round droplets that can split in two
  advect: 0, force: 0,          // pointer-driven drag is off: it smeared the glass into streaks, droplets read cleaner
  inject: 0.6, radius: 0.028,   // each droplet the pointer drops: how much glass, and how wide
  spacing: 0.09,                // a new droplet each time the pointer travels this far (in host heights)
  life: 0.988,                  // outside the digits, glass keeps this fraction each step, so droplets dissolve
  morph: 650,                   // milliseconds for one number to melt into the next
};

const VERT = `#version 300 es
out vec2 vUv;
void main() {
  vec2 p = vec2(float((gl_VertexID << 1) & 2), float(gl_VertexID & 2));
  vUv = p;
  gl_Position = vec4(p * 2.0 - 1.0, 0.0, 1.0);
}`;

// Pointer movement becomes a velocity field that fades quickly.
const VELOCITY = `#version 300 es
precision highp float;
in vec2 vUv; out vec4 o;
uniform sampler2D uVel;
uniform vec2 uPos, uDelta, uAspect;
uniform float uRadius, uForce;
void main() {
  vec2 v = texture(uVel, vUv).xy * 0.93;
  vec2 d = (vUv - uPos) * uAspect;
  v += uDelta * exp(-dot(d, d) / (uRadius * uRadius)) * uForce;
  o = vec4(v, 0.0, 1.0);
}`;

// Gray-Scott reaction-diffusion (r = A, g = B). B is the glass: it is held up inside the digits, injected under the
// pointer, and decays outside the digits so droplets dissolve back into them.
const SIM = `#version 300 es
precision highp float;
in vec2 vUv; out vec4 o;
uniform sampler2D uState, uVel, uMask, uMaskOld;
uniform vec2 uTexel, uPos, uAspect;
uniform float uFeed, uKill, uAdvect, uInject, uRadius, uLife, uMix, uFollow;
vec2 s(vec2 uv) { return texture(uState, uv).rg; }
void main() {
  vec2 uv = vUv - texture(uVel, vUv).xy * uAdvect;
  vec2 c = s(uv);
  vec2 lap = -c
    + 0.2 * (s(uv + vec2(uTexel.x, 0.0)) + s(uv - vec2(uTexel.x, 0.0)) + s(uv + vec2(0.0, uTexel.y)) + s(uv - vec2(0.0, uTexel.y)))
    + 0.05 * (s(uv + uTexel) + s(uv - uTexel) + s(uv + vec2(uTexel.x, -uTexel.y)) + s(uv + vec2(-uTexel.x, uTexel.y)));
  float abb = c.r * c.g * c.g;
  float a = c.r + (lap.x - abb + uFeed * (1.0 - c.r));
  float b = c.g + (0.5 * lap.y + abb - (uKill + uFeed) * c.g);
  vec2 d = (vUv - uPos) * uAspect;
  b += uInject * exp(-dot(d, d) / (uRadius * uRadius));
  // The digits are a blend of the old and the new shapes while one number morphs into the next; the glass follows
  // that blend both up and down, so the old digit melts into the new one instead of fading behind it.
  float m = mix(texture(uMaskOld, vUv).g, texture(uMask, vUv).g, uMix);
  b = mix(b, m * 0.95, uFollow);
  b = max(b, m * 0.95);
  b *= mix(uLife, 1.0, m);
  o = vec4(clamp(a, 0.0, 1.0), clamp(b, 0.0, 1.0), 0.0, 1.0);
}`;

// Height field -> normals -> refraction of a soft studio backdrop (with a little colour fringing), specular glints,
// and a bright rim. Only the glass is opaque; everything else stays transparent so what is behind it shows through.
const RENDER = `#version 300 es
precision highp float;
in vec2 vUv; out vec4 o;
uniform sampler2D uState;
uniform vec2 uTexel, uAspect;
uniform vec3 uTint;
float raw(vec2 uv) { return smoothstep(0.10, 0.7, texture(uState, uv).g); }
// A soft bevel: the glass height is blurred over a few texels, so the surface curves like a rounded pane.
float height(vec2 uv) {
  float sum = raw(uv) * 2.0;
  for (int i = 0; i < 8; i++) {
    float a = float(i) * 0.7853982;
    vec2 d = vec2(cos(a), sin(a));
    sum += raw(uv + d * uTexel * 3.5) + raw(uv + d * uTexel * 7.0) * 0.6;
  }
  return sum / (2.0 + 8.0 * 1.6);
}
// The backdrop varies only from top to bottom, never side to side, so every digit is lit exactly the same way.
vec3 backdrop(vec2 uv) {
  float band = 0.5 + 0.5 * sin(uv.y * 11.0);
  return mix(uTint * 0.6, vec3(1.0), 0.2 + 0.22 * band);
}
void main() {
  vec2 e = uTexel * 2.2;
  float h = height(vUv);
  float hx = height(vUv + vec2(e.x, 0.0)) - height(vUv - vec2(e.x, 0.0));
  float hy = height(vUv + vec2(0.0, e.y)) - height(vUv - vec2(0.0, e.y));
  vec3 n = normalize(vec3(-hx * 5.5, -hy * 5.5, 1.0));
  float edge = clamp(length(vec2(hx, hy)) * 4.0, 0.0, 1.0);
  float cover = smoothstep(0.10, 0.40, h);

  vec2 off = n.xy * 0.09 * (0.4 + h);
  vec3 refr = vec3(backdrop(vUv + off * 0.86).r, backdrop(vUv + off).g, backdrop(vUv + off * 1.14).b);

  vec3 v = vec3(0.0, 0.0, 1.0);
  vec3 l1 = normalize(vec3(-0.55, 0.65, 0.7));
  vec3 l2 = normalize(vec3(0.6, -0.55, 0.6));
  float spec = pow(max(dot(n, normalize(l1 + v)), 0.0), 60.0) + 0.7 * pow(max(dot(n, normalize(l2 + v)), 0.0), 40.0);
  float rim = pow(1.0 - n.z, 1.5);

  vec3 col = refr * 0.8 + uTint * 0.1;
  col += vec3(spec * 1.15) + mix(vec3(1.0), uTint, 0.3) * rim * 1.1;
  col += vec3(0.07) * (1.0 - edge);          // a faint glow through the thick middle of each stroke
  float alpha = clamp(cover * 0.52 + edge * 0.6 + spec * 0.55, 0.0, 1.0);
  o = vec4(col * alpha, alpha);
}`;

function hexToRgb(hex) {
  const m = /^#?([0-9a-f]{6})$/i.exec(hex || '');
  const n = m ? parseInt(m[1], 16) : 0x8b5cf6;
  return [(n >> 16) / 255, ((n >> 8) & 255) / 255, (n & 255) / 255];
}

export function createFluidGlassTime(host, options = {}) {
  const props = { text: '25:00', accent: '#8B5CF6', ...options };
  const tune = { ...DEFAULT_TUNE, ...(options.tune || {}) };
  const fontSpec = options.fontFamily || 'Montserrat, sans-serif';
  const reducedMotion = window.matchMedia('(prefers-reduced-motion: reduce)');
  const showFallback = options.fallbackText !== false;

  if (getComputedStyle(host).position === 'static') host.style.position = 'relative';

  const canvas = document.createElement('canvas');
  canvas.style.cssText = 'position:absolute;inset:0;width:100%;height:100%;display:block';
  host.appendChild(canvas);
  const fallback = document.createElement('div');
  fallback.style.cssText = `position:absolute;inset:0;display:none;align-items:center;justify-content:center;color:#fff;font:700 64px ${fontSpec};font-variant-numeric:tabular-nums`;
  host.appendChild(fallback);

  const gl = canvas.getContext('webgl2', { alpha: true, premultipliedAlpha: true, antialias: false });
  const supported = Boolean(gl && gl.getExtension('EXT_color_buffer_float'));
  if (!supported) {
    canvas.style.display = 'none';
    if (showFallback) {
      fallback.textContent = props.text;
      fallback.style.display = 'flex';
    }
    return { supported: false, update(next = {}) { Object.assign(props, next); if (showFallback) fallback.textContent = props.text; }, destroy() { canvas.remove(); fallback.remove(); } };
  }

  let sim, velocity, render, vao;
  let stateA, stateB, velA, velB, maskTex, maskOldTex;
  let mixStart = -1e9;
  let simW = 0, simH = 0, cssW = 0, cssH = 0, maskCanvas, maskCtx;
  const splat = { x: 0.5, y: 0.5, dx: 0, dy: 0, active: false };
  let last = null;
  let lastDrop = null;
  const drops = []; // droplets waiting to be dropped, one per simulation step
  let settle = 0;
  let frameId = 0;
  let alive = true;

  function compile(type, source) {
    const shader = gl.createShader(type);
    gl.shaderSource(shader, source);
    gl.compileShader(shader);
    if (!gl.getShaderParameter(shader, gl.COMPILE_STATUS)) throw new Error(gl.getShaderInfoLog(shader));
    return shader;
  }
  function program(fragment) {
    const p = gl.createProgram();
    gl.attachShader(p, compile(gl.VERTEX_SHADER, VERT));
    gl.attachShader(p, compile(gl.FRAGMENT_SHADER, fragment));
    gl.linkProgram(p);
    if (!gl.getProgramParameter(p, gl.LINK_STATUS)) throw new Error(gl.getProgramInfoLog(p));
    const u = {};
    const count = gl.getProgramParameter(p, gl.ACTIVE_UNIFORMS);
    for (let i = 0; i < count; i++) {
      const name = gl.getActiveUniform(p, i).name;
      u[name] = gl.getUniformLocation(p, name);
    }
    return { p, u };
  }

  function target(w, h, filter) {
    const tex = gl.createTexture();
    gl.bindTexture(gl.TEXTURE_2D, tex);
    gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGBA16F, w, h, 0, gl.RGBA, gl.HALF_FLOAT, null);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, filter);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, filter);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE);
    const fbo = gl.createFramebuffer();
    gl.bindFramebuffer(gl.FRAMEBUFFER, fbo);
    gl.framebufferTexture2D(gl.FRAMEBUFFER, gl.COLOR_ATTACHMENT0, gl.TEXTURE_2D, tex, 0);
    gl.clearColor(0, 0, 0, 1);
    gl.clear(gl.COLOR_BUFFER_BIT);
    return { tex, fbo };
  }

  // A is 1 everywhere and B is 0 at the start.
  function resetState(t) {
    gl.bindFramebuffer(gl.FRAMEBUFFER, t.fbo);
    gl.clearColor(1, 0, 0, 1);
    gl.clear(gl.COLOR_BUFFER_BIT);
  }

  function setup() {
    cssW = host.clientWidth;
    cssH = host.clientHeight;
    if (cssW < 2 || cssH < 2) return false; // hidden or not laid out yet
    // A resize builds new buffers; free the old ones.
    for (const t of [stateA, stateB, velA, velB]) if (t) { gl.deleteTexture(t.tex); gl.deleteFramebuffer(t.fbo); }
    const dpr = Math.min(window.devicePixelRatio || 1, 2);
    canvas.width = Math.max(2, Math.round(cssW * dpr));
    canvas.height = Math.max(2, Math.round(cssH * dpr));
    simW = Math.min(512, Math.max(96, Math.round(cssW * 1.6)));
    simH = Math.max(48, Math.round(simW * cssH / cssW));
    stateA = target(simW, simH, gl.LINEAR);
    stateB = target(simW, simH, gl.LINEAR);
    velA = target(simW, simH, gl.LINEAR);
    velB = target(simW, simH, gl.LINEAR);
    resetState(stateA);
    resetState(stateB);

    // The digits are drawn on a 2D canvas the size of the sim grid x2, then used as a texture.
    maskCanvas = maskCanvas || document.createElement('canvas');
    maskCanvas.width = simW * 2;
    maskCanvas.height = simH * 2;
    maskCtx = maskCanvas.getContext('2d');
    maskTex = maskTex || gl.createTexture();
    maskOldTex = maskOldTex || gl.createTexture();
    drawMask(true);
    return true;
  }

  // Digits sit in fixed-width cells, so the clock doesn't jiggle as 1 and 0 change width.
  function drawMask(initial) {
    // The shape that was showing becomes the one to morph from (on the first draw both are the same).
    if (!initial) [maskOldTex, maskTex] = [maskTex, maskOldTex];
    const w = maskCanvas.width, h = maskCanvas.height;
    maskCtx.fillStyle = '#000';
    maskCtx.fillRect(0, 0, w, h);
    const text = props.text;
    let size = h * 0.62;
    maskCtx.font = `700 ${size}px ${fontSpec}`;
    const digit = maskCtx.measureText('0').width;
    const colon = digit * 0.45;
    const widths = [...text].map((c) => (c === ':' ? colon : digit));
    const total = widths.reduce((a, b) => a + b, 0);
    const fit = Math.min(1, (w * 0.9) / total);
    size *= fit;
    maskCtx.font = `700 ${size}px ${fontSpec}`;
    maskCtx.fillStyle = '#fff';
    maskCtx.textAlign = 'center';
    maskCtx.textBaseline = 'alphabetic';
    const metrics = maskCtx.measureText('0');
    const baseline = h / 2 + (metrics.actualBoundingBoxAscent - metrics.actualBoundingBoxDescent) / 2;
    let x = (w - total * fit) / 2;
    [...text].forEach((c, i) => {
      maskCtx.fillText(c, x + (widths[i] * fit) / 2, baseline);
      x += widths[i] * fit;
    });
    for (const tex of initial ? [maskTex, maskOldTex] : [maskTex]) {
      gl.bindTexture(gl.TEXTURE_2D, tex);
      gl.pixelStorei(gl.UNPACK_FLIP_Y_WEBGL, true);
      gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGBA, gl.RGBA, gl.UNSIGNED_BYTE, maskCanvas);
      gl.pixelStorei(gl.UNPACK_FLIP_Y_WEBGL, false);
      gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR);
      gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.LINEAR);
      gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE);
      gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE);
    }
    if (initial || reducedMotion.matches) {
      mixStart = -1e9; // no morph: show the new digits straight away
      settle = 28;     // a short burst of simulation so the digits get their soft glass edge
    } else {
      mixStart = performance.now();
    }
  }

  function bind(unit, tex) {
    gl.activeTexture(gl.TEXTURE0 + unit);
    gl.bindTexture(gl.TEXTURE_2D, tex);
  }

  function pass(prog, out, w, h) {
    gl.useProgram(prog.p);
    gl.bindFramebuffer(gl.FRAMEBUFFER, out ? out.fbo : null);
    gl.viewport(0, 0, w, h);
    gl.bindVertexArray(vao);
    gl.drawArrays(gl.TRIANGLES, 0, 3);
  }

  function step(drop) {
    const aspect = [cssW / cssH, 1];
    // 1. velocity
    gl.useProgram(velocity.p);
    bind(0, velA.tex);
    gl.uniform1i(velocity.u.uVel, 0);
    gl.uniform2f(velocity.u.uPos, splat.x, splat.y);
    gl.uniform2f(velocity.u.uDelta, splat.dx, splat.dy);
    gl.uniform2f(velocity.u.uAspect, aspect[0], aspect[1]);
    gl.uniform1f(velocity.u.uRadius, 0.11);
    gl.uniform1f(velocity.u.uForce, tune.force);
    pass(velocity, velB, simW, simH);
    [velA, velB] = [velB, velA];

    // 2. reaction-diffusion + advection
    gl.useProgram(sim.p);
    bind(0, stateA.tex); gl.uniform1i(sim.u.uState, 0);
    bind(1, velA.tex); gl.uniform1i(sim.u.uVel, 1);
    bind(2, maskTex); gl.uniform1i(sim.u.uMask, 2);
    bind(3, maskOldTex); gl.uniform1i(sim.u.uMaskOld, 3);
    const t = Math.min(1, (performance.now() - mixStart) / tune.morph);
    gl.uniform1f(sim.u.uMix, t * t * (3 - 2 * t));
    gl.uniform1f(sim.u.uFollow, t < 1 ? 0.35 : 0);
    gl.uniform2f(sim.u.uTexel, 1 / simW, 1 / simH);
    gl.uniform2f(sim.u.uPos, drop ? drop.x : -1, drop ? drop.y : -1);
    gl.uniform2f(sim.u.uAspect, aspect[0], aspect[1]);
    gl.uniform1f(sim.u.uFeed, tune.feed);
    gl.uniform1f(sim.u.uKill, tune.kill);
    gl.uniform1f(sim.u.uAdvect, tune.advect);
    gl.uniform1f(sim.u.uInject, drop ? tune.inject : 0);
    gl.uniform1f(sim.u.uRadius, tune.radius);
    gl.uniform1f(sim.u.uLife, tune.life);
    pass(sim, stateB, simW, simH);
    [stateA, stateB] = [stateB, stateA];
  }

  function draw() {
    gl.useProgram(render.p);
    bind(0, stateA.tex);
    gl.uniform1i(render.u.uState, 0);
    gl.uniform2f(render.u.uTexel, 1 / simW, 1 / simH);
    gl.uniform2f(render.u.uAspect, cssW / cssH, 1);
    gl.uniform3fv(render.u.uTint, hexToRgb(props.accent));
    gl.enable(gl.BLEND);
    gl.blendFunc(gl.ONE, gl.ONE_MINUS_SRC_ALPHA);
    gl.bindFramebuffer(gl.FRAMEBUFFER, null);
    gl.viewport(0, 0, canvas.width, canvas.height);
    gl.clearColor(0, 0, 0, 0);
    gl.clear(gl.COLOR_BUFFER_BIT);
    gl.bindVertexArray(vao);
    gl.drawArrays(gl.TRIANGLES, 0, 3);
    gl.disable(gl.BLEND);
  }

  // The liquid drifts slowly. While nothing is happening to it (no pointer near, no change of digits) it is drawn every other
  // frame with twice the simulation steps, so the same simulated time passes but the page hands the compositor half as many
  // frames (each one is a layer commit on the app's main thread). The moment the pointer or the digits move, it draws every frame.
  let busyUntil = 0;
  let skipped = 0;
  let onScreen = true;
  function frame(now = performance.now()) {
    if (!alive) return;
    frameId = requestAnimationFrame(frame);
    if (!simW || document.hidden || !onScreen || host.clientWidth < 2) return; // nothing to draw while hidden
    const calm = reducedMotion.matches;
    const lively = settle > 0 || drops.length > 0 || splat.active || now < busyUntil || now - mixStart < tune.morph + 100;
    if (!lively && !calm && skipped < 1) { skipped++; return; }
    const steps = (settle > 0 ? 8 : calm ? 0 : 3) * (1 + skipped);
    skipped = 0;
    for (let i = 0; i < steps; i++) step(calm ? null : drops.shift());
    if (calm) drops.length = 0;
    if (settle > 0) settle = Math.max(0, settle - steps);
    splat.active = false;
    splat.dx = splat.dy = 0;
    draw();
  }

  function pointer(event) {
    const rect = host.getBoundingClientRect();
    if (rect.width < 2 || rect.height < 2) return;
    const x = (event.clientX - rect.left) / rect.width;
    const y = 1 - (event.clientY - rect.top) / rect.height;
    if (x < -0.05 || x > 1.05 || y < -0.15 || y > 1.15) { last = null; lastDrop = null; return; }
    if (last) {
      splat.dx += x - last.x;
      splat.dy += y - last.y;
    }
    splat.x = x;
    splat.y = y;
    splat.active = true;
    busyUntil = performance.now() + 900; // droplets and ripples settle for a moment after the pointer leaves
    last = { x, y };
    // Drop a droplet each time the pointer has travelled far enough, so they stay separate beads instead of one line.
    const aspect = rect.width / rect.height;
    if (!lastDrop || Math.hypot((x - lastDrop.x) * aspect, y - lastDrop.y) > tune.spacing) {
      drops.push({ x: x + (Math.random() - 0.5) * 0.02, y: y + (Math.random() - 0.5) * 0.04 });
      if (drops.length > 12) drops.shift();
      lastDrop = { x, y };
    }
  }

  vao = gl.createVertexArray();
  velocity = program(VELOCITY);
  sim = program(SIM);
  render = program(RENDER);

  const resizeObserver = new ResizeObserver(() => { setup(); });
  resizeObserver.observe(host);
  // Nothing is drawn while the digits are scrolled out of view.
  const visibility = typeof IntersectionObserver === 'function'
    ? new IntersectionObserver(([entry]) => { onScreen = entry.isIntersecting; })
    : null;
  visibility?.observe(host);
  window.addEventListener('pointermove', pointer);

  // The digit shapes come from the page's font, so wait for it before drawing them.
  const family = fontSpec.split(',')[0].trim();
  (document.fonts?.load(`700 64px ${family}`) ?? Promise.resolve()).then(() => { setup(); }, () => { setup(); });
  frameId = requestAnimationFrame(frame);

  return {
    supported: true,
    update(next = {}) {
      const textChanged = next.text !== undefined && next.text !== props.text;
      Object.assign(props, next);
      if (textChanged && simW) drawMask();
    },
    destroy() {
      alive = false;
      cancelAnimationFrame(frameId);
      resizeObserver.disconnect();
      visibility?.disconnect();
      window.removeEventListener('pointermove', pointer);
      canvas.remove();
      fallback.remove();
    },
  };
}
