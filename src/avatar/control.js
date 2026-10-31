// Fluff avatar control page: camera + face tracking run HERE, on this device; only head
// angles and mouth openness (numbers) go to the output window, inside this browser.
import * as THREE from 'three';
import { FUR_PRESETS } from '../ui.js';
import { CHANNEL, DEFAULTS, BACKGROUNDS } from './channel.js';

const VISION = 'https://cdn.jsdelivr.net/npm/@mediapipe/tasks-vision@0.10.14';
const MODEL = 'https://storage.googleapis.com/mediapipe-models/face_landmarker/face_landmarker/float16/1/face_landmarker.task';

const $ = (id) => document.getElementById(id);
const settings = { ...DEFAULTS };
const channel = new BroadcastChannel(CHANNEL);
const sendSettings = () => channel.postMessage({ type: 'settings', settings });
const sendPose = (pose) => channel.postMessage({ type: 'pose', pose });
channel.onmessage = (e) => {
  if (e.data && e.data.type === 'hello') sendSettings();
};

FUR_PRESETS.forEach((p, i) => $('preset').add(new Option(p.name || `Coat ${i + 1}`, String(i))));
BACKGROUNDS.forEach(([name, hex]) => $('background').add(new Option(name, hex)));
$('preset').onchange = (e) => { settings.preset = Number(e.target.value); sendSettings(); };
$('background').onchange = (e) => { settings.background = e.target.value; sendSettings(); };
$('sensitivity').oninput = (e) => { settings.sensitivity = Number(e.target.value); sendSettings(); };

$('open-output').onclick = () => {
  window.open('output.html', 'fluff-output', 'popup,width=720,height=720');
  setTimeout(sendSettings, 800);
};

let stream = null;
let landmarker = null;
let running = false;

$('consent-ok').onclick = async () => {
  $('consent').hidden = true;
  setStatus('Loading face tracker...');
  try {
    const vision = await import(/* @vite-ignore */ `${VISION}/vision_bundle.mjs`);
    const files = await vision.FilesetResolver.forVisionTasks(`${VISION}/wasm`);
    landmarker = await vision.FaceLandmarker.createFromOptions(files, {
      baseOptions: { modelAssetPath: MODEL, delegate: 'GPU' },
      runningMode: 'VIDEO',
      numFaces: 1,
      outputFaceBlendshapes: true,
      outputFacialTransformationMatrixes: true,
    });
    setStatus('Requesting camera access...');
    stream = await navigator.mediaDevices.getUserMedia({ video: { width: 640, height: 480 }, audio: false });
    $('video').srcObject = stream;
    await $('video').play();
    running = true;
    $('stop').hidden = false;
    setStatus('Tracking. Open the output window and capture it in OBS.');
    track();
  } catch (err) {
    setStatus(`Camera or tracker unavailable: ${err && err.message ? err.message : err}`);
  }
};

$('consent-no').onclick = () => {
  $('consent').hidden = true;
  setStatus('Camera not used. Nothing was requested.');
};

$('stop').onclick = () => {
  running = false;
  if (stream) stream.getTracks().forEach((t) => t.stop());
  stream = null;
  $('stop').hidden = true;
  sendPose({ yaw: 0, pitch: 0, roll: 0, jaw: 0 });
  setStatus('Camera stopped.');
};

const m4 = new THREE.Matrix4();
const euler = new THREE.Euler(0, 0, 0, 'YXZ');
let lastTime = -1;

function track() {
  if (!running) return;
  const video = $('video');
  if (video.currentTime !== lastTime) {
    lastTime = video.currentTime;
    const result = landmarker.detectForVideo(video, performance.now());
    const mat = result.facialTransformationMatrixes && result.facialTransformationMatrixes[0];
    if (mat) {
      euler.setFromRotationMatrix(m4.fromArray(mat.data));
      const shapes = (result.faceBlendshapes && result.faceBlendshapes[0] && result.faceBlendshapes[0].categories) || [];
      const jawShape = shapes.find((c) => c.categoryName === 'jawOpen');
      sendPose({ yaw: euler.y, pitch: euler.x, roll: euler.z, jaw: jawShape ? jawShape.score : 0 });
    }
  }
  requestAnimationFrame(track);
}

function setStatus(text) {
  $('status').textContent = text;
}
