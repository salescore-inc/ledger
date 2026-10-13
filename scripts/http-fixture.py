import http.server
import time
import signal
import pathlib
import sys
import socketserver

# Swift Testing on Linux can pass a blocked SIGTERM mask to child processes.
signal.pthread_sigmask(signal.SIG_UNBLOCK, {signal.SIGTERM})
# Test hosts can also inherit an ignored disposition; termination must reap this fixture.
signal.signal(signal.SIGTERM, signal.SIG_DFL)

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

class FixtureServer(http.server.ThreadingHTTPServer):
    def server_bind(self):
        # This loopback-only fixture must not wait for external reverse DNS.
        socketserver.TCPServer.server_bind(self)
        self.server_name = 'localhost'
        self.server_port = self.server_address[1]

server = FixtureServer(('127.0.0.1', 0), Handler)
if len(sys.argv) == 2:
    pathlib.Path(sys.argv[1]).write_text(str(server.server_port))
else:
    print(server.server_port, flush=True)
server.serve_forever()
