(()=>{var pe={feed:.0367,kill:.0649,advect:0,force:0,inject:.6,radius:.028,spacing:.09,life:.988,morph:650},Te=`#version 300 es
out vec2 vUv;
void main() {
  vec2 p = vec2(float((gl_VertexID << 1) & 2), float(gl_VertexID & 2));
  vUv = p;
  gl_Position = vec4(p * 2.0 - 1.0, 0.0, 1.0);
}`,Ee=`#version 300 es
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
}`,ge=`#version 300 es
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
}`,be=`#version 300 es
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
}`;function Re(i){let m=/^#?([0-9a-f]{6})$/i.exec(i||""),l=m?parseInt(m[1],16):9133302;return[(l>>16)/255,(l>>8&255)/255,(l&255)/255]}function le(i,m={}){let l={text:"25:00",accent:"#8B5CF6",...m},d={...pe,...m.tune||{}},C=m.fontFamily||"Montserrat, sans-serif",K=window.matchMedia("(prefers-reduced-motion: reduce)"),Y=m.fallbackText!==!1;getComputedStyle(i).position==="static"&&(i.style.position="relative");let v=document.createElement("canvas");v.style.cssText="position:absolute;inset:0;width:100%;height:100%;display:block",i.appendChild(v);let T=document.createElement("div");T.style.cssText=`position:absolute;inset:0;display:none;align-items:center;justify-content:center;color:#fff;font:700 64px ${C};font-variant-numeric:tabular-nums`,i.appendChild(T);let e=v.getContext("webgl2",{alpha:!0,premultipliedAlpha:!0,antialias:!1});if(!!!(e&&e.getExtension("EXT_color_buffer_float")))return v.style.display="none",Y&&(T.textContent=l.text,T.style.display="flex"),{supported:!1,update(o={}){Object.assign(l,o),Y&&(T.textContent=l.text)},destroy(){v.remove(),T.remove()}};let a,h,A,V,E,y,U,L,g,F,k=-1e9,c=0,x=0,b=0,w=0,p,f,s={x:.5,y:.5,dx:0,dy:0,active:!1},D=null,S=null,M=[],P=0,W=0,q=!0;function J(o,t){let n=e.createShader(o);if(e.shaderSource(n,t),e.compileShader(n),!e.getShaderParameter(n,e.COMPILE_STATUS))throw new Error(e.getShaderInfoLog(n));return n}function z(o){let t=e.createProgram();if(e.attachShader(t,J(e.VERTEX_SHADER,Te)),e.attachShader(t,J(e.FRAGMENT_SHADER,o)),e.linkProgram(t),!e.getProgramParameter(t,e.LINK_STATUS))throw new Error(e.getProgramInfoLog(t));let n={},r=e.getProgramParameter(t,e.ACTIVE_UNIFORMS);for(let u=0;u<r;u++){let B=e.getActiveUniform(t,u).name;n[B]=e.getUniformLocation(t,B)}return{p:t,u:n}}function N(o,t,n){let r=e.createTexture();e.bindTexture(e.TEXTURE_2D,r),e.texImage2D(e.TEXTURE_2D,0,e.RGBA16F,o,t,0,e.RGBA,e.HALF_FLOAT,null),e.texParameteri(e.TEXTURE_2D,e.TEXTURE_MIN_FILTER,n),e.texParameteri(e.TEXTURE_2D,e.TEXTURE_MAG_FILTER,n),e.texParameteri(e.TEXTURE_2D,e.TEXTURE_WRAP_S,e.CLAMP_TO_EDGE),e.texParameteri(e.TEXTURE_2D,e.TEXTURE_WRAP_T,e.CLAMP_TO_EDGE);let u=e.createFramebuffer();return e.bindFramebuffer(e.FRAMEBUFFER,u),e.framebufferTexture2D(e.FRAMEBUFFER,e.COLOR_ATTACHMENT0,e.TEXTURE_2D,r,0),e.clearColor(0,0,0,1),e.clear(e.COLOR_BUFFER_BIT),{tex:r,fbo:u}}function Q(o){e.bindFramebuffer(e.FRAMEBUFFER,o.fbo),e.clearColor(1,0,0,1),e.clear(e.COLOR_BUFFER_BIT)}function j(){if(b=i.clientWidth,w=i.clientHeight,b<2||w<2)return!1;for(let t of[E,y,U,L])t&&(e.deleteTexture(t.tex),e.deleteFramebuffer(t.fbo));let o=Math.min(window.devicePixelRatio||1,2);return v.width=Math.max(2,Math.round(b*o)),v.height=Math.max(2,Math.round(w*o)),c=Math.min(512,Math.max(96,Math.round(b*1.6))),x=Math.max(48,Math.round(c*w/b)),E=N(c,x,e.LINEAR),y=N(c,x,e.LINEAR),U=N(c,x,e.LINEAR),L=N(c,x,e.LINEAR),Q(E),Q(y),p=p||document.createElement("canvas"),p.width=c*2,p.height=x*2,f=p.getContext("2d"),g=g||e.createTexture(),F=F||e.createTexture(),Z(!0),!0}function Z(o){o||([F,g]=[g,F]);let t=p.width,n=p.height;f.fillStyle="#000",f.fillRect(0,0,t,n);let r=l.text,u=n*.62;f.font=`700 ${u}px ${C}`;let B=f.measureText("0").width,xe=B*.45,H=[...r].map(R=>R===":"?xe:B),ue=H.reduce((R,G)=>R+G,0),X=Math.min(1,t*.9/ue);u*=X,f.font=`700 ${u}px ${C}`,f.fillStyle="#fff",f.textAlign="center",f.textBaseline="alphabetic";let ce=f.measureText("0"),he=n/2+(ce.actualBoundingBoxAscent-ce.actualBoundingBoxDescent)/2,se=(t-ue*X)/2;[...r].forEach((R,G)=>{f.fillText(R,se+H[G]*X/2,he),se+=H[G]*X});for(let R of o?[g,F]:[g])e.bindTexture(e.TEXTURE_2D,R),e.pixelStorei(e.UNPACK_FLIP_Y_WEBGL,!0),e.texImage2D(e.TEXTURE_2D,0,e.RGBA,e.RGBA,e.UNSIGNED_BYTE,p),e.pixelStorei(e.UNPACK_FLIP_Y_WEBGL,!1),e.texParameteri(e.TEXTURE_2D,e.TEXTURE_MIN_FILTER,e.LINEAR),e.texParameteri(e.TEXTURE_2D,e.TEXTURE_MAG_FILTER,e.LINEAR),e.texParameteri(e.TEXTURE_2D,e.TEXTURE_WRAP_S,e.CLAMP_TO_EDGE),e.texParameteri(e.TEXTURE_2D,e.TEXTURE_WRAP_T,e.CLAMP_TO_EDGE);o||K.matches?(k=-1e9,P=28):k=performance.now()}function I(o,t){e.activeTexture(e.TEXTURE0+o),e.bindTexture(e.TEXTURE_2D,t)}function ee(o,t,n,r){e.useProgram(o.p),e.bindFramebuffer(e.FRAMEBUFFER,t?t.fbo:null),e.viewport(0,0,n,r),e.bindVertexArray(V),e.drawArrays(e.TRIANGLES,0,3)}function me(o){let t=[b/w,1];e.useProgram(h.p),I(0,U.tex),e.uniform1i(h.u.uVel,0),e.uniform2f(h.u.uPos,s.x,s.y),e.uniform2f(h.u.uDelta,s.dx,s.dy),e.uniform2f(h.u.uAspect,t[0],t[1]),e.uniform1f(h.u.uRadius,.11),e.uniform1f(h.u.uForce,d.force),ee(h,L,c,x),[U,L]=[L,U],e.useProgram(a.p),I(0,E.tex),e.uniform1i(a.u.uState,0),I(1,U.tex),e.uniform1i(a.u.uVel,1),I(2,g),e.uniform1i(a.u.uMask,2),I(3,F),e.uniform1i(a.u.uMaskOld,3);let n=Math.min(1,(performance.now()-k)/d.morph);e.uniform1f(a.u.uMix,n*n*(3-2*n)),e.uniform1f(a.u.uFollow,n<1?.35:0),e.uniform2f(a.u.uTexel,1/c,1/x),e.uniform2f(a.u.uPos,o?o.x:-1,o?o.y:-1),e.uniform2f(a.u.uAspect,t[0],t[1]),e.uniform1f(a.u.uFeed,d.feed),e.uniform1f(a.u.uKill,d.kill),e.uniform1f(a.u.uAdvect,d.advect),e.uniform1f(a.u.uInject,o?d.inject:0),e.uniform1f(a.u.uRadius,d.radius),e.uniform1f(a.u.uLife,d.life),ee(a,y,c,x),[E,y]=[y,E]}function de(){e.useProgram(A.p),I(0,E.tex),e.uniform1i(A.u.uState,0),e.uniform2f(A.u.uTexel,1/c,1/x),e.uniform2f(A.u.uAspect,b/w,1),e.uniform3fv(A.u.uTint,Re(l.accent)),e.enable(e.BLEND),e.blendFunc(e.ONE,e.ONE_MINUS_SRC_ALPHA),e.bindFramebuffer(e.FRAMEBUFFER,null),e.viewport(0,0,v.width,v.height),e.clearColor(0,0,0,0),e.clear(e.COLOR_BUFFER_BIT),e.bindVertexArray(V),e.drawArrays(e.TRIANGLES,0,3),e.disable(e.BLEND)}let te=0,O=0,oe=!0;function ne(o=performance.now()){if(!q||(W=requestAnimationFrame(ne),!c||document.hidden||!oe||i.clientWidth<2))return;let t=K.matches;if(!(P>0||M.length>0||s.active||o<te||o-k<d.morph+100)&&!t&&O<1){O++;return}let r=(P>0?8:t?0:3)*(1+O);O=0;for(let u=0;u<r;u++)me(t?null:M.shift());t&&(M.length=0),P>0&&(P=Math.max(0,P-r)),s.active=!1,s.dx=s.dy=0,de()}function re(o){let t=i.getBoundingClientRect();if(t.width<2||t.height<2)return;let n=(o.clientX-t.left)/t.width,r=1-(o.clientY-t.top)/t.height;if(n<-.05||n>1.05||r<-.15||r>1.15){D=null,S=null;return}D&&(s.dx+=n-D.x,s.dy+=r-D.y),s.x=n,s.y=r,s.active=!0,te=performance.now()+900,D={x:n,y:r};let u=t.width/t.height;(!S||Math.hypot((n-S.x)*u,r-S.y)>d.spacing)&&(M.push({x:n+(Math.random()-.5)*.02,y:r+(Math.random()-.5)*.04}),M.length>12&&M.shift(),S={x:n,y:r})}V=e.createVertexArray(),h=z(Ee),a=z(ge),A=z(be);let ae=new ResizeObserver(()=>{j()});ae.observe(i);let ie=typeof IntersectionObserver=="function"?new IntersectionObserver(([o])=>{oe=o.isIntersecting}):null;ie?.observe(i),window.addEventListener("pointermove",re);let ve=C.split(",")[0].trim();return(document.fonts?.load(`700 64px ${ve}`)??Promise.resolve()).then(()=>{j()},()=>{j()}),W=requestAnimationFrame(ne),{supported:!0,update(o={}){let t=o.text!==void 0&&o.text!==l.text;Object.assign(l,o),t&&c&&Z()},destroy(){q=!1,cancelAnimationFrame(W),ae.disconnect(),ie?.disconnect(),window.removeEventListener("pointermove",re),v.remove(),T.remove()}}}var _=new URLSearchParams(location.search),_e=document.getElementById("root");_.get("bg")&&(document.body.style.background=_.get("bg"));var fe={};for(let[i,m]of _)!Number.isNaN(parseFloat(m))&&!["text","accent","bg","v"].includes(i)&&(fe[i]=parseFloat(m));var $={text:"25:00",accent:"#8B5CF6",...window.__initialProps||{}};_.get("text")&&($.text=_.get("text"));_.get("accent")&&($.accent=_.get("accent"));var Ae=le(_e,{...$,tune:fe});window.updateProps=(i={})=>Ae.update(i);})();
