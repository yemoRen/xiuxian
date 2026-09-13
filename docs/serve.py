"""Local static server for the Godot 4 Web build.

Godot Web exports load a .wasm file, so they must be served over HTTP —
opening index.html directly with file:// will not work.

Usage:  python serve.py [port]     (default port 8130)
Then open http://127.0.0.1:8130/
"""
import functools
import http.server
import os
import socketserver
import sys

ROOT = os.path.dirname(os.path.abspath(__file__))
PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 8130


class Handler(http.server.SimpleHTTPRequestHandler):
    def end_headers(self):
        self.send_header("Cross-Origin-Opener-Policy", "same-origin")
        self.send_header("Cross-Origin-Embedder-Policy", "require-corp")
        self.send_header("Cache-Control", "no-cache")
        super().end_headers()

    def log_message(self, fmt, *args):
        sys.stderr.write("[serve] %s\n" % (fmt % args))


if __name__ == "__main__":
    socketserver.TCPServer.allow_reuse_address = True
    handler = functools.partial(Handler, directory=ROOT)
    with socketserver.ThreadingTCPServer(("127.0.0.1", PORT), handler) as httpd:
        sys.stderr.write("Serving %s\nOpen http://127.0.0.1:%d/\n" % (ROOT, PORT))
        try:
            httpd.serve_forever()
        except KeyboardInterrupt:
            sys.stderr.write("\nStopped.\n")
