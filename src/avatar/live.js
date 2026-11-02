// The Streaming section of the settings panel:
// - "Detach preview": opens output.html, a window with only the creature on a key colour,
//   mirroring every fur setting and the creature's pose live (for OBS Window Capture).
// - "Head tracking": the creature follows your head (camera).
// - "Mouth follows": your jaw (camera), your voice (microphone) or other people (the audio
//   of a shared tab or screen, e.g. a call). All processed on this device; a notice first.
import * as THREE from 'three';
import { CHANNEL } from './channel.js';
import { currentCharacterKey } from '../characters.js';

const VISION = 'https://cdn.jsdelivr.net/npm/@mediapipe/tasks-vision@0.10.14';
const MODEL = 'https://storage.googleapis.com/mediapipe-models/face_landmarker/face_landmarker/float16/1/face_landmarker.task';

// One Euro filter: steady when your head is still, no lag when it moves. This is what
// removes the jitter without making the creature feel slow.
function oneEuro(minCutoff = 1.2, beta = 6.0, dCutoff = 1.0) {
  let x = null;
  let dx = 0;
  let last = 0;
  const alpha = (cutoff, dt) => 1 / (1 + 1 / (2 * Math.PI * cutoff * dt));
  return (value, now) => {
    if (x === null) { x = value; last = now; return x; }
    const dt = Math.max((now - last) / 1000, 1 / 120);
    last = now;
    dx += alpha(dCutoff, dt) * ((value - x) / dt - dx);
    x += alpha(minCutoff + beta * Math.abs(dx), dt) * (value - x);
    return x;
  };
}

const HEAD_GAIN = 1.25;

