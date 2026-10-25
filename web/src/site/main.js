// Locken site: smooth scroll with spring physics, masked text reveals, and the liquid-glass 3D scenes.
import * as THREE from "three";
import { GLTFLoader } from "three/examples/jsm/loaders/GLTFLoader.js";
import { DRACOLoader } from "three/examples/jsm/loaders/DRACOLoader.js";
import { MeshoptDecoder } from "three/examples/jsm/libs/meshopt_decoder.module.js";
import gsap from "gsap";
import { ScrollTrigger } from "gsap/ScrollTrigger";
import { SplitText } from "gsap/SplitText";
import { CustomEase } from "gsap/CustomEase";
import Lenis from "lenis";
import "./connectors.jsx";

gsap.registerPlugin(ScrollTrigger, SplitText, CustomEase);
document.documentElement.classList.add("js", "site-ready");
if ("scrollRestoration" in history) history.scrollRestoration = "manual"; // the intro always starts at the top

const reduceMotion = window.matchMedia("(prefers-reduced-motion: reduce)").matches;

// Download buttons offer the visitor's own system: Windows gets the Windows installer, everyone else the Mac app
// (without JavaScript the buttons stay on the Mac app). The note under the last button names the other system.
(function initDownloads() {
  const platform = (navigator.userAgentData?.platform || navigator.platform || navigator.userAgent || "").toLowerCase();
  const isWindows = platform.includes("win");
  const mac = { href: "/Locken.dmg", label: "Download for Mac", note: "Free. Requires macOS 15 or later, on Apple silicon or Intel." };
  const windows = {
    href: "/Locken-Setup.exe",
    label: "Download for Windows",
    note: "Free. For Windows 10 or 11 (64-bit). Windows may say it doesn't recognise the app yet: choose More info, then Run anyway.",
  };
  const mine = isWindows ? windows : mac;
  const other = isWindows ? mac : windows;
  document.querySelectorAll("[data-download]").forEach((link) => {
    link.href = mine.href;
    link.firstChild.textContent = `${mine.label} `;
  });
  document.querySelectorAll("[data-download-plain]").forEach((link) => { link.href = mine.href; });
  document.querySelectorAll("[data-download-note]").forEach((note) => { note.textContent = mine.note; });
  document.querySelectorAll("[data-download-alt]").forEach((link) => {
    link.href = other.href;
    link.textContent = isWindows ? "Also for Mac" : "Also for Windows";
  });
})();

// The hero's "Start in three clicks" box: macOS / Windows tabs, opening on the visitor's own system.
{
  const tabs = [...document.querySelectorAll(".term-tabs [data-os]")];
  const select = (os) => {
    tabs.forEach((tab) => tab.setAttribute("aria-selected", String(tab.dataset.os === os)));
    document.querySelectorAll("[data-term]").forEach((line) => { line.hidden = line.dataset.term !== os; });
  };
  tabs.forEach((tab) => tab.addEventListener("click", () => select(tab.dataset.os)));
  if ((navigator.userAgentData?.platform || navigator.platform || "").toLowerCase().includes("win")) select("win");
}

// "silk": a soft in-out for scroll-linked moves, gentler at both ends than power curves.
CustomEase.create("silk", "M0,0 C0.62,0.02 0.3,1 1,1");

// ---------------------------------------------------------------------------------------------
// Motion core

/** A damped spring that follows `target`. Stiffness pulls it toward the target; damping settles it. */
class Spring {
  constructor(value, stiffness = 120, damping = 20) {
    this.value = value;
    this.target = value;
    this.velocity = 0;
    this.stiffness = stiffness;
    this.damping = damping;
  }

  step(dt) {
    if (reduceMotion) {
      this.value = this.target;
      this.velocity = 0;
      return this.value;
    }
    // Small fixed sub-steps keep it stable when a frame takes longer.
    for (let left = dt; left > 1e-6; left -= 1 / 240) {
      const h = Math.min(left, 1 / 240);
      this.velocity += (this.stiffness * (this.target - this.value) - this.damping * this.velocity) * h;
      this.value += this.velocity * h;
    }
    return this.value;
  }
}

/** Scroll speed, smoothed: about -1 (fast up) to 1 (fast down). The 3D scenes lean and stretch with it. */
const scrollSpeed = new Spring(0, 70, 16);
const pointer = { x: 0, y: 0 };

let lenis = null;
if (!reduceMotion) {
  lenis = new Lenis({ lerp: 0.085, smoothWheel: true, wheelMultiplier: 0.95, touchMultiplier: 1.1 });
  lenis.on("scroll", ScrollTrigger.update);
  window.addEventListener("pointermove", (event) => {
    pointer.x = event.clientX / window.innerWidth - 0.5;
    pointer.y = event.clientY / window.innerHeight - 0.5;
  }, { passive: true });
}

gsap.ticker.add((time, deltaMs) => {
  if (lenis) {
    lenis.raf(time * 1000);
    scrollSpeed.target = gsap.utils.clamp(-1, 1, lenis.velocity / 42);
  }
  scrollSpeed.step(Math.min(deltaMs / 1000, 0.05));
});
gsap.ticker.lagSmoothing(0);

// In-page links glide with an exponential ease-out; the header stays above the target.
const glide = (t) => (t >= 1 ? 1 : 1 - Math.pow(2, -10 * t));
document.querySelectorAll('a[href^="#"]').forEach((link) => {
  link.addEventListener("click", (event) => {
    const target = document.querySelector(link.getAttribute("href"));
    if (!target) return;
    event.preventDefault();
    if (lenis) lenis.scrollTo(target, { offset: -16, duration: 1.6, easing: glide });
    else target.scrollIntoView();
  });
});

// Phone menu: the nav links fold into a small panel behind a Menu button.
(function initMenu() {
  const pill = document.querySelector(".nav-pill");
  const toggle = document.querySelector(".nav-menu-toggle");
  if (!pill || !toggle) return;
  const setOpen = (open) => {
    pill.classList.toggle("is-open", open);
    toggle.setAttribute("aria-expanded", String(open));
    toggle.textContent = open ? "Close" : "Menu";
  };
  toggle.addEventListener("click", () => setOpen(!pill.classList.contains("is-open")));
  pill.querySelectorAll(".nav-links a").forEach((link) => link.addEventListener("click", () => setOpen(false)));
  document.addEventListener("keydown", (event) => { if (event.key === "Escape") setOpen(false); });
  document.addEventListener("click", (event) => { if (!pill.contains(event.target)) setOpen(false); });
})();

// ---------------------------------------------------------------------------------------------
// Page backdrop: lavender in the hero, night as Product arrives, black from Integrations. The same values
// drive the CSS layers and the glass shader, which rebuilds the backdrop so it can refract it.

