"""Minimal static server for Godot 4 Web export.

Sets the COOP/COEP headers required by SharedArrayBuffer (Godot threads)
and serves the export directory over HTTP (file:// will NOT work).
"""
import functools
import http.server
import os
import socketserver
import sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "docs"))
PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 8123


class Handler(http.server.SimpleHTTPRequestHandler):
    def end_headers(self):
        self.send_header("Cross-Origin-Opener-Policy", "same-origin")
        self.send_header("Cross-Origin-Embedder-Policy", "require-corp")
        self.send_header("Cross-Origin-Resource-Policy", "same-origin")
        self.send_header("Cache-Control", "no-cache")
        super().end_headers()

    def log_message(self, fmt, *args):
        sys.stderr.write("[serve] %s\n" % (fmt % args))


if __name__ == "__main__":
    os.chdir(ROOT)
    socketserver.TCPServer.allow_reuse_address = True
    handler = functools.partial(Handler, directory=ROOT)
    with socketserver.ThreadingTCPServer(("127.0.0.1", PORT), handler) as httpd:
        sys.stderr.write("Serving %s at http://127.0.0.1:%d\n" % (ROOT, PORT))
        httpd.serve_forever()