export function setupLive({ creature, furSystem, pointerNDC, panel }) {
  const channel = new BroadcastChannel(CHANNEL);
  const pose = { lookX: 0, lookY: 0, yaw: 0, pitch: 0, roll: 0, mouth: 0, jaw: 0, blink: 0 };
  const filters = { yaw: oneEuro(), pitch: oneEuro(), roll: oneEuro(), jaw: oneEuro(3, 8), blink: oneEuro(8, 10) };
  let lastVideoTime = -1;
  let mouthSource = 'jaw';
  let audioStream = null;
  let audioCtx = null;
  let noiseFloor = 0.01;
  let tracking = false;
  let landmarker = null;
  let video = null;
  let analyser = null;
  let streams = [];
  const m4 = new THREE.Matrix4();
  const euler = new THREE.Euler(0, 0, 0, 'YXZ');
  const level = new Uint8Array(256);

  const NOTICES = {
    head: ['your camera', 'The camera is used to follow the angle of your head, your blinks and your jaw.'],
    mic: ['your microphone', 'The microphone only measures how loud the sound is, to move the mouth. It picks up everything in the room.'],
    others: ['the audio of a tab or screen', 'Your browser asks what to share: pick the tab or screen with the call and turn on its audio. Only how loud it is gets measured, to move the mouth. The picture is not used.'],
  };

  const mkButton = (text) => {
    const b = document.createElement('button');
    b.type = 'button';
    b.className = 'preset-btn';
    const label = document.createElement('span');
    label.className = 'preset-label';
    label.textContent = text;
    b.appendChild(label);
    b.setLabel = (t) => { label.textContent = t; };
    return b;
  };
  const grid = document.createElement('div');
  grid.className = 'preset-grid';
  const detachBtn = mkButton('Detach preview');
  const trackBtn = mkButton('Head tracking');
  grid.append(detachBtn, trackBtn);
  panel.appendChild(grid);

  const mouthTitle = document.createElement('div');
  mouthTitle.className = 'ui-section-title';
  mouthTitle.style.marginTop = '12px';
  mouthTitle.textContent = 'Mouth follows';
  panel.appendChild(mouthTitle);
  const mouthGrid = document.createElement('div');
  mouthGrid.className = 'preset-grid';
  mouthGrid.style.gridTemplateColumns = 'repeat(3, 1fr)';
  const sourceBtns = { jaw: mkButton('My jaw'), mic: mkButton('My mic'), others: mkButton('Other people') };
  Object.values(sourceBtns).forEach((b) => mouthGrid.appendChild(b));
  panel.appendChild(mouthGrid);

  function refreshButtons() {
    trackBtn.setLabel(tracking ? 'Stop tracking' : 'Head tracking');
    for (const [key, b] of Object.entries(sourceBtns)) {
      const on = mouthSource === key;
      b.setAttribute('aria-pressed', String(on));
      b.style.outline = on ? '2px solid #ff9ec7' : '';
      b.style.outlineOffset = on ? '-2px' : '';
    }
  }

  detachBtn.onclick = () => window.open(`output.html?character=${currentCharacterKey()}`, 'fluff-output', 'popup,width=720,height=720');
  trackBtn.onclick = () => (tracking ? stopHead() : confirmThen('head', startHead));
  sourceBtns.jaw.onclick = () => {
    stopAudio();
    mouthSource = 'jaw';
    refreshButtons();
    if (!tracking) confirmThen('head', startHead);
  };
  sourceBtns.mic.onclick = () => confirmThen('mic', () => startAudio('mic'));
  sourceBtns.others.onclick = () => confirmThen('others', () => startAudio('others'));
  refreshButtons();

  function confirmThen(kind, action) {
    const [what, how] = NOTICES[kind];
    const wrap = document.createElement('div');
    wrap.style.cssText = 'position:fixed;inset:0;z-index:60;display:grid;place-items:center;padding:16px;background:rgba(5,8,14,.8);font:15px/1.5 system-ui,sans-serif;color:#f1f5fb';
    const extra = kind === 'head'
      ? '<li>To follow your head, the page downloads Google\'s free face-tracking code and model (from jsDelivr and Google). Your video is not sent to them.</li>'
      : '';
    wrap.innerHTML = `<div role="dialog" aria-modal="true" style="max-width:520px;background:#1b2638;border:1px solid #304056;border-radius:12px;padding:20px">
      <h2 style="margin-top:0">Before we use ${what}</h2>
      <p>Your browser will next ask for permission. If you allow it:</p>
      <ul>
        <li>${how}</li>
        <li>It is processed only on this device, in this tab. Nothing is recorded, stored or sent anywhere.</li>
        ${extra}
        <li>Stop any time in the Streaming section, or close the tab.</li>
      </ul>
      <div style="display:flex;gap:8px;flex-wrap:wrap">
        <button data-ok style="min-height:44px;padding:0 18px;border-radius:8px;border:1px solid #9a8cff;background:#7765f4;color:#fff">Continue</button>
        <button data-no style="min-height:44px;padding:0 18px;border-radius:8px;border:1px solid #304056;background:#111826;color:#fff">Not now</button>
      </div></div>`;
    document.body.appendChild(wrap);
    wrap.querySelector('[data-no]').onclick = () => wrap.remove();
    wrap.querySelector('[data-ok]').onclick = () => { wrap.remove(); action(); };
  }

  async function startHead() {
    trackBtn.setLabel('Starting...');
    try {
      const cam = await navigator.mediaDevices.getUserMedia({ video: { width: 640, height: 480 } });
      streams.push(cam);
      video = document.createElement('video');
      video.muted = true;
      video.playsInline = true;
      video.srcObject = cam;
      await video.play();
      if (!landmarker) {
        const vision = await import(/* @vite-ignore */ `${VISION}/vision_bundle.mjs`);
        const files = await vision.FilesetResolver.forVisionTasks(`${VISION}/wasm`);
        landmarker = await vision.FaceLandmarker.createFromOptions(files, {
          baseOptions: { modelAssetPath: MODEL, delegate: 'GPU' },
          runningMode: 'VIDEO', numFaces: 1, outputFacialTransformationMatrixes: true, outputFaceBlendshapes: true,
        });
      }
      tracking = true;
    } catch (err) {
      stopHead();
      notify(`Camera unavailable (${reason(err)}).`);
      console.warn('Head tracking:', err);
    }
    refreshButtons();
  }

  function stopHead() {
    tracking = false;
    streams.forEach((s) => s.getTracks().forEach((t) => t.stop()));
    streams = [];
    video = null;
    Object.assign(pose, { yaw: 0, pitch: 0, roll: 0, jaw: 0, blink: 0 });
    creature.animState.externalBlink = 0;
    if (!analyser) creature.setMouthOpen(0);
    refreshButtons();
  }

  async function startAudio(kind) {
    stopAudio();
    try {
      if (kind === 'mic') {
        audioStream = await navigator.mediaDevices.getUserMedia({ audio: true });
      } else {
        // Browsers only hand out shared audio together with a picture; the picture is switched off.
        audioStream = await navigator.mediaDevices.getDisplayMedia({ video: true, audio: true });
        audioStream.getVideoTracks().forEach((t) => { t.enabled = false; });
        if (audioStream.getAudioTracks().length === 0) {
          stopAudio();
          notify('No audio was shared. Share a tab or your screen and turn on its audio.');
          refreshButtons();
          return;
        }
      }
      audioCtx = new AudioContext();
      analyser = audioCtx.createAnalyser();
      analyser.fftSize = 512;
      audioCtx.createMediaStreamSource(new MediaStream(audioStream.getAudioTracks())).connect(analyser);
      noiseFloor = 0.01;
      mouthSource = kind;
      // Sharing can be ended from the browser's own bar: fall back to the jaw.
      audioStream.getAudioTracks()[0].addEventListener('ended', () => {
        stopAudio();
        mouthSource = 'jaw';
        refreshButtons();
      });
    } catch (err) {
      stopAudio();
      notify(`${kind === 'mic' ? 'Microphone' : 'Shared audio'} unavailable (${reason(err)}).`);
      console.warn('Mouth source:', err);
    }
    refreshButtons();
  }

  function stopAudio() {
    if (audioStream) audioStream.getTracks().forEach((t) => t.stop());
    audioStream = null;
    if (audioCtx) audioCtx.close();
    audioCtx = null;
    analyser = null;
    pose.mouth = 0;
    if (!tracking) creature.setMouthOpen(0);
  }

  // "Permission denied by system" is the operating system refusing, not the browser.
  function reason(err) {
    const msg = (err && err.message) || String(err);
    if (/system/i.test(msg)) return 'blocked by your system privacy settings: allow it for your browser in Windows Settings > Privacy & security, or macOS System Settings > Privacy';
    if (err && err.name === 'NotReadableError') return 'in use by another app, e.g. OBS';
    if (err && err.name === 'NotAllowedError') return 'permission denied or cancelled in the browser';
    if (err && err.name === 'NotFoundError') return 'no device found';
    return msg;
  }

  function notify(text) {
    const n = document.createElement('div');
    n.textContent = text;
    n.style.cssText = 'position:fixed;left:16px;bottom:16px;z-index:55;max-width:min(520px,calc(100vw - 32px));padding:10px 14px;border-radius:10px;background:rgba(17,24,38,.95);border:1px solid #304056;color:#f1f5fb;font:14px/1.4 system-ui,sans-serif';
    document.body.appendChild(n);
    setTimeout(() => n.remove(), 9000);
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
    // Only when the camera has a NEW frame: detecting on every display frame blocked the
    // render loop for nothing, which was a big part of the stutter.
    if (tracking && landmarker && video && video.srcObject && video.readyState >= 2 && video.currentTime !== lastVideoTime) {
      lastVideoTime = video.currentTime;
      const now = performance.now();
      const r = landmarker.detectForVideo(video, now);
      const mat = r.facialTransformationMatrixes && r.facialTransformationMatrixes[0];
      if (mat) {
        euler.setFromRotationMatrix(m4.fromArray(mat.data));
        pose.yaw = filters.yaw(-euler.y, now);
        pose.pitch = filters.pitch(-euler.x, now);
        pose.roll = filters.roll(-euler.z, now);
        const shapes = (r.faceBlendshapes && r.faceBlendshapes[0] && r.faceBlendshapes[0].categories) || [];
        const score = (name) => { const c = shapes.find((s) => s.categoryName === name); return c ? c.score : 0; };
        pose.jaw = filters.jaw(score('jawOpen'), now);
        pose.blink = filters.blink(Math.max(score('eyeBlinkLeft'), score('eyeBlinkRight')), now);
      }
    }
    if (tracking && video && video.srcObject) {
      // Eyes lead the head, like a real look.
      pointerNDC.set(THREE.MathUtils.clamp(pose.yaw * 2.5, -1, 1), THREE.MathUtils.clamp(-pose.pitch * 2.5, -1, 1));
    }
    if (analyser) {
      analyser.getByteTimeDomainData(level);
      let sum = 0;
      for (let i = 0; i < level.length; i++) { const d = (level[i] - 128) / 128; sum += d * d; }
      const rms = Math.sqrt(sum / level.length);
      // Follows the room's or call's own noise level, so steady background stays closed.
      noiseFloor += (rms < noiseFloor ? 0.2 : 0.003) * (rms - noiseFloor);
      const target = THREE.MathUtils.clamp((rms - noiseFloor * 1.6 - 0.006) * 11, 0, 1);
      pose.mouth = THREE.MathUtils.lerp(pose.mouth, target, target > pose.mouth ? 0.6 : 0.22);
    }
  }

  // After creature.update(), which rewrites the root rotation every frame: the head turn
  // goes on top of its idle sway, at full range, so the motion is recognisably yours.
  function afterUpdate() {
    const mouth = mouthSource === 'jaw' ? Math.min(1, Math.max(0, pose.jaw - 0.05) * 1.9) : pose.mouth;
    if (tracking || analyser) creature.setMouthOpen(mouth);
    if (tracking) {
      creature.root.rotation.y += pose.yaw * HEAD_GAIN;
      creature.root.rotation.x += pose.pitch * HEAD_GAIN;
      creature.root.rotation.z += pose.roll * HEAD_GAIN;
      creature.animState.externalBlink = pose.blink > 0.45 ? pose.blink : 0;
    }
    channel.postMessage({
      type: 'state',
      character: currentCharacterKey(),
      pose: { lookX: pointerNDC.x, lookY: pointerNDC.y, yaw: pose.yaw * HEAD_GAIN, pitch: pose.pitch * HEAD_GAIN,
        roll: pose.roll * HEAD_GAIN, mouth, blink: creature.animState.externalBlink || 0 },
      uniforms: serializeUniforms(),
      skin: '#' + creature.skinMaterial.color.getHexString(),
    });
  }

  return { tick, afterUpdate };
}