const backdrop = { night: 0, black: 0 };
const nightLayer = document.querySelector(".backdrop-night");
const blackLayer = document.querySelector(".backdrop-black");
const paintBackdrop = () => {
  if (nightLayer) nightLayer.style.opacity = String(backdrop.night);
  if (blackLayer) blackLayer.style.opacity = String(backdrop.black);
};
gsap.to(backdrop, {
  night: 1, ease: "none", onUpdate: paintBackdrop,
  scrollTrigger: { trigger: ".session", start: "top 90%", end: "top 10%", scrub: true },
});
gsap.to(backdrop, {
  black: 1, ease: "none", onUpdate: paintBackdrop,
  scrollTrigger: { trigger: ".works", start: "top 80%", end: "top 10%", scrub: true },
});

// ---------------------------------------------------------------------------------------------
// Typewriter (Fancy Components' Typewriter): a list of features typed, held, deleted, then the next one.
// The full sentence stays in a screen-reader-only span; with Reduce Motion the static list stays as written.

function typewriter(el) {
  const items = el.dataset.type.split("|");
  const text = document.createElement("span");
  const cursor = document.createElement("span");
  cursor.className = "typewriter-cursor";
  cursor.textContent = "_";
  el.replaceChildren(text, cursor);
  let item = 0;
  let shown = 0;
  let deleting = false;
  const tick = () => {
    const word = items[item];
    shown += deleting ? -1 : 1;
    text.textContent = word.slice(0, shown);
    let wait = deleting ? 40 : 70;
    if (!deleting && shown === word.length) { deleting = true; wait = 1500; }
    else if (deleting && shown === 0) { deleting = false; item = (item + 1) % items.length; wait = 300; }
    setTimeout(tick, wait);
  };
  tick();
}
if (!reduceMotion) document.querySelectorAll(".typewriter[data-type]").forEach(typewriter);

// ---------------------------------------------------------------------------------------------
// Reveals: heading letters rise out of masks; copy and cards ease up; the product panel glides in.

function initReveals() {
  if (reduceMotion) {
    document.querySelectorAll("[data-split]").forEach((el) => el.classList.add("is-split"));
    return;
  }

  gsap.from(".nav", { autoAlpha: 0, y: -14, duration: 1.1, ease: "expo.out", delay: 0.15 });

  document.querySelectorAll("[data-split]").forEach((el) => {
    const inHero = Boolean(el.closest(".hero"));
    // Vertical cut reveal (Fancy Components' VerticalCutReveal): each letter rises out of its own mask, one after
    // another, on a spring (stiffness 200, damping 21: settles fast with a slight overshoot). Words stay whole for wrapping.
    SplitText.create(el, {
      type: "words,chars",
      wordsClass: "split-word",
      mask: "chars",
      autoSplit: true,
      onSplit(self) {
        el.classList.add("is-split");
        // Room under each letter so descenders aren't clipped by its mask.
        const masks = self.masks?.length ? self.masks : self.chars.map((char) => char.parentElement);
        masks.forEach((mask) => { mask.style.paddingBottom = "0.12em"; mask.style.marginBottom = "-0.12em"; });
        return gsap.from(self.chars, {
          yPercent: 110,
          duration: 0.9,
          ease: "back.out(1.1)",
          stagger: { each: 0.025, from: "start" },
          delay: inHero ? 0.35 : 0,
          scrollTrigger: inHero ? undefined : { trigger: el, start: "top 88%", once: true },
        });
      },
    });
  });

  let heroIndex = 0;
  gsap.utils.toArray("[data-reveal]").forEach((el) => {
    const inHero = Boolean(el.closest(".hero"));
    const from = { autoAlpha: 0, y: 28 };
    const to = { autoAlpha: 1, y: 0, duration: 1.2, ease: "expo.out" };
    if (el.classList.contains("eyebrow")) {
      from.letterSpacing = "0.6em";
      to.letterSpacing = "0.32em";
      to.duration = 1.5;
    }
    if (inHero) to.delay = 0.75 + heroIndex++ * 0.1;
    else to.scrollTrigger = { trigger: el, start: "top 90%", once: true };
    gsap.fromTo(el, from, to);
  });

  gsap.utils.toArray("[data-stagger]").forEach((group) => {
    gsap.fromTo(group.children, { autoAlpha: 0, y: 56, scale: 0.97 }, {
      autoAlpha: 1, y: 0, scale: 1, duration: 1.25, ease: "expo.out", stagger: 0.075,
      scrollTrigger: { trigger: group, start: "top 86%", once: true },
    });
  });

  // The product panel rises out from under the figure as you arrive.
  gsap.fromTo(".session-panel", { yPercent: 35, autoAlpha: 0.15 }, {
    yPercent: 0, autoAlpha: 1, ease: "silk",
    scrollTrigger: { trigger: ".session", start: "top 95%", end: "top 15%", scrub: true },
  });

  // Numbers count up when they come into view.
  document.querySelectorAll("[data-count]").forEach((el) => {
    const end = Number(el.dataset.count);
    const suffix = el.dataset.suffix || "";
    const counter = { value: 0 };
    el.textContent = `0${suffix}`;
    gsap.to(counter, {
      value: end, duration: 1.8, ease: "expo.out",
      onUpdate: () => { el.textContent = `${Math.round(counter.value)}${suffix}`; },
      scrollTrigger: { trigger: el, start: "top 88%", once: true },
    });
  });
}

initReveals();

// ---------------------------------------------------------------------------------------------
// 3D: shared pieces

const loader = new GLTFLoader();
const draco = new DRACOLoader();
draco.setDecoderPath("/draco/");
loader.setDRACOLoader(draco);
loader.setMeshoptDecoder(MeshoptDecoder);

function makeRenderer(canvas, maxPixelRatio) {
  // No canvas antialiasing: the scene renders into a multisampled target and only a full-screen quad hits the canvas.
  const renderer = new THREE.WebGLRenderer({ canvas, antialias: false, alpha: true, powerPreference: "high-performance" });
  renderer.setPixelRatio(Math.min(window.devicePixelRatio, maxPixelRatio));
  renderer.outputColorSpace = THREE.SRGBColorSpace;
  renderer.toneMapping = THREE.NeutralToneMapping; // keeps the violets true instead of shifting them
  renderer.toneMappingExposure = 1.0;
  return renderer;
}

/**
 * A studio for reflections: a violet dome with soft light panels (white key, lavender strip, cool cyan strip, a low
 * pink kick). Glass and chrome mirror these as long, clean highlights.
 */
