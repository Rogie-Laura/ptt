import { io, Socket } from "socket.io-client";

interface User {
  id: string;
  name: string;
}

const app = document.getElementById("app")!;

let socket: Socket | null = null;
let micStream: MediaStream | null = null;
let recorder: MediaRecorder | null = null;
let audioMime = "audio/webm";
let isTalking = false;
let currentSpeakerId: string | null = null;
let lastUsers: User[] = [];

const audioQueue: Blob[] = [];
let isPlaying = false;

function escapeHtml(text: string) {
  const el = document.createElement("span");
  el.textContent = text;
  return el.innerHTML;
}

function renderJoin() {
  app.innerHTML = `
    <header>
      <h1>📻 PTT</h1>
      <p>Push-to-talk walkie style</p>
    </header>
    <div class="card">
      <label for="name">Pangalan mo</label>
      <input id="name" type="text" placeholder="hal. Juan" maxlength="24" autocomplete="nickname" />
      <label for="room">Room / Channel</label>
      <input id="room" type="text" placeholder="hal. team-alpha" maxlength="32" autocomplete="off" />
      <button class="btn btn-primary" id="join-btn">Sumali sa channel</button>
      <p class="error hidden" id="join-error"></p>
    </div>
  `;

  const nameInput = document.getElementById("name") as HTMLInputElement;
  const roomInput = document.getElementById("room") as HTMLInputElement;
  const joinBtn = document.getElementById("join-btn") as HTMLButtonElement;
  const joinError = document.getElementById("join-error")!;

  const savedName = localStorage.getItem("ptt-name");
  const savedRoom = localStorage.getItem("ptt-room");
  if (savedName) nameInput.value = savedName;
  if (savedRoom) roomInput.value = savedRoom;

  joinBtn.addEventListener("click", () => join(nameInput.value, roomInput.value, joinBtn, joinError));
  roomInput.addEventListener("keydown", (e) => {
    if (e.key === "Enter") join(nameInput.value, roomInput.value, joinBtn, joinError);
  });
}

function renderRoom(name: string, room: string) {
  app.innerHTML = `
    <header>
      <h1>📻 PTT</h1>
    </header>
    <div class="status-bar">
      <span class="status-dot" id="status-dot"></span>
      <span id="status-text">Kumokonekta...</span>
    </div>
    <div class="card">
      <p class="room-label">Channel</p>
      <p class="room-name">${escapeHtml(room)}</p>
      <div class="speaker-box" id="speaker-box">
        <span class="label">Status</span>
        <span class="name" id="speaker-name">Nakikinig...</span>
      </div>
      <div class="ptt-wrap">
        <button class="ptt-btn" id="ptt-btn" disabled>HOLD<br/>TO TALK</button>
        <p class="ptt-hint" id="ptt-hint">Hintayin ang mic permission...</p>
      </div>
      <div class="user-list">
        <h3>Online</h3>
        <ul id="user-list"></ul>
      </div>
      <button class="btn leave-btn" id="leave-btn">Umalis sa channel</button>
    </div>
  `;

  document.getElementById("leave-btn")!.addEventListener("click", leave);
  bindPttButton(document.getElementById("ptt-btn") as HTMLButtonElement);
}

async function join(name: string, room: string, btn: HTMLButtonElement, errEl: HTMLElement) {
  const trimmedName = name.trim();
  const trimmedRoom = room.trim();

  if (!trimmedName || !trimmedRoom) {
    errEl.textContent = "Ilagay ang pangalan at room.";
    errEl.classList.remove("hidden");
    return;
  }

  btn.disabled = true;
  errEl.classList.add("hidden");

  localStorage.setItem("ptt-name", trimmedName);
  localStorage.setItem("ptt-room", trimmedRoom);

  renderRoom(trimmedName, trimmedRoom);
  connectSocket(trimmedName, trimmedRoom);
  await setupMic();
}

function connectSocket(name: string, room: string) {
  const url = import.meta.env.DEV ? "http://localhost:3001" : undefined;
  socket = io(url, { transports: ["websocket", "polling"] });

  const statusDot = document.getElementById("status-dot")!;
  const statusText = document.getElementById("status-text")!;

  socket.on("connect", () => {
    statusDot.className = "status-dot online";
    statusText.textContent = "Connected";
    socket!.emit("join", { room, name }, (res: { ok: boolean; error?: string; users?: User[] }) => {
      if (!res?.ok) {
        statusText.textContent = res?.error ?? "Hindi makasali";
        return;
      }
      updateUserList(res.users ?? []);
      enablePttIfReady();
    });
  });

  socket.on("disconnect", () => {
    statusDot.className = "status-dot offline";
    statusText.textContent = "Disconnected";
    stopTalking();
  });

  socket.on("users", (users: User[]) => updateUserList(users));

  socket.on("floor-granted", () => startRecording());

  socket.on("floor-denied", ({ holder }: { holder: string }) => {
    const hint = document.getElementById("ptt-hint");
    if (hint) hint.textContent = `${holder} ang nagsasalita — hintayin`;
    isTalking = false;
    document.getElementById("ptt-btn")?.classList.remove("talking");
  });

  socket.on("ptt-start", ({ id, name: speakerName }: { id: string; name: string }) => {
    currentSpeakerId = id;
    setSpeaker(`${speakerName} nagsasalita...`, true);
    updateUserList(lastUsers);
  });

  socket.on("ptt-end", ({ id }: { id: string; name: string }) => {
    if (currentSpeakerId === id) {
      currentSpeakerId = null;
      setSpeaker("Nakikinig...", false);
      updateUserList(lastUsers);
    }
    enablePttIfReady();
  });

  socket.on("audio", ({ chunk, name: speakerName }: { from: string; name: string; chunk: ArrayBuffer }) => {
    setSpeaker(`${speakerName} nagsasalita...`, true);
    audioQueue.push(new Blob([chunk], { type: audioMime }));
    void playNext();
  });
}

