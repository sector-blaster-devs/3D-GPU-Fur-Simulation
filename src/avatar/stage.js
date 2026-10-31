// Fluff avatar output: the creature alone on a key-colour background, driven by
// head-pose messages from the control page (avatar.html). Grab this window in OBS
// (Window Capture + Chroma Key). No camera, no network here.
import * as THREE from 'three';
import { createBlobCreature } from '../blobCreature.js';
import { createGPUFurPhysics } from '../gpuPhysics.js';
import { createGPUFurSystem } from '../furSystem.js';
import { FUR_PRESETS } from '../ui.js';
import { CHANNEL, DEFAULTS } from './channel.js';

const settings = { ...DEFAULTS };
const pose = { yaw: 0, pitch: 0, roll: 0, jaw: 0 };

const renderer = new THREE.WebGLRenderer({ antialias: true, alpha: false });
renderer.setPixelRatio(Math.min(window.devicePixelRatio || 1, 2));
renderer.setSize(window.innerWidth, window.innerHeight);
renderer.toneMapping = THREE.ACESFilmicToneMapping;
renderer.toneMappingExposure = 1.08;
document.body.appendChild(renderer.domElement);

const scene = new THREE.Scene();
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
const furState = { ...FUR_PRESETS[0], lightIntensity: 1.35, rimIntensity: 1.35, windStrength: 0.4,
  gpuFurEnabled: physics.isGPGPUActive };
const fur = createGPUFurSystem(creature.bodyGeometry, furState);
creature.root.add(fur.shellMesh);
creature.root.add(fur.strandMesh);

function applySettings() {
  scene.background = new THREE.Color(settings.background);
  const preset = FUR_PRESETS[settings.preset] || FUR_PRESETS[0];
  const u = fur.sharedUniforms;
  u.uBaseColor.value.set(preset.baseColor);
  u.uTipColor.value.set(preset.tipColor);
  creature.skinMaterial.color.set(preset.baseColor).multiplyScalar(0.55);
}
applySettings();

const channel = new BroadcastChannel(CHANNEL);
channel.onmessage = (e) => {
  const m = e.data || {};
  if (m.type === 'pose') Object.assign(pose, m.pose);
  if (m.type === 'settings') { Object.assign(settings, m.settings); applySettings(); }
};
channel.postMessage({ type: 'hello' });   // ask the control page for current settings

const clock = new THREE.Clock();
const look = new THREE.Vector2();
const zero = new THREE.Vector3();
let elapsed = 0;
let smoothJaw = 0;
function frame() {
  const dt = Math.min(clock.getDelta(), 0.033);
  elapsed += dt;
  // Head pose -> the creature's own look tracking (it expects pointer-like -1..1 values).
  const k = settings.sensitivity;
  look.set(THREE.MathUtils.clamp(-pose.yaw * 2.2 * k, -1, 1), THREE.MathUtils.clamp(pose.pitch * 2.2 * k, -1, 1));
  creature.update(dt, look, camera.position, false);
  creature.root.rotation.z = THREE.MathUtils.lerp(creature.root.rotation.z, -pose.roll * 0.8 * k, 0.25);
  smoothJaw = THREE.MathUtils.lerp(smoothJaw, pose.jaw, 0.45);
  creature.setMouthOpen(smoothJaw * 1.6);

  const u = fur.sharedUniforms;
  u.uPhysicsTex.value = physics.isGPGPUActive ? physics.step({
    time: elapsed, dt, windStrength: 0.4,
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