function makeStudioEnvironment(renderer) {
  const studio = new THREE.Scene();
  const dome = new THREE.Mesh(
    new THREE.SphereGeometry(30, 48, 24),
    new THREE.ShaderMaterial({
      side: THREE.BackSide,
      depthWrite: false,
      vertexShader: "varying vec3 vDir; void main(){ vDir = normalize(position); gl_Position = projectionMatrix * modelViewMatrix * vec4(position, 1.0); }",
      fragmentShader: `
        varying vec3 vDir;
        void main() {
          float y = vDir.y;
          vec3 ground = vec3(0.012, 0.01, 0.035);
          vec3 horizon = vec3(0.15, 0.10, 0.40);
          vec3 zenith = vec3(0.40, 0.38, 0.82);
          vec3 c = y < 0.0 ? mix(horizon, ground, smoothstep(0.0, -0.6, y)) : mix(horizon, zenith, smoothstep(0.0, 0.9, y));
          gl_FragColor = vec4(c, 1.0);
        }`,
    }),
  );
  studio.add(dome);
  const panel = (width, height, hex, intensity, x, y, z) => {
    const mesh = new THREE.Mesh(
      new THREE.PlaneGeometry(width, height),
      new THREE.MeshBasicMaterial({ color: new THREE.Color(hex).multiplyScalar(intensity), side: THREE.DoubleSide }),
    );
    mesh.position.set(x, y, z);
    mesh.lookAt(0, 0, 0);
    studio.add(mesh);
  };
  panel(16, 4, 0xffffff, 7, -8, 12, 8);     // big soft key, top left, in front
  panel(3, 18, 0xc4b5ff, 5, 14, 2, 4);      // tall lavender strip, right
  panel(3, 14, 0x86c8ff, 3, -14, 0, -4);    // cool cyan strip, back left
  panel(10, 1.6, 0xff9ee3, 2.4, 3, -8, 10); // low warm pink, in front
  panel(22, 3, 0xffffff, 3.5, 0, 16, -10);  // overhead, behind
  const pmrem = new THREE.PMREMGenerator(renderer);
  const texture = pmrem.fromScene(studio, 0.025).texture;
  pmrem.dispose();
  studio.traverse((node) => { node.geometry?.dispose(); node.material?.dispose(); });
  return texture;
}

/** The CSS backdrop (radial gradients in sRGB, plus the night and black layers) rebuilt in GLSL. */
const BACKDROP_GLSL = /* glsl */ `
  uniform float uNight, uBlack;
  vec3 heroRamp(float t) {
    vec3 a = vec3(0.306, 0.290, 0.722), b = vec3(0.184, 0.165, 0.525), c = vec3(0.094, 0.078, 0.310), d = vec3(0.039, 0.031, 0.125);
    if (t < 0.32) return mix(a, b, t / 0.32);
    if (t < 0.66) return mix(b, c, (t - 0.32) / 0.34);
    return mix(c, d, clamp((t - 0.66) / 0.34, 0.0, 1.0));
  }
  vec3 nightRamp(float t) {
    vec3 a = vec3(0.114, 0.114, 0.259), b = vec3(0.047, 0.043, 0.114), c = vec3(0.020, 0.016, 0.035);
    if (t < 0.55) return mix(a, b, t / 0.55);
    return mix(b, c, clamp((t - 0.55) / 0.45, 0.0, 1.0));
  }
  vec3 pageBackdrop(vec2 uv) {
    uv = clamp(uv, 0.0, 1.0);
    vec2 p = vec2(uv.x, 1.0 - uv.y);
    vec3 c = heroRamp(length((p - vec2(0.62, 0.42)) / vec2(0.70)));
    c = mix(c, nightRamp(length((p - vec2(0.60, 0.30)) / vec2(0.90, 0.80))), uNight);
    c = mix(c, vec3(0.027, 0.024, 0.051), uBlack);
    return pow(c, vec3(2.2));
  }`;

/**
 * Liquid glass: almost no diffuse colour, so what you see is the page behind it bent by refraction (split slightly
 * per colour channel), tinted deeper violet where the glass is thicker, plus studio reflections, clearcoat,
 * thin-film iridescence and a rim of light. The refraction ripples gently, more when you scroll fast.
 */
function makeLiquidGlass({ env, tintCore, tintEdge, refract = 0.1, emissive = 0x7a5cff, emissiveIntensity = 0.3 }) {
  const material = new THREE.MeshPhysicalMaterial({
    color: 0x07060d,
    metalness: 0,
    roughness: 0.2,
    envMap: env,
    envMapIntensity: 1.35,
    clearcoat: 1,
    clearcoatRoughness: 0.14,
    iridescence: 0.9,
    iridescenceIOR: 1.32,
    iridescenceThicknessRange: [160, 520],
    specularIntensity: 1,
    ior: 1.5,
    emissive: new THREE.Color(emissive),
    emissiveIntensity,
  });
  const uniforms = {
    uResolution: { value: new THREE.Vector2(1, 1) },
    uTime: { value: 0 },
    uLiquid: { value: 1 },
    uNight: { value: 0 },
    uBlack: { value: 0 },
    uIor: { value: 1.33 },
    uRefract: { value: refract },
    uTintCore: { value: new THREE.Color(tintCore) },
    uTintEdge: { value: new THREE.Color(tintEdge) },
    uRimColor: { value: new THREE.Color(0xd9d2ff) },
    uRim: { value: 0.55 },
  };
  material.onBeforeCompile = (shader) => {
    Object.assign(shader.uniforms, uniforms);
    shader.fragmentShader = shader.fragmentShader
      .replace("void main() {", `
        uniform vec2 uResolution;
        uniform float uTime, uLiquid, uIor, uRefract, uRim;
        uniform vec3 uTintCore, uTintEdge, uRimColor;
        ${BACKDROP_GLSL}
        void main() {`)
      .replace("#include <opaque_fragment>", `
        {
          vec3 V = normalize( vViewPosition );
          vec3 N = normalize( normal );
          float facing = clamp( dot( N, V ), 0.0, 1.0 );
          vec2 screenUv = gl_FragCoord.xy / uResolution;
          vec3 bend = refract( -V, N, 1.0 / uIor );
          vec2 shift = bend.xy * uRefract * ( 0.35 + 0.65 * ( 1.0 - facing ) );
          // A slow ripple through the glass, like liquid moving inside it.
          shift += vec2( sin( screenUv.y * 38.0 + uTime * 1.7 ), cos( screenUv.x * 31.0 - uTime * 1.3 ) ) * 0.0035 * uLiquid;
          vec3 behind = vec3(
            pageBackdrop( screenUv + shift * 1.12 ).r,
            pageBackdrop( screenUv + shift ).g,
            pageBackdrop( screenUv + shift * 0.88 ).b );
          float thickness = pow( 1.0 - facing, 1.1 );
          outgoingLight += behind * mix( uTintCore, uTintEdge, thickness );
          outgoingLight += uRimColor * pow( 1.0 - facing, 3.2 ) * uRim;
        }
        #include <opaque_fragment>`);
  };
  material.customProgramCacheKey = () => "locken-liquid-glass";
  return { material, uniforms };
}

/**
 * The finishing pass over the 3D scene: thin liquid drips that grow and shrink smoothly and taper to a point (bright
 * parts drip most, mostly downward), a soft glow around the brightest highlights, faint lens fringing toward the
 * screen edges, then tone mapping and sRGB output.
 */
