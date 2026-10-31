// Detached preview (output.html): the creature alone on a key colour for OBS Window
// Capture + Chroma Key. Mirrors the main demo live: every fur setting, the look/head
// pose and the mouth. Click to cycle the key colour (green, blue, magenta).
import * as THREE from 'three';
import { createBlobCreature } from '../blobCreature.js';
import { createGPUFurPhysics } from '../gpuPhysics.js';
import { createGPUFurSystem } from '../furSystem.js';
import { FUR_PRESETS } from '../ui.js';
import { CHANNEL } from './channel.js';

const KEYS = ['#00ff00', '#0000ff', '#ff00ff'];
let keyIndex = 0;

const renderer = new THREE.WebGLRenderer({ antialias: true });
renderer.setPixelRatio(Math.min(window.devicePixelRatio || 1, 2));
renderer.setSize(window.innerWidth, window.innerHeight);
renderer.toneMapping = THREE.ACESFilmicToneMapping;
renderer.toneMappingExposure = 1.08;
document.body.appendChild(renderer.domElement);

const scene = new THREE.Scene();
scene.background = new THREE.Color(KEYS[0]);
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
  keyIndex = (keyIndex + 1) % KEYS.length;
  scene.background.set(KEYS[keyIndex]);
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
