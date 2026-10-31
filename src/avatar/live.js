// Adds two things to the original demo, without touching its UI:
// - "Detach preview": opens output.html, a window with only the creature on a key colour,
//   mirroring every fur setting and the creature's pose live (for OBS Window Capture).
// - "Head + voice": the creature follows your head (camera) and opens its mouth when you
//   speak (microphone). Both are processed on this device only; a notice comes first.
import * as THREE from 'three';
import { CHANNEL } from './channel.js';

const VISION = 'https://cdn.jsdelivr.net/npm/@mediapipe/tasks-vision@0.10.14';
const MODEL = 'https://storage.googleapis.com/mediapipe-models/face_landmarker/face_landmarker/float16/1/face_landmarker.task';

export function setupLive({ creature, furSystem, pointerNDC }) {
  const channel = new BroadcastChannel(CHANNEL);
  const pose = { lookX: 0, lookY: 0, roll: 0, mouth: 0 };
  let tracking = false;
  let landmarker = null;
  let video = null;
  let analyser = null;
  let streams = [];
  const m4 = new THREE.Matrix4();
  const euler = new THREE.Euler(0, 0, 0, 'YXZ');
  const level = new Uint8Array(256);

  const bar = document.createElement('div');
  bar.style.cssText = 'position:fixed;left:16px;bottom:16px;z-index:50;display:flex;gap:8px;flex-wrap:wrap;font:14px system-ui,sans-serif';
  const mk = (text) => {
    const b = document.createElement('button');
    b.textContent = text;
    b.style.cssText = 'min-height:40px;padding:0 14px;border-radius:10px;border:1px solid rgba(255,255,255,.25);background:rgba(17,24,38,.85);color:#fff;cursor:pointer';
    bar.appendChild(b);
    return b;
  };
  const detachBtn = mk('Detach preview');
  const trackBtn = mk('Head + voice');
  document.body.appendChild(bar);

  detachBtn.onclick = () => window.open('output.html', 'fluff-output', 'popup,width=720,height=720');
  trackBtn.onclick = () => (tracking ? stop() : showNotice());

  function showNotice() {
    const wrap = document.createElement('div');
    wrap.style.cssText = 'position:fixed;inset:0;z-index:60;display:grid;place-items:center;padding:16px;background:rgba(5,8,14,.8);font:15px/1.5 system-ui,sans-serif;color:#f1f5fb';
    wrap.innerHTML = `<div role="dialog" aria-modal="true" style="max-width:520px;background:#1b2638;border:1px solid #304056;border-radius:12px;padding:20px">
      <h2 style="margin-top:0">Before we use your camera and microphone</h2>
      <p>Your browser will next ask for your <b>camera</b> and <b>microphone</b>. If you allow them:</p>
      <ul>
        <li>The camera is used to follow the angle of your head; the microphone only measures how loud you speak, to move the mouth.</li>
        <li>Both are processed only on this device, in this tab. Nothing is recorded, stored or sent anywhere.</li>
        <li>To follow your head, the page downloads Google's free face-tracking code and model (from jsDelivr and Google). Your video and voice are not sent to them.</li>
        <li>Press "Stop head + voice" or close the tab to stop.</li>
      </ul>
      <div style="display:flex;gap:8px;flex-wrap:wrap">
        <button data-ok style="min-height:44px;padding:0 18px;border-radius:8px;border:1px solid #9a8cff;background:#7765f4;color:#fff">Continue</button>
        <button data-no style="min-height:44px;padding:0 18px;border-radius:8px;border:1px solid #304056;background:#111826;color:#fff">Not now</button>
      </div></div>`;
    document.body.appendChild(wrap);
    wrap.querySelector('[data-no]').onclick = () => wrap.remove();
    wrap.querySelector('[data-ok]').onclick = () => { wrap.remove(); start(); };
  }

  async function start() {
    trackBtn.textContent = 'Starting...';
    try {
      const stream = await navigator.mediaDevices.getUserMedia({ video: { width: 640, height: 480 }, audio: true });
      streams.push(stream);
      video = document.createElement('video');
      video.muted = true;
      video.playsInline = true;
      video.srcObject = new MediaStream(stream.getVideoTracks());
      await video.play();
      const ctx = new AudioContext();
      analyser = ctx.createAnalyser();
      analyser.fftSize = 512;
      ctx.createMediaStreamSource(new MediaStream(stream.getAudioTracks())).connect(analyser);
      const vision = await import(/* @vite-ignore */ `${VISION}/vision_bundle.mjs`);
      const files = await vision.FilesetResolver.forVisionTasks(`${VISION}/wasm`);
      landmarker = await vision.FaceLandmarker.createFromOptions(files, {
        baseOptions: { modelAssetPath: MODEL, delegate: 'GPU' },
        runningMode: 'VIDEO', numFaces: 1, outputFacialTransformationMatrixes: true,
      });
      tracking = true;
      trackBtn.textContent = 'Stop head + voice';
    } catch (err) {
      stop();
      trackBtn.textContent = 'Head + voice (unavailable)';
      console.warn('Head + voice:', err);
    }
  }

  function stop() {
    tracking = false;
    streams.forEach((s) => s.getTracks().forEach((t) => t.stop()));
    streams = [];
    analyser = null;
    pose.mouth = 0;
    pose.roll = 0;
    creature.setMouthOpen(0);
    trackBtn.textContent = 'Head + voice';
  }

  function serializeUniforms() {
    const out = {};
    for (const [name, u] of Object.entries(furSystem.sharedUniforms)) {
      const v = u.value;
      if (name === 'uPhysicsTex' || name === 'uTime') continue;
      if (typeof v === 'number') out[name] = v;
      else if (v && v.isColor) out[name] = ['c', v.r, v.g, v.b];
      else if (v && v.isVector3) out[name] = ['v', v.x, v.y, v.z];
    }
    return out;
  }

  // Call before creature.update(): head pose drives the creature's own look tracking.
  function tick() {
    if (tracking && landmarker && video && video.readyState >= 2) {
      const r = landmarker.detectForVideo(video, performance.now());
      const mat = r.facialTransformationMatrixes && r.facialTransformationMatrixes[0];
      if (mat) {
        euler.setFromRotationMatrix(m4.fromArray(mat.data));
        pose.lookX = THREE.MathUtils.clamp(-euler.y * 2.2, -1, 1);
        pose.lookY = THREE.MathUtils.clamp(euler.x * 2.2, -1, 1);
        pose.roll = THREE.MathUtils.lerp(pose.roll, -euler.z * 0.8, 0.3);
      }
      pointerNDC.set(pose.lookX, pose.lookY);
      creature.root.rotation.z = pose.roll;
    }
    if (analyser) {
      analyser.getByteTimeDomainData(level);
      let sum = 0;
      for (let i = 0; i < level.length; i++) { const d = (level[i] - 128) / 128; sum += d * d; }
      const rms = Math.sqrt(sum / level.length);
      pose.mouth = THREE.MathUtils.lerp(pose.mouth, THREE.MathUtils.clamp((rms - 0.02) * 9, 0, 1), 0.5);
      creature.setMouthOpen(pose.mouth);
    }
    channel.postMessage({
      type: 'state',
      pose: { lookX: pointerNDC.x, lookY: pointerNDC.y, roll: creature.root.rotation.z, mouth: pose.mouth },
      uniforms: serializeUniforms(),
      skin: '#' + creature.skinMaterial.color.getHexString(),
    });
  }

  return { tick };
}