function makeLiquidPass(renderer, { columns = 120, reach = 0.24, glow = 1, aberration = 0.003, rise = 0.28 } = {}) {
  // Mipmapped so the glow can read a pre-blurred copy of the scene.
  const target = new THREE.WebGLRenderTarget(2, 2, {
    type: THREE.HalfFloatType, samples: 4, generateMipmaps: true, minFilter: THREE.LinearMipmapLinearFilter,
  });
  const uniforms = {
    tScene: { value: target.texture },
    uTexel: { value: new THREE.Vector2(1, 1) },
    uTime: { value: 0 },
    uColumns: { value: columns },
    uReach: { value: reduceMotion ? reach * 0.35 : reach },
    uFlow: { value: 1 },
    uGlow: { value: glow },
    uAberration: { value: aberration },
    uRise: { value: rise },
    uGlitch: { value: 0 },
  };
  const material = new THREE.ShaderMaterial({
    uniforms,
    depthTest: false,
    depthWrite: false,
    blending: THREE.CustomBlending,
    blendSrc: THREE.OneFactor,
    blendDst: THREE.OneMinusSrcAlphaFactor,
    vertexShader: "varying vec2 vUv; void main(){ vUv = uv; gl_Position = vec4(position.xy, 0.0, 1.0); }",
    fragmentShader: /* glsl */ `
      precision highp float;
      varying vec2 vUv;
      uniform sampler2D tScene;
      uniform vec2 uTexel;
      uniform float uTime, uColumns, uReach, uFlow, uGlow, uAberration, uRise, uGlitch;
      float hash(float n) { return fract(sin(n * 91.3458) * 47453.5453); }
      float smoothNoise(float x) { float i = floor(x); float f = fract(x); f = f * f * (3.0 - 2.0 * f); return mix(hash(i), hash(i + 1.0), f); }
      float luma(vec3 c) { return dot(c, vec3(0.2126, 0.7152, 0.0722)); }
      void main() {
        // Glitch (only while uGlitch > 0): random horizontal bands jump sideways and turn blocky, colours split.
        vec2 uv = vUv;
        if (uGlitch > 0.001) {
          float tick = floor(uTime * 24.0);
          float band = floor(vUv.y * 42.0);
          float pick = step(1.0 - uGlitch * 0.35, hash(band * 1.7 + tick * 3.1));
          uv.x += (hash(band + tick * 7.3) - 0.5) * 0.03 * uGlitch * pick;
          uv.x = mix(uv.x, floor(uv.x * 140.0) / 140.0, pick);
        }
        vec2 fringe = (vUv - 0.5) * uAberration + vec2(0.003 * uGlitch, 0.0);
        vec4 body = texture2D(tScene, uv);
        body.r = texture2D(tScene, uv + fringe).r;
        body.b = texture2D(tScene, uv - fringe).b;
        body.rgb = min(body.rgb, vec3(2.5) * max(body.a, 1e-3)); // no single over-bright pixel (fireflies)

        float columnX = vUv.x * uColumns;
        float column = floor(columnX);
        float across = abs(fract(columnX) - 0.5);
        float seed = hash(column);
        float dir = seed > uRise ? 1.0 : -1.0;
        float len = pow(smoothNoise(uTime * (0.18 + seed * 0.42) + seed * 37.0), 2.6) * uReach * uFlow * (0.5 + hash(column * 7.13));
        float centerX = (column + 0.5) / uColumns;
        vec3 dripColor = vec3(0.0);
        float drip = 0.0;
        for (int i = 1; i <= 28; i++) {
          float t = pow(float(i) / 28.0, 1.35); // taps packed near the body, sparser toward the thin tip
          vec4 s = texture2D(tScene, vec2(centerX, vUv.y + dir * len * t));
          float width = mix(0.44, 0.08, t);
          float inside = 1.0 - smoothstep(width - 0.06, width, across);
          float k = s.a * smoothstep(0.06, 0.5, luma(s.rgb / max(s.a, 1e-3))) * inside * pow(1.0 - t, 1.3);
          if (k > drip) { drip = k; dripColor = s.rgb / max(s.a, 1e-3); }
        }

        // A soft halo from blurred (mipmapped) copies of the scene: only the brightest highlights bleed.
        vec3 glow = max(texture2D(tScene, vUv, 3.0).rgb - 0.55, 0.0) * 0.55
                  + max(texture2D(tScene, vUv, 5.0).rgb - 0.45, 0.0) * 0.45;
        glow *= uGlow;

        float dripAlpha = drip * 0.9 * (1.0 - body.a);
        vec3 color = body.rgb + dripColor * dripAlpha + glow;
        float alpha = body.a + dripAlpha;
        float glowAlpha = clamp(max(glow.r, max(glow.g, glow.b)), 0.0, 1.0);
        alpha = clamp(alpha + glowAlpha * (1.0 - alpha), 0.0, 1.0);

        gl_FragColor = vec4(color / max(alpha, 1e-4), alpha);
        #include <tonemapping_fragment>
        #include <colorspace_fragment>
        gl_FragColor.rgb *= gl_FragColor.a;
      }`,
  });
  const quadScene = new THREE.Scene();
  quadScene.add(new THREE.Mesh(new THREE.PlaneGeometry(2, 2), material));
  const quadCamera = new THREE.OrthographicCamera(-1, 1, 1, -1, 0, 1);
  return {
    uniforms,
    /** Sizes the target to the canvas; returns its pixel size (what gl_FragCoord measures). */
    setSize(width, height) {
      const ratio = renderer.getPixelRatio();
      const w = Math.max(1, Math.floor(width * ratio));
      const h = Math.max(1, Math.floor(height * ratio));
      target.setSize(w, h);
      uniforms.uTexel.value.set(1 / w, 1 / h);
      return new THREE.Vector2(w, h);
    },
    render(scene, camera, time) {
      uniforms.uTime.value = time;
      renderer.setRenderTarget(target);
      renderer.setClearColor(0x000000, 0);
      renderer.render(scene, camera);
      renderer.setRenderTarget(null);
      renderer.render(quadScene, quadCamera);
    },
  };
}

/**
 * Smooth shading for the low-poly body: every vertex gets the area-weighted average of the faces around its position,
 * so seams and facets read as one continuous surface (matters for glass, where normals steer the refraction).
 */
function smoothNormals(geometry) {
  const position = geometry.getAttribute("position");
  const original = geometry.getAttribute("normal");
  const index = geometry.getIndex();
  const count = position.count;
  const keys = new Array(count);
  for (let i = 0; i < count; i++) {
    keys[i] = `${Math.round(position.getX(i) * 1e4)},${Math.round(position.getY(i) * 1e4)},${Math.round(position.getZ(i) * 1e4)}`;
  }
  const sums = new Map();
  const a = new THREE.Vector3(), b = new THREE.Vector3(), c = new THREE.Vector3();
  const ab = new THREE.Vector3(), ac = new THREE.Vector3(), n = new THREE.Vector3();
  const triangles = (index ? index.count : count) / 3;
  for (let t = 0; t < triangles; t++) {
    const ia = index ? index.getX(t * 3) : t * 3;
    const ib = index ? index.getX(t * 3 + 1) : t * 3 + 1;
    const ic = index ? index.getX(t * 3 + 2) : t * 3 + 2;
    a.fromBufferAttribute(position, ia);
    b.fromBufferAttribute(position, ib);
    c.fromBufferAttribute(position, ic);
    n.crossVectors(ab.subVectors(b, a), ac.subVectors(c, a));
    for (const i of [ia, ib, ic]) {
      const sum = sums.get(keys[i]);
      if (sum) sum.add(n);
      else sums.set(keys[i], n.clone());
    }
  }
  const normals = new Float32Array(count * 3);
  const before = new THREE.Vector3();
  for (let i = 0; i < count; i++) {
    const sum = sums.get(keys[i]);
    if (!sum || sum.lengthSq() === 0) continue;
    n.copy(sum).normalize();
    if (original) {
      before.fromBufferAttribute(original, i);
      if (before.dot(n) < 0) n.negate(); // keep the authored facing
    }
    normals[i * 3] = n.x;
    normals[i * 3 + 1] = n.y;
    normals[i * 3 + 2] = n.z;
  }
  geometry.setAttribute("normal", new THREE.BufferAttribute(normals, 3));
}

