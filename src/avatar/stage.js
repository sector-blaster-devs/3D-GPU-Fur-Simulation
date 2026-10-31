// Detached preview (output.html): the creature alone on a key colour for OBS Window
// Capture + Chroma Key. Mirrors the main demo live: every fur setting, the look/head
// pose and the mouth. Click to cycle the background: green, blue, magenta, transparent
// (for an OBS Browser Source, or open output?bg=transparent) and blurred camera (your own
// camera, blurred, behind the creature; stays on this device).
import * as THREE from 'three';
import { createBlobCreature } from '../blobCreature.js';
import { createGPUFurPhysics } from '../gpuPhysics.js';
import { createGPUFurSystem } from '../furSystem.js';
import { FUR_PRESETS } from '../ui.js';
import { CHANNEL } from './channel.js';

const MODES = ['#00ff00', '#0000ff', '#ff00ff', 'transparent', 'blur'];
const NAMES = { '#00ff00': 'Green', '#0000ff': 'Blue', '#ff00ff': 'Magenta', transparent: 'Transparent', blur: 'Blurred camera' };
const asked = new URLSearchParams(location.search).get('bg');
let modeIndex = Math.max(0, MODES.indexOf(asked === 'transparent' || asked === 'blur' ? asked : '#' + (asked || '00ff00')));

const renderer = new THREE.WebGLRenderer({ antialias: true, alpha: true });
renderer.setClearColor(0x000000, 0);
renderer.setPixelRatio(Math.min(window.devicePixelRatio || 1, 2));
renderer.setSize(window.innerWidth, window.innerHeight);
renderer.toneMapping = THREE.ACESFilmicToneMapping;
renderer.toneMappingExposure = 1.08;
document.body.appendChild(renderer.domElement);

const scene = new THREE.Scene();
const backdrop = document.createElement('video');
backdrop.muted = true;
backdrop.playsInline = true;
backdrop.style.cssText = 'position:fixed;inset:-40px;width:calc(100% + 80px);height:calc(100% + 80px);object-fit:cover;filter:blur(28px) brightness(0.85);transform:scaleX(-1);z-index:-1;display:none';
document.body.appendChild(backdrop);
renderer.domElement.style.position = 'relative';
const toast = document.createElement('div');
toast.style.cssText = 'position:fixed;left:12px;top:12px;padding:6px 10px;border-radius:8px;background:rgba(0,0,0,.6);color:#fff;font:13px system-ui,sans-serif;transition:opacity .4s;opacity:0';
document.body.appendChild(toast);
let camStream = null;

async function applyMode(announce) {
  const mode = MODES[modeIndex];
  const solid = mode.startsWith('#');
  scene.background = solid ? new THREE.Color(mode) : null;
  document.documentElement.style.background = document.body.style.background = solid ? mode : 'transparent';
  if (mode === 'blur' && !camStream) {
    try {
      camStream = await navigator.mediaDevices.getUserMedia({ video: true, audio: false });
      backdrop.srcObject = camStream;
      await backdrop.play();
    } catch (err) {
      console.warn('Blurred background needs the camera:', err);
    }
  }
  if (mode !== 'blur' && camStream) {
    camStream.getTracks().forEach((t) => t.stop());
    camStream = null;
  }
  backdrop.style.display = mode === 'blur' ? 'block' : 'none';
  if (announce) {
    toast.textContent = NAMES[mode];
    toast.style.opacity = '1';
    clearTimeout(toast._t);
    toast._t = setTimeout(() => { toast.style.opacity = '0'; }, 1200);
  }
}
applyMode(false);
const camera = new THREE.PerspectiveCamera(32, window.innerWidth / window.innerHeight, 0.1, 50);
camera.position.set(0, 0.15, 8.6);
camera.lookAt(0, 0.05, 0);
const key = new THREE.DirectionalLight('#fff7ed', 1.9);
key.position.set(2.2, 2.6, 3.0);
scene.add(key);
const rim = new THREE.DirectionalLight('#c4b5fd', 1.6);
rim.position.set(-2.4, 1.8, -3.2);
scene.add(rim);
scene.add(new THREE.HemisphereLight('#f5d0fe', '#1e1b4b', 0.85));

const creature = createBlobCreature();
scene.add(creature.root);
const physics = createGPUFurPhysics(renderer);
const fur = createGPUFurSystem(creature.bodyGeometry, { ...FUR_PRESETS[0], lightIntensity: 1.35,
  rimIntensity: 1.35, windStrength: 0.4, gpuFurEnabled: physics.isGPGPUActive });
creature.root.add(fur.shellMesh);
creature.root.add(fur.strandMesh);

const look = new THREE.Vector2();
let roll = 0;
let mouth = 0;
const channel = new BroadcastChannel(CHANNEL);
channel.onmessage = (e) => {
  const m = e.data;
  if (!m || m.type !== 'state') return;
  look.set(m.pose.lookX, m.pose.lookY);
  roll = m.pose.roll;
  mouth = m.pose.mouth;
  if (m.skin) creature.skinMaterial.color.set(m.skin);
  const u = fur.sharedUniforms;
  for (const [name, v] of Object.entries(m.uniforms || {})) {
    if (!u[name]) continue;
    if (typeof v === 'number') u[name].value = v;
    else if (v[0] === 'c') u[name].value.setRGB(v[1], v[2], v[3]);
    else if (v[0] === 'v') u[name].value.set(v[1], v[2], v[3]);
  }
};

window.addEventListener('click', () => {
  modeIndex = (modeIndex + 1) % MODES.length;
  applyMode(true);
});

const clock = new THREE.Clock();
const zero = new THREE.Vector3();
let elapsed = 0;
function frame() {
  const dt = Math.min(clock.getDelta(), 0.033);
  elapsed += dt;
  creature.update(dt, look, camera.position, false);
  creature.root.rotation.z = roll;
  creature.setMouthOpen(mouth);
  const u = fur.sharedUniforms;
  u.uPhysicsTex.value = physics.isGPGPUActive ? physics.step({
    time: elapsed, dt, windStrength: u.uWindStrength.value,
    creatureVelocity: creature.animState.velocity, creatureAngularVel: creature.animState.angularVelocity,
    pointerLocalPos: zero, pointerVelocity: zero, pointerActive: false, boopShockwave: 0,
  }) : physics.fallbackTexture;
  u.uTime.value = elapsed;
  renderer.render(scene, camera);
  requestAnimationFrame(frame);
}
requestAnimationFrame(frame);

window.addEventListener('resize', () => {
  camera.aspect = window.innerWidth / window.innerHeight;
  camera.updateProjectionMatrix();
  renderer.setSize(window.innerWidth, window.innerHeight);
});
