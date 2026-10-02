import http.server
import time

class Handler(http.server.BaseHTTPRequestHandler):
    def log_message(self, *args):
        pass
    def do_GET(self):
        if self.path == '/redirect':
            self.send_response(302)
            self.send_header('Location', '/ok')
            self.send_header('Content-Length', '0')
            self.end_headers()
            return
        self.send_response(200)
        if self.path == '/length':
            self.send_header('Content-Length', '1000000')
        self.end_headers()
        self.wfile.flush()
        try:
            if self.path == '/length':
                time.sleep(1)
            if self.path == '/slow':
                time.sleep(5)
            self.wfile.write(b'x' * (1000000 if self.path == '/length' else 1000 if self.path == '/body' else 2))
        except (BrokenPipeError, ConnectionResetError):
            pass

server = http.server.ThreadingHTTPServer(('127.0.0.1', 0), Handler)
print(server.server_port, flush=True)
server.serve_forever()