/**
 * Turns the figure's own head into the Locken padlock. The head gets a morph target: its vertices slide onto a
 * rounded lock body (a superellipsoid sized to the head), blending into the neck so it stays one piece. A glass
 * metal shackle grows out of the top of the skull and a keyhole fades in. Drive it with `setLock(amount)`, 0 to 1.
 */
function makeHeadLock(headMesh, headIndices, cutY, material, shackleMaterial = material) {
  const geometry = headMesh.geometry;
  const position = geometry.getAttribute("position");
  const normal = geometry.getAttribute("normal");
  const used = new Set(headIndices);
  const box = new THREE.Box3();
  const v = new THREE.Vector3();
  for (const i of used) box.expandByPoint(v.fromBufferAttribute(position, i));
  const size = box.getSize(new THREE.Vector3());
  const center = box.getCenter(new THREE.Vector3());
  const headHeight = box.max.y - cutY;

  // The lock body takes the lower half of the head (face and jaw); the shackle takes the skull above it, so the
  // whole padlock has the head's own outline.
  const half = new THREE.Vector3(size.x * 0.5, headHeight * 0.24, size.z * 0.4);
  const bodyCenter = new THREE.Vector3(center.x, cutY + headHeight * 0.14 + half.y, center.z + size.z * 0.04);
  const power = 16; // higher = boxier, lower = rounder; 16 gives a real padlock body with small rounded edges
  const morphPositions = new Float32Array(position.array.length);
  const morphNormals = new Float32Array(position.array.length);
  const n = new THREE.Vector3();
  for (let i = 0; i < position.count; i++) {
    v.fromBufferAttribute(position, i);
    n.fromBufferAttribute(normal, i);
    if (!used.has(i)) {
      v.toArray(morphPositions, i * 3);
      n.toArray(morphNormals, i * 3);
      continue;
    }
    const d = v.clone().sub(bodyCenter);
    const q = new THREE.Vector3(d.x / half.x, d.y / half.y, d.z / half.z);
    const norm = Math.pow(Math.abs(q.x) ** power + Math.abs(q.y) ** power + Math.abs(q.z) ** power, 1 / power) || 1;
    const target = bodyCenter.clone().add(d.divideScalar(norm));
    const t = new THREE.Vector3(
      Math.sign(q.x) * Math.abs(q.x / norm) ** (power - 1) / half.x,
      Math.sign(q.y) * Math.abs(q.y / norm) ** (power - 1) / half.y,
      Math.sign(q.z) * Math.abs(q.z / norm) ** (power - 1) / half.z,
    ).normalize();
    // Vertices near the cut stay on the neck, so the lock grows out of the body instead of floating.
    const w = THREE.MathUtils.smoothstep(v.y, cutY, cutY + headHeight * 0.2);
    v.lerp(target, w).toArray(morphPositions, i * 3);
    n.lerp(t, w).normalize().toArray(morphNormals, i * 3);
  }
  geometry.morphAttributes.position = [new THREE.BufferAttribute(morphPositions, 3)];
  geometry.morphAttributes.normal = [new THREE.BufferAttribute(morphNormals, 3)];
  headMesh.updateMorphTargets();

  // The shackle: a glass arch whose legs sink into the top of the lock body.
  const archRadius = half.x * 0.58;
  const tube = half.x * 0.15;
  const shackle = new THREE.Group();
  const arch = new THREE.Mesh(new THREE.TorusGeometry(archRadius, tube, 24, 64, Math.PI), shackleMaterial);
  arch.position.y = half.y * 0.7;
  const legGeometry = new THREE.CylinderGeometry(tube, tube, half.y * 0.7, 24);
  legGeometry.translate(0, half.y * 0.35, 0);
  const left = new THREE.Mesh(legGeometry, shackleMaterial);
  left.position.x = -archRadius;
  const right = new THREE.Mesh(legGeometry, shackleMaterial);
  right.position.x = archRadius;
  shackle.add(arch, left, right);
  shackle.position.set(bodyCenter.x, bodyCenter.y + half.y * 0.75, bodyCenter.z);
  headMesh.add(shackle);

  // The keyhole, on the front of the lock body.
  const ink = new THREE.MeshBasicMaterial({ color: 0x05040c, transparent: true, opacity: 0, depthWrite: false });
  const keyhole = new THREE.Group();
  const hole = new THREE.Mesh(new THREE.CircleGeometry(half.x * 0.16, 32), ink);
  hole.position.y = half.y * 0.12;
  const slot = new THREE.Mesh(new THREE.PlaneGeometry(half.x * 0.12, half.y * 0.42), ink);
  slot.position.y = -half.y * 0.18;
  keyhole.add(hole, slot);
  keyhole.position.set(bodyCenter.x, bodyCenter.y - half.y * 0.1, bodyCenter.z + half.z * 1.01);
  headMesh.add(keyhole);

  const basePosition = headMesh.position.clone();
  return {
    setLock(amount, jolt = 0) {
      headMesh.morphTargetInfluences[0] = amount;
      const grow = THREE.MathUtils.smoothstep(amount, 0.45, 1);
      shackle.visible = grow > 0.001;
      shackle.scale.set(1, Math.max(grow, 1e-3), 1);
      ink.opacity = THREE.MathUtils.smoothstep(amount, 0.7, 1);
      headMesh.position.set(basePosition.x + jolt, basePosition.y, basePosition.z);
    },
  };
}

const loadModel = (url) => new Promise((resolve, reject) => loader.load(url, resolve, undefined, reject));

/** The figure: Blender Studio's "Human Base Meshes" realistic male body (CC0), exported by us. */
const FIGURE_URL = "/models/locken-figure.glb";

/**
 * The chrome ring, built in code: 1.3 units across with a slim round band, lying in the XY plane.
 */
function makeRing(material) {
  return new THREE.Mesh(new THREE.TorusGeometry(0.617, 0.032, 48, 256), material);
}

/**
 * Splits a body mesh at the neck into body and head meshes that share the same vertices and normals, so there is
 * no visible seam, and the head can be hidden on its own. `neck` is the cut height as a fraction of the body's
 * height. Returns the head mesh (added next to the body) and the cut and top heights in the mesh's local space.
 */
