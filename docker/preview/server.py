#!/usr/bin/env python3
# GameBox — Preview Server
# Sirve el stream MJPEG desde ffmpeg capturando PipeWire
# y una página HTML con la preview + estado.

import http.server
import subprocess
import threading
import os
import signal
import json
import time

PORT = int(os.environ.get("PREVIEW_PORT", "48090"))
FFMPEG_PATH = os.environ.get("FFMPEG_PATH", "ffmpeg")
PIPEWIRE_INPUT = os.environ.get("PIPEWIRE_INPUT", "pipewire-0")
INSTANCE_NAME = os.environ.get("INSTANCE_NAME", "gamebox")

# Estado del servidor
server_status = {
    "instance": INSTANCE_NAME,
    "gamescope_running": False,
    "sunshine_running": False,
    "stream_active": False,
    "uptime": time.time()
}

ffmpeg_proc = None

def get_pipewire_nodes():
    """Detecta nodos PipeWire activos (para detectar Gamescope)"""
    try:
        result = subprocess.run(
            ["pw-cli", "list-objects", "Node"],
            capture_output=True, text=True, timeout=3
        )
        return result.stdout
    except:
        return ""

def get_status():
    """Actualiza el estado del servidor"""
    pw_nodes = get_pipewire_nodes()
    server_status["gamescope_running"] = "gamescope" in pw_nodes.lower() or "Steam" in pw_nodes
    server_status["sunshine_running"] = (
        subprocess.run(["pgrep", "-x", "sunshine"], capture_output=True).returncode == 0
    )
    server_status["stream_active"] = ffmpeg_proc is not None and ffmpeg_proc.poll() is None
    return server_status

class PreviewHandler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == "/":
            self.send_response(200)
            self.send_header("Content-type", "text/html; charset=utf-8")
            self.end_headers()
            html_path = os.path.join(os.path.dirname(__file__), "index.html")
            try:
                with open(html_path, "rb") as f:
                    self.wfile.write(f.read())
            except:
                self.wfile.write(b"<h1>GameBox Preview</h1><p>Error loading index.html</p>")
        
        elif self.path == "/preview":
            # Stream MJPEG desde ffmpeg
            global ffmpeg_proc
            self.send_response(200)
            self.send_header("Content-type", "multipart/x-mixed-replace; boundary=frame")
            self.send_header("Cache-Control", "no-cache")
            self.send_header("Connection", "close")
            self.end_headers()

            try:
                ffmpeg_proc = subprocess.Popen(
                    [FFMPEG_PATH,
                     "-f", "pipewire",
                     "-i", PIPEWIRE_INPUT,
                     "-f", "mpjpeg",
                     "-q:v", "5",
                     "-update", "1",
                     "-"],
                    stdout=subprocess.PIPE,
                    stderr=subprocess.DEVNULL
                )

                while ffmpeg_proc.poll() is None:
                    data = ffmpeg_proc.stdout.read(65536)
                    if not data:
                        break
                    try:
                        self.wfile.write(data)
                        self.wfile.flush()
                    except BrokenPipeError:
                        break
            except Exception as e:
                print(f"[Preview] Error: {e}")
            finally:
                if ffmpeg_proc:
                    ffmpeg_proc.kill()
                    ffmpeg_proc = None
        
        elif self.path == "/status":
            self.send_response(200)
            self.send_header("Content-type", "application/json")
            self.send_header("Access-Control-Allow-Origin", "*")
            self.end_headers()
            self.wfile.write(json.dumps(get_status()).encode())
        
        elif self.path == "/sunshine":
            # Proxy simple al estado de Sunshine
            self.send_response(302)
            self.send_header("Location", "http://localhost:47990")
            self.end_headers()
        
        else:
            self.send_response(404)
            self.end_headers()
    
    def log_message(self, format, *args):
        pass  # Silenciar logs del servidor

def main():
    print(f"[Preview] Servidor iniciado en puerto {PORT}")
    print(f"[Preview] PipeWire input: {PIPEWIRE_INPUT}")
    
    server = http.server.HTTPServer(("0.0.0.0", PORT), PreviewHandler)
    
    def shutdown(sig, frame):
        print("[Preview] Cerrando servidor...")
        server.shutdown()
    
    signal.signal(signal.SIGINT, shutdown)
    signal.signal(signal.SIGTERM, shutdown)
    
    server.serve_forever()

if __name__ == "__main__":
    main()
