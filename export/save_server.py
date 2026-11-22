"""Tiny local helper for sprite-lab.html: receives exported PNG/JSON sheets and writes them next to this file
(and into ../godot/character/art/ when the Godot project exists).

Run:  python export/save_server.py      (listens on http://localhost:8140, localhost only)
Then press "Save to export/" in sprite-lab.html.
"""
import http.server, os, re, sys

HERE = os.path.dirname(os.path.abspath(__file__))
GODOT_ART = os.path.join(os.path.dirname(HERE), 'godot', 'character', 'art')   # also refresh the Godot project's art if present
NAME_OK = re.compile(r'^[a-z0-9_\-]+\.(png|json)$')


class H(http.server.BaseHTTPRequestHandler):
    def _cors(self):
        self.send_header('Access-Control-Allow-Origin', '*')
        self.send_header('Access-Control-Allow-Methods', 'POST, OPTIONS')
        self.send_header('Access-Control-Allow-Headers', 'Content-Type')

    def do_OPTIONS(self):
        self.send_response(204); self._cors(); self.end_headers()

    def do_POST(self):
        name = self.path.rsplit('/', 1)[-1]
        if not NAME_OK.match(name):
            self.send_response(400); self._cors(); self.end_headers(); return
        n = int(self.headers.get('Content-Length', 0))
        if n > 20_000_000:
            self.send_response(413); self._cors(); self.end_headers(); return
        data = self.rfile.read(n)
        for d in [HERE] + ([GODOT_ART] if os.path.isdir(GODOT_ART) else []):
            with open(os.path.join(d, name), 'wb') as f:
                f.write(data)
        self.send_response(200); self._cors(); self.end_headers(); self.wfile.write(b'ok')
        print('saved', name, n, 'bytes')


if __name__ == '__main__':
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 8140
    http.server.HTTPServer(('127.0.0.1', port), H).serve_forever()