function splitHead(mesh, neck = 0.88) {
  const geometry = mesh.geometry;
  geometry.computeBoundingBox();
  const { min, max } = geometry.boundingBox;
  const cutY = min.y + (max.y - min.y) * neck;
  const position = geometry.getAttribute("position");
  const index = geometry.getIndex();
  const count = index ? index.count : position.count;
  const vertex = (i) => (index ? index.getX(i) : i);
  const bodyIndices = [];
  const headIndices = [];
  for (let i = 0; i < count; i += 3) {
    const a = vertex(i), b = vertex(i + 1), c = vertex(i + 2);
    const centerY = (position.getY(a) + position.getY(b) + position.getY(c)) / 3;
    (centerY > cutY ? headIndices : bodyIndices).push(a, b, c);
  }
  const part = (indices) => {
    const g = new THREE.BufferGeometry();
    for (const [name, attribute] of Object.entries(geometry.attributes)) g.setAttribute(name, attribute);
    g.setIndex(indices);
    g.computeBoundingBox();
    g.computeBoundingSphere();
    return g;
  };
  mesh.geometry = part(bodyIndices);
  const head = new THREE.Mesh(part(headIndices), mesh.material);
  head.frustumCulled = false;
  head.position.copy(mesh.position);
  head.quaternion.copy(mesh.quaternion);
  head.scale.copy(mesh.scale);
  mesh.parent.add(head);
  return { head, headIndices, cutY, topY: max.y };
}

/**
 * The closing scene: a dark-glass figure stands inside the spinning chrome ring, and every few seconds its head
 * glitches into the Locken padlock and back (flicker, jolts and screen-slice glitch). It rises into place as the
 * section scrolls in, turns gently with the pointer, and the ring spins with scroll speed.
 */
function initFinale() {
  const canvas = document.getElementById("ring2");
  if (!canvas) return;
  const renderer = makeRenderer(canvas, 1.75);
  const scene = new THREE.Scene();
  const camera = new THREE.PerspectiveCamera(32, 1, 0.01, 100);
  const env = makeStudioEnvironment(renderer);
  scene.environment = env;
  const key = new THREE.DirectionalLight(0xffffff, 2.2);
  key.position.set(-2, 3, 4);
  const rim = new THREE.DirectionalLight(0xa58cff, 3);
  rim.position.set(2.5, 1.5, -3);
  scene.add(key, rim);

  const stage = new THREE.Group(); // shifted right on wide screens, clear of the headline
  scene.add(stage);
  const ringSpin = new THREE.Group();
  const ringTilt = new THREE.Group();
  ringSpin.add(ringTilt);
  const rig = new THREE.Group();
  stage.add(ringSpin, rig);

  const glass = makeLiquidGlass({ env, tintCore: 0xffffff, tintEdge: 0x5a3cff, emissive: 0x4b2fd9, emissiveIntensity: 0.14, refract: 0.12 });
  glass.uniforms.uNight.value = 1;
  glass.uniforms.uBlack.value = 1; // this section's backdrop is black
  glass.uniforms.uRim.value = 0.9;
  const chrome = new THREE.MeshPhysicalMaterial({
    color: 0xd9d0ff, metalness: 1, roughness: 0.12, envMapIntensity: 1.5, clearcoat: 1, clearcoatRoughness: 0.03,
    iridescence: 1, iridescenceIOR: 1.4, iridescenceThicknessRange: [200, 600],
    emissive: new THREE.Color(0x6d4dff), emissiveIntensity: 0.55, side: THREE.DoubleSide,
  });
  const pass = makeLiquidPass(renderer, { columns: 160, reach: 0.2, glow: 1.2 });

  const HEIGHT = 3; // figure height in scene units; the ring sits around the chest
  let headSplit = null;
  let ready = false;
  let onScreen = false;
  const enter = { value: 0 }; // 0 → 1 as the section scrolls in
  const rise = new Spring(-0.25, 55, 13);
  const tilt = new Spring(-1.42, 60, 14);
  const spinSpeed = new Spring(0.25, 30, 10);
  const lookX = new Spring(0, 40, 11);
  let spin = 0;

  loadModel(FIGURE_URL)
    .then((human) => {
      const figure = human.scene;
      let body = null;
      figure.traverse((node) => {
        if (node.isMesh) {
          smoothNormals(node.geometry);
          node.material = glass.material;
          node.frustumCulled = false;
          body = body || node;
        }
      });
      if (body) {
        const split = splitHead(body);
        headSplit = makeHeadLock(split.head, split.headIndices, split.cutY, glass.material, chrome);
      }
      const box = new THREE.Box3().setFromObject(figure);
      const size = box.getSize(new THREE.Vector3());
      figure.scale.setScalar(HEIGHT / size.y);
      box.setFromObject(figure);
      figure.position.set(-box.getCenter(new THREE.Vector3()).x, -box.min.y - HEIGHT * 0.7, -box.getCenter(new THREE.Vector3()).z);
      rig.add(figure);

      ringTilt.add(makeRing(chrome));
      ringTilt.scale.setScalar(1.25);

      resize();
      ready = true;
    });

  function resize() {
    const rect = canvas.getBoundingClientRect();
    renderer.setSize(rect.width, rect.height, false);
    glass.uniforms.uResolution.value.copy(pass.setSize(rect.width, rect.height));
    camera.aspect = rect.width / Math.max(rect.height, 1);
    const wide = camera.aspect >= 1;
    const visible = HEIGHT * (wide ? 0.95 : 1.15); // knees up to above the head
    const distance = visible / 2 / Math.tan(THREE.MathUtils.degToRad(camera.fov / 2));
    camera.position.set(0, 0.55, distance);
    camera.lookAt(0, -0.1, 0);
    camera.updateProjectionMatrix();
    const visibleWidth = visible * camera.aspect;
    stage.position.set(wide ? visibleWidth * 0.16 : 0, wide ? 0 : -0.25, 0);
  }
  resize();
  window.addEventListener("resize", resize);
  new IntersectionObserver(([entry]) => { onScreen = entry.isIntersecting; }).observe(canvas);
  gsap.to(enter, { value: 1, ease: "none", scrollTrigger: { trigger: ".cta", start: "top 85%", end: "top 15%", scrub: true } });

  // Head ↔ lock: 4.5 s head, 0.4 s glitch, 1.5 s lock, 0.4 s glitch, repeat.
  const hash = (n) => { const x = Math.sin(n * 91.3458) * 47453.5453; return x - Math.floor(x); };
  function headState(time) {
    if (reduceMotion) return { lock: 0, glitch: 0 };
    const phases = [4.5, 0.55, 1.6, 0.55];
    let t = time % phases.reduce((a, b) => a + b, 0);
    let phase = 0;
    while (t > phases[phase]) { t -= phases[phase]; phase++; }
    const progress = t / phases[phase];
    if (phase === 0) return { lock: 0, glitch: 0 };
    if (phase === 2) return { lock: 1, glitch: 0 };
    const eased = progress * progress * (3 - 2 * progress);
    const towardLock = phase === 1 ? eased : 1 - eased;
    const glitch = Math.sin(progress * Math.PI);
    // The morph stutters a little on the way, like a glitch, but always settles.
    const stutter = (hash(Math.floor(time * 24)) - 0.5) * 0.35 * glitch;
    return { lock: THREE.MathUtils.clamp(towardLock + stutter, 0, 1), glitch };
  }

  const clock = new THREE.Clock();
  renderer.setAnimationLoop(() => {
    const dt = Math.min(clock.getDelta(), 0.05);
    const time = clock.elapsedTime;
    if (!ready || !onScreen || document.hidden) return;
    const speed = scrollSpeed.value;

    rise.target = (1 - enter.value) * -0.25;
    tilt.target = -1.42 + (1 - enter.value) * 0.25;
    spinSpeed.target = reduceMotion ? 0 : 0.25 + speed * 1.6;
    lookX.target = pointer.x;
    rise.step(dt); tilt.step(dt); lookX.step(dt);
    spin += spinSpeed.step(dt) * dt;
    rig.position.y = rise.value * HEIGHT;
    rig.rotation.y = Math.sin(time * 0.35) * 0.18 + lookX.value * 0.5;
    ringTilt.rotation.x = tilt.value;
    ringSpin.rotation.y = spin;
    ringSpin.position.y = rise.value * HEIGHT * 0.4;

    const state = headState(time);
    if (headSplit) {
      const jolt = state.glitch > 0 ? (hash(Math.floor(time * 30)) - 0.5) * 0.02 * state.glitch : 0;
      headSplit.setLock(state.lock, jolt);
    }

    pass.uniforms.uGlitch.value = state.glitch;
    pass.uniforms.uFlow.value = 1 + Math.abs(speed) * 1.6 + state.glitch * 1.5;
    pass.render(scene, camera, time);
    if ((frame += 1) % 2 === 0) ascii.draw();
  });
  const ascii = makeAscii(canvas);
  let frame = 0;
}

