"use client"

// 3D Orb (from 21st.dev): a wireframe globe in a soft atmospheric glow, inside a slowly turning starfield. Adapted for
// Locken's web views: no Tailwind (the page has none), the colours come from the app (the current tab's), no earth
// textures (they aren't shipped, so the orb stays a wireframe), no "Drag to explore" hint (the dashboard stage doesn't
// take drags), and Reduce Motion holds it still.

import { useEffect, useRef } from "react"
import * as THREE from "three"
import { OrbitControls } from "three/examples/jsm/controls/OrbitControls.js"
import { Color } from "three"

type Props = {
  /** Colours the orb drifts between, in order. */
  colors?: string[]
  /** Reduce Motion: no rotation and no colour drift. */
  still?: boolean
}

const DEFAULT_COLORS = ["#3a86ff", "#8338ec", "#ff006e", "#fb5607", "#ffbe0b"]

export default function Globe({ colors = DEFAULT_COLORS, still = false }: Props) {
  const mountRef = useRef<HTMLDivElement>(null)
  // The scene is built once; colour and motion changes are read from here each frame.
  const live = useRef({ colors: colors.map((c) => new Color(c)), still })
  live.current = { colors: (colors.length ? colors : DEFAULT_COLORS).map((c) => new Color(c)), still }

  useEffect(() => {
    const mount = mountRef.current
    if (!mount) return

    const size = () => ({ w: mount.clientWidth || window.innerWidth, h: mount.clientHeight || window.innerHeight })
    let { w, h } = size()

    const scene = new THREE.Scene()
    const camera = new THREE.PerspectiveCamera(75, w / h, 0.1, 1000)
    const renderer = new THREE.WebGLRenderer({ antialias: true, alpha: true })
    renderer.setSize(w, h)
    renderer.setPixelRatio(window.devicePixelRatio)
    mount.appendChild(renderer.domElement)

    // Starfield
    const starsGeometry = new THREE.BufferGeometry()
    const starsCount = 10000
    const positions = new Float32Array(starsCount * 3)
    for (let i = 0; i < starsCount; i++) {
      positions[i * 3] = (Math.random() - 0.5) * 2000
      positions[i * 3 + 1] = (Math.random() - 0.5) * 2000
      positions[i * 3 + 2] = (Math.random() - 0.5) * 2000
    }
    starsGeometry.setAttribute("position", new THREE.BufferAttribute(positions, 3))
    const stars = new THREE.Points(starsGeometry, new THREE.PointsMaterial({ color: 0xffffff, size: 0.7, sizeAttenuation: true }))
    scene.add(stars)

    // Atmospheric glow
    const atmosphereMaterial = new THREE.ShaderMaterial({
      vertexShader: `
        varying vec3 vNormal;
        void main() {
          vNormal = normalize(normalMatrix * normal);
          gl_Position = projectionMatrix * modelViewMatrix * vec4(position, 1.0);
        }
      `,
      fragmentShader: `
        uniform vec3 glowColor;
        varying vec3 vNormal;
        void main() {
          float intensity = pow(0.6 - dot(vNormal, vec3(0.0, 0.0, 1.0)), 2.0);
          gl_FragColor = vec4(glowColor, 1.0) * intensity;
        }
      `,
      blending: THREE.AdditiveBlending,
      side: THREE.BackSide,
      transparent: true,
      uniforms: { glowColor: { value: new Color(live.current.colors[0]) } },
    })
    const atmosphereMesh = new THREE.Mesh(new THREE.SphereGeometry(5.2, 32, 32), atmosphereMaterial)
    scene.add(atmosphereMesh)

    // Wireframe globe
    const wireframeMaterial = new THREE.MeshBasicMaterial({ color: live.current.colors[0], wireframe: true, transparent: true, opacity: 0.5 })
    const wireframeGlobe = new THREE.Mesh(new THREE.SphereGeometry(5, 32, 32), wireframeMaterial)
    scene.add(wireframeGlobe)

    scene.add(new THREE.AmbientLight(0xffffff, 0.5))
    const pointLight = new THREE.PointLight(0xffffff, 1)
    pointLight.position.set(10, 10, 10)
    scene.add(pointLight)

    camera.position.z = 10

    const controls = new OrbitControls(camera, renderer.domElement)
    controls.enableDamping = true
    controls.dampingFactor = 0.05
    controls.rotateSpeed = 0.5
    controls.enableZoom = false

    let colorIndex = 0
    let colorT = 0
    const colorTransitionSpeed = 0.005
    const current = new Color()

    let animationId = 0
    const animate = () => {
      animationId = requestAnimationFrame(animate)
      const { colors: palette, still: frozen } = live.current
      if (!frozen) {
        colorT += colorTransitionSpeed
        if (colorT >= 1) {
          colorT = 0
          colorIndex = (colorIndex + 1) % palette.length
        }
      }
      const from = palette[colorIndex % palette.length]
      const to = palette[(colorIndex + 1) % palette.length]
      current.copy(from).lerp(to, frozen ? 0 : colorT)
      wireframeMaterial.color.copy(current)
      atmosphereMaterial.uniforms.glowColor.value.copy(current)

      if (!frozen) {
        wireframeGlobe.rotation.y += 0.001
        atmosphereMesh.rotation.y += 0.0005
        stars.rotation.y += 0.0001
      }
      controls.update()
      renderer.render(scene, camera)
    }
    animate()

    const handleResize = () => {
      ;({ w, h } = size())
      camera.aspect = w / h
      camera.updateProjectionMatrix()
      renderer.setSize(w, h)
    }
    window.addEventListener("resize", handleResize)

    return () => {
      window.removeEventListener("resize", handleResize)
      cancelAnimationFrame(animationId)
      controls.dispose()
      renderer.dispose()
      mount.removeChild(renderer.domElement)
    }
  }, [])

  return <div ref={mountRef} style={{ position: "absolute", inset: 0 }} />
}