function enablePttIfReady() {
  const pttBtn = document.getElementById("ptt-btn") as HTMLButtonElement | null;
  const hint = document.getElementById("ptt-hint");
  if (pttBtn && micStream && socket?.connected) {
    pttBtn.disabled = false;
    if (hint) hint.textContent = "Pindutin at hawakan para magsalita (o Space bar)";
  }
}

async function setupMic() {
  const pttBtn = document.getElementById("ptt-btn") as HTMLButtonElement;
  const hint = document.getElementById("ptt-hint")!;

  try {
    micStream = await navigator.mediaDevices.getUserMedia({
      audio: {
        echoCancellation: true,
        noiseSuppression: true,
        autoGainControl: true,
      },
      video: false,
    });

    if (MediaRecorder.isTypeSupported("audio/webm;codecs=opus")) {
      audioMime = "audio/webm;codecs=opus";
    }

    enablePttIfReady();
  } catch {
    hint.textContent = "Mic permission denied — kailangan ng microphone";
    pttBtn.disabled = true;
  }
}

function bindPttButton(btn: HTMLButtonElement) {
  const start = (e: Event) => {
    e.preventDefault();
    if (btn.disabled || isTalking) return;
    isTalking = true;
    btn.classList.add("talking");
    socket?.emit("ptt-down");
  };

  const stop = (e: Event) => {
    e.preventDefault();
    if (!isTalking) return;
    stopTalking();
  };

  btn.addEventListener("mousedown", start);
  btn.addEventListener("mouseup", stop);
  btn.addEventListener("mouseleave", stop);
  btn.addEventListener("touchstart", start, { passive: false });
  btn.addEventListener("touchend", stop, { passive: false });
  btn.addEventListener("touchcancel", stop, { passive: false });

  window.addEventListener("keydown", (e) => {
    if (e.code === "Space" && !e.repeat && document.activeElement?.tagName !== "INPUT") {
      e.preventDefault();
      start(e);
    }
  });
  window.addEventListener("keyup", (e) => {
    if (e.code === "Space") stop(e);
  });
}

function startRecording() {
  if (!micStream || recorder?.state === "recording") return;

  recorder = new MediaRecorder(micStream, { mimeType: audioMime });
  recorder.ondataavailable = (e) => {
    if (e.data.size > 0 && socket?.connected) {
      e.data.arrayBuffer().then((buf) => socket!.emit("audio", buf));
    }
  };
  recorder.start(120);

  const hint = document.getElementById("ptt-hint");
  if (hint) hint.textContent = "🔴 Nagsasalita ka...";
}

function stopTalking() {
  isTalking = false;
  document.getElementById("ptt-btn")?.classList.remove("talking");

  if (recorder?.state === "recording") recorder.stop();
  recorder = null;

  socket?.emit("ptt-up");
  enablePttIfReady();
}

async function playNext() {
  if (isPlaying || audioQueue.length === 0) return;
  isPlaying = true;

  const blob = audioQueue.shift()!;
  const url = URL.createObjectURL(blob);
  const audio = new Audio(url);

  try {
    await audio.play();
    await new Promise<void>((resolve) => {
      audio.onended = () => resolve();
      audio.onerror = () => resolve();
    });
  } catch {
    // autoplay blocked or decode error
  } finally {
    URL.revokeObjectURL(url);
    isPlaying = false;
    void playNext();
  }
}

function setSpeaker(name: string, active: boolean) {
  const box = document.getElementById("speaker-box");
  const el = document.getElementById("speaker-name");
  if (!el) return;
  el.textContent = name;
  box?.classList.toggle("active", active);
}

function updateUserList(users: User[]) {
  lastUsers = users;
  const list = document.getElementById("user-list");
  if (!list || !socket) return;

  list.innerHTML = users
    .map((u) => {
      const self = u.id === socket!.id ? " self" : "";
      const talking = u.id === currentSpeakerId ? " talking" : "";
      const label = u.id === socket!.id ? `${escapeHtml(u.name)} (ikaw)` : escapeHtml(u.name);
      return `<li class="${self}${talking}">${label}</li>`;
    })
    .join("");
}

function leave() {
  stopTalking();
  micStream?.getTracks().forEach((t) => t.stop());
  micStream = null;
  socket?.disconnect();
  socket = null;
  audioQueue.length = 0;
  currentSpeakerId = null;
  lastUsers = [];
  renderJoin();
}

renderJoin();