// ---------------------------------------------------------------------------------------------
// The figure: idles behind the first three sections, glides between framings on springs as you scroll, leans
// and stretches a little with scroll speed, follows the pointer, and fades before Features.

function initFigure() {
  const canvas = document.getElementById("figure");
  if (!canvas) return;
  const renderer = makeRenderer(canvas, 1);
  const scene = new THREE.Scene();
  const camera = new THREE.PerspectiveCamera(30, 1, 0.01, 100);
  scene.environment = makeStudioEnvironment(renderer);
  const asciiPre = document.getElementById("figure-ascii");
  const ascii = makeAscii(canvas, asciiPre);

  const key = new THREE.DirectionalLight(0xffffff, 2.4);
  key.position.set(-2, 3, 4);
  const rim = new THREE.DirectionalLight(0xa58cff, 3.2);
  rim.position.set(3, 1.5, -3);
  const sweep = new THREE.DirectionalLight(0xeee6ff, 1.6); // travels around the figure with scroll
  scene.add(key, rim, sweep);

  const glass = makeLiquidGlass({
    env: scene.environment, tintCore: 0xdcd6ff, tintEdge: 0x6440ff, emissive: 0x5a3cff, emissiveIntensity: 0.05, refract: 0.15,
  });
  const pass = makeLiquidPass(renderer, { columns: 92, reach: 0.26, glow: 0.9, rise: 0.45 });

  const rig = new THREE.Group();
  scene.add(rig);
  let mixer = null;
  let height = 1.8;
  let ready = false;
  const intro = { opacity: 0 };

  // Scroll targets (scrubbed) and the springs that chase them. The springs start below and turned away, so the
  // figure arrives on load with a real settle.
  const target = { x: 0.1, y: 0, scale: 1, turn: -0.55, sweep: 0, fade: 1 };
  const springs = {
    x: new Spring(0.1, 70, 15),
    y: new Spring(-0.24, 60, 14),
    scale: new Spring(0.9, 90, 17),
    turn: new Spring(-1.15, 45, 11),
    lookX: new Spring(0, 40, 11),
    lookY: new Spring(0, 40, 11),
  };

  loader.load(FIGURE_URL, (gltf) => {
    const model = gltf.scene;
    model.traverse((node) => {
      if (!node.isMesh) return;
      smoothNormals(node.geometry);
      node.material = glass.material;
      node.frustumCulled = false;
    });
    const box = new THREE.Box3().setFromObject(model);
    height = box.getSize(new THREE.Vector3()).y;
    model.position.sub(box.getCenter(new THREE.Vector3()));
    rig.add(model);
    if (gltf.animations.length && !reduceMotion) {
      mixer = new THREE.AnimationMixer(model);
      mixer.clipAction(gltf.animations[0]).play();
    }
    resize();
    ready = true;
    gsap.to(intro, { opacity: 1, duration: 1.4, ease: "power2.out" });
  });

  function resize() {
    const width = window.innerWidth;
    const heightPx = window.innerHeight;
    renderer.setSize(width, heightPx, false);
    glass.uniforms.uResolution.value.copy(pass.setSize(width, heightPx));
    camera.aspect = width / heightPx;
    const focusY = height * 0.36;
    const distance = height * (camera.aspect < 0.9 ? 1.5 : 0.8);
    camera.position.set(0, focusY, distance);
    camera.lookAt(0, focusY - height * 0.04, 0);
    camera.updateProjectionMatrix();
  }
  resize();
  window.addEventListener("resize", resize);

  gsap.timeline({
    scrollTrigger: { trigger: ".hero", start: "top top", endTrigger: ".works", end: "bottom top", scrub: true },
  })
    .to(target, { x: 0, y: 0.05, scale: 0.8, turn: 0.18, sweep: 0.5, ease: "silk" })  // into Product
    .to(target, { x: 0.3, y: 0.02, scale: 0.58, turn: 0.72, sweep: 1, ease: "silk" }); // into Integrations
  gsap.to(target, {
    fade: 0, ease: "power2.in",
    scrollTrigger: { trigger: ".features", start: "top bottom", end: "top 45%", scrub: true },
  });

  const clock = new THREE.Clock();
  renderer.setAnimationLoop(() => {
    const dt = Math.min(clock.getDelta(), 0.05);
    const time = clock.elapsedTime;
    const opacity = intro.opacity * target.fade;
    asciiPre.style.opacity = String(opacity);
    if (!ready || document.hidden || opacity <= 0.001) return;

    if (mixer) mixer.update(dt);
    const speed = scrollSpeed.value;
    const rush = Math.abs(speed);
    springs.x.target = target.x;
    springs.y.target = target.y;
    springs.scale.target = target.scale;
    springs.turn.target = target.turn;
    springs.lookX.target = pointer.x;
    springs.lookY.target = pointer.y;
    for (const spring of Object.values(springs)) spring.step(dt);

    const wide = camera.aspect >= 0.9 ? 1 : 0;
    const breathe = reduceMotion ? 0 : Math.sin(time * 0.9) * 0.006;
    const s = springs.scale.value;
    rig.position.set(springs.x.value * height * wide, (springs.y.value + breathe - speed * 0.035) * height, 0);
    rig.scale.set(s * (1 - rush * 0.025), s * (1 + rush * 0.05), s * (1 - rush * 0.025)); // stretches like liquid
    rig.rotation.set(speed * 0.16 + springs.lookY.value * 0.12, springs.turn.value + springs.lookX.value * 0.35, 0);

    const angle = target.sweep * Math.PI * 1.2 - 0.6 + time * 0.08;
    sweep.position.set(Math.cos(angle) * 4, 2.2, Math.sin(angle) * 4 + 1.5);

    glass.uniforms.uTime.value = time;
    glass.uniforms.uLiquid.value = 1 + rush * 2.5;
    glass.uniforms.uNight.value = backdrop.night;
    glass.uniforms.uBlack.value = backdrop.black;
    pass.uniforms.uFlow.value = 1 + rush * 1.8;
    pass.render(scene, camera, time);
    if ((frame += 1) % 2 === 0) ascii.draw(); // half rate is plenty for text
  });
  let frame = 0;
}

