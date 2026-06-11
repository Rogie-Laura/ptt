import express from "express";
import { createServer } from "http";
import path from "path";
import { fileURLToPath } from "url";
import { Server } from "socket.io";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const PORT = Number(process.env.PORT) || 3001;
const isProd = process.env.NODE_ENV === "production";

const app = express();
const httpServer = createServer(app);
const io = new Server(httpServer, {
  cors: { origin: true },
  maxHttpBufferSize: 1e7,
});

app.get("/health", (_req, res) => {
  res.json({ ok: true, service: "ptt-server" });
});

interface RoomState {
  floorHolder: string | null;
  users: Map<string, { name: string }>;
}

const rooms = new Map<string, RoomState>();

function getRoom(roomId: string): RoomState {
  let room = rooms.get(roomId);
  if (!room) {
    room = { floorHolder: null, users: new Map() };
    rooms.set(roomId, room);
  }
  return room;
}

function userList(room: RoomState) {
  return Array.from(room.users.entries()).map(([id, u]) => ({
    id,
    name: u.name,
  }));
}

function broadcastUsers(roomId: string) {
  const room = getRoom(roomId);
  io.to(roomId).emit("users", userList(room));
}

io.on("connection", (socket) => {
  let roomId: string | null = null;
  let userName = "";

  socket.on("join", ({ room, name }: { room: string; name: string }, ack) => {
    const trimmedRoom = room.trim().slice(0, 32);
    const trimmedName = name.trim().slice(0, 24);

    if (!trimmedRoom || !trimmedName) {
      ack?.({ ok: false, error: "Kailangan ng room at pangalan." });
      return;
    }

    if (roomId) {
      socket.leave(roomId);
      const old = getRoom(roomId);
      old.users.delete(socket.id);
      if (old.floorHolder === socket.id) old.floorHolder = null;
      broadcastUsers(roomId);
      if (old.users.size === 0) rooms.delete(roomId);
    }

    roomId = trimmedRoom;
    userName = trimmedName;
    socket.join(roomId);

    const roomState = getRoom(roomId);
    roomState.users.set(socket.id, { name: userName });
    broadcastUsers(roomId);

    ack?.({ ok: true, users: userList(roomState) });
  });

  socket.on("ptt-down", () => {
    if (!roomId) return;
    const room = getRoom(roomId);

    if (room.floorHolder && room.floorHolder !== socket.id) {
      const holder = room.users.get(room.floorHolder)?.name ?? "Someone";
      socket.emit("floor-denied", { holder });
      return;
    }

    room.floorHolder = socket.id;
    socket.emit("floor-granted");
    socket.to(roomId).emit("ptt-start", { id: socket.id, name: userName });
  });

  socket.on("ptt-up", () => {
    if (!roomId) return;
    const room = getRoom(roomId);
    if (room.floorHolder !== socket.id) return;

    room.floorHolder = null;
    socket.to(roomId).emit("ptt-end", { id: socket.id, name: userName });
  });

  socket.on("audio", (chunk: ArrayBuffer) => {
    if (!roomId) return;
    const room = getRoom(roomId);
    if (room.floorHolder !== socket.id) return;

    socket.to(roomId).emit("audio", {
      from: socket.id,
      name: userName,
      chunk,
    });
  });

  socket.on("disconnect", () => {
    if (!roomId) return;
    const room = getRoom(roomId);
    room.users.delete(socket.id);

    if (room.floorHolder === socket.id) {
      room.floorHolder = null;
      socket.to(roomId).emit("ptt-end", { id: socket.id, name: userName });
    }

    broadcastUsers(roomId);
    if (room.users.size === 0) rooms.delete(roomId);
  });
});

if (isProd) {
  const dist = path.join(__dirname, "../dist");
  app.use(express.static(dist));
  app.get("/{*splat}", (_req, res) => {
    res.sendFile(path.join(dist, "index.html"));
  });
}

httpServer.listen(PORT, "0.0.0.0", () => {
  console.log(`PTT server running on port ${PORT}`);
});