/** A <pre> laid exactly over `canvas` (same box), which then hides the canvas itself. */
function asciiLayerFor(canvas) {
  const pre = document.createElement("pre");
  pre.className = "ascii-layer";
  pre.setAttribute("aria-hidden", "true");
  canvas.after(pre);
  canvas.classList.add("ascii-source");
  return pre;
}

/**
 * Shows a WebGL canvas as ASCII (Hermes-style): the frame is shrunk to one pixel per character and each pixel's
 * brightness picks a character. Deliberately low detail. The WebGL canvas stays in the page but invisible.
 */
function makeAscii(canvas, pre = asciiLayerFor(canvas)) {
  const RAMP = " .:-=+*#%@";
  const CELL_W = 7.2; // px per character across (a 12px monospace character, matching .figure-ascii)
  const CELL_H = 12; // px per line
  const small = document.createElement("canvas");
  const context = small.getContext("2d", { willReadFrequently: true });
  return {
    draw() {
      const cols = Math.ceil(canvas.clientWidth / CELL_W);
      const rows = Math.ceil(canvas.clientHeight / CELL_H);
      if (!cols || !rows) return;
      if (small.width !== cols || small.height !== rows) { small.width = cols; small.height = rows; }
      context.fillStyle = "#000";
      context.fillRect(0, 0, cols, rows);
      context.drawImage(canvas, 0, 0, cols, rows); // must run right after the WebGL render, in the same frame
      const { data } = context.getImageData(0, 0, cols, rows);
      let out = "";
      for (let y = 0; y < rows; y += 1) {
        for (let x = 0; x < cols; x += 1) {
          const i = (y * cols + x) * 4;
          const light = (0.299 * data[i] + 0.587 * data[i + 1] + 0.114 * data[i + 2]) / 255;
          out += RAMP[Math.min(RAMP.length - 1, Math.floor(Math.pow(light, 0.8) * RAMP.length))];
        }
        out += "\n";
      }
      pre.textContent = out;
    },
  };
}

// ---------------------------------------------------------------------------------------------
// The rings: polished iridescent chrome with a violet glow. They tilt with scroll on a spring and spin faster
// (or reverse) with scroll speed. Each renders only while its section is on screen.

function initRing(canvasId, section, options) {
  const canvas = document.getElementById(canvasId);
  if (!canvas) return;
  const renderer = makeRenderer(canvas, 1.75);
  const scene = new THREE.Scene();
  const camera = new THREE.PerspectiveCamera(35, 1, 0.01, 100);
  scene.environment = makeStudioEnvironment(renderer);
  const key = new THREE.DirectionalLight(0xffffff, 2);
  key.position.set(-2, 3, 3);
  scene.add(key);

  const chrome = new THREE.MeshPhysicalMaterial({
    color: 0xd9d0ff,
    metalness: 1,
    roughness: 0.12,
    envMapIntensity: 1.5,
    clearcoat: 1,
    clearcoatRoughness: 0.03,
    iridescence: 1,
    iridescenceIOR: 1.4,
    iridescenceThicknessRange: [200, 600],
    emissive: new THREE.Color(0x6d4dff),
    emissiveIntensity: 0.55,
    side: THREE.DoubleSide,
  });
  const pass = makeLiquidPass(renderer, { columns: 160, reach: 0.2, glow: 1.2 });

  // The ring model lies in the XY plane: the tilt group lays it down, the pivot spins it around the vertical.
  const pivot = new THREE.Group();
  const tiltGroup = new THREE.Group();
  pivot.add(tiltGroup);
  scene.add(pivot);
  const tilt = new Spring(options.tilt, 60, 14);
  const spinSpeed = new Spring(0.22, 30, 10);
  const tiltTarget = { value: options.tilt };
  let spin = 0;
  let onScreen = false;
  let ready = false;

  {
    const model = makeRing(chrome);
    const box = new THREE.Box3().setFromObject(model);
    const size = box.getSize(new THREE.Vector3()).length();
    model.position.sub(box.getCenter(new THREE.Vector3()));
    tiltGroup.add(model);
    camera.position.set(0, size * 0.18, size * options.distance);
    camera.lookAt(0, 0, 0);
    resize();
    ready = true;
  }

  function resize() {
    const rect = canvas.getBoundingClientRect();
    renderer.setSize(rect.width, rect.height, false);
    pass.setSize(rect.width, rect.height);
    camera.aspect = rect.width / Math.max(rect.height, 1);
    camera.updateProjectionMatrix();
  }
  resize();
  window.addEventListener("resize", resize);
  new IntersectionObserver(([entry]) => { onScreen = entry.isIntersecting; }).observe(canvas);

  gsap.to(tiltTarget, {
    value: options.tiltEnd, ease: "none",
    scrollTrigger: { trigger: section, start: "top bottom", end: "bottom top", scrub: true },
  });

  const clock = new THREE.Clock();
  renderer.setAnimationLoop(() => {
    const dt = Math.min(clock.getDelta(), 0.05);
    if (!ready || !onScreen || document.hidden) return;
    const speed = scrollSpeed.value;
    tilt.target = tiltTarget.value;
    tilt.step(dt);
    spinSpeed.target = reduceMotion ? 0 : 0.22 + speed * 1.6;
    spin += spinSpeed.step(dt) * dt;
    tiltGroup.rotation.x = tilt.value;
    pivot.rotation.y = spin;
    pass.uniforms.uFlow.value = 1 + Math.abs(speed) * 1.6;
    pass.render(scene, camera, clock.elapsedTime);
    if ((frame += 1) % 2 === 0) ascii.draw();
  });
  const ascii = makeAscii(canvas);
  let frame = 0;
}

initFigure();
initRing("ring", ".welcome", { tilt: -0.35, tiltEnd: -1.05, distance: 2.2 });
initFinale();
