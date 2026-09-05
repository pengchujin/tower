#!/usr/bin/env python3
"""Exercise a generated sing-box downloader with no system DNS or TUN needed.

Usage: python3 Scripts/test_singbox_bootstrap.py /path/to/sing-box generated.json
The loopback SOCKS peer rejects domain requests, like a proxy whose DNS is down.
A private DNS fixture can resolve the rule host. Only configuration dialer fields
are retained; no subscription credentials or remote endpoints are contacted.
"""
import contextlib
import copy
import http.server
import json
from pathlib import Path
import select
import socket
import socketserver
import struct
import subprocess
import sys
import tempfile
import threading
import time


def exact(sock, size):
    result = b""
    while len(result) < size:
        chunk = sock.recv(size - len(result))
        if not chunk:
            raise EOFError()
        result += chunk
    return result


class DNS(socketserver.BaseRequestHandler):
    def handle(self):
        data, sock = self.request
        end = 12
        while data[end]:
            end += data[end] + 1
        end += 1
        question = data[12:end + 4]
        is_a = data[end:end + 2] == b"\x00\x01"
        answer = b"\xc0\x0c\x00\x01\x00\x01\x00\x00\x00\x3c\x00\x04\x7f\x00\x00\x01" if is_a else b""
        sock.sendto(data[:2] + struct.pack("!HHHHH", 0x8180, 1, int(is_a), 0, 0) + question + answer, self.client_address)


class Rules(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        if getattr(self.server, "fail_requests", False):
            self.send_error(503)
            return
        body = b'{"version":3,"rules":[{"domain_suffix":["example.com"]}]}'
        self.send_response(200)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *_):
        pass


class SOCKS(socketserver.BaseRequestHandler):
    def handle(self):
        try:
            sock = self.request
            _, count = exact(sock, 2)
            exact(sock, count)
            sock.sendall(b"\x05\x00")
            _, _, _, kind = exact(sock, 4)
            if kind != 1:
                # Domain lookup at the proxy is unavailable. An explicit local
                # resolver must turn cold-rules.invalid into an IPv4 address.
                sock.sendall(b"\x05\x04\x00\x01" + bytes(6))
                return
            address = socket.inet_ntoa(exact(sock, 4))
            port = struct.unpack("!H", exact(sock, 2))[0]
            if address != "127.0.0.1" or port != self.server.rule_port:
                raise ValueError("fixture must stay on loopback")
            with socket.create_connection((address, port), timeout=5) as upstream:
                sock.sendall(b"\x05\x00\x00\x01" + bytes(6))
                while True:
                    ready, _, _ = select.select([sock, upstream], [], [], 5)
                    if not ready:
                        return
                    for source in ready:
                        data = source.recv(65536)
                        if not data:
                            return
                        (upstream if source is sock else sock).sendall(data)
        except (OSError, EOFError):
            pass


class TCP(socketserver.ThreadingTCPServer):
    daemon_threads = True


def run(binary, config, directory=None):
    context = tempfile.TemporaryDirectory(prefix="tower-bootstrap-") if directory is None else contextlib.nullcontext(directory)
    with context as directory:
        path = Path(directory) / "config.json"
        path.write_text(json.dumps(config))
        checked = subprocess.run([binary, "check", "-c", str(path)], capture_output=True, timeout=10)
        if checked.returncode:
            raise RuntimeError(checked.stderr.decode())
        log = Path(directory) / "run.log"
        with log.open("w") as output:
            process = subprocess.Popen([binary, "run", "-c", str(path)], cwd=directory, stdout=output, stderr=output)
            try:
                deadline = time.monotonic() + 12
                while time.monotonic() < deadline:
                    content = log.read_text()
                    if "sing-box started" in content:
                        return True
                    if process.poll() is not None:
                        return False
                    time.sleep(0.05)
                return False
            finally:
                if process.poll() is None:
                    process.terminate()
                process.wait(timeout=5)


def main():
    binary = str(Path(sys.argv[1]).resolve())
    generated = json.loads(Path(sys.argv[2]).read_text())
    client = copy.deepcopy(generated["http_clients"][0])
    with socketserver.ThreadingUDPServer(("127.0.0.1", 0), DNS) as dns, TCP(("127.0.0.1", 0), Rules) as http, TCP(("127.0.0.1", 0), SOCKS) as socks:
        socks.rule_port = http.server_address[1]
        for server in [dns, http, socks]:
            threading.Thread(target=server.serve_forever, daemon=True).start()
        client["detour"] = "fixture-proxy"
        config = {
            "log": {"level": "info"},
            "dns": {"servers": [{"type": "udp", "tag": "local", "server": "127.0.0.1", "server_port": dns.server_address[1]}], "strategy": "ipv4_only"},
            "http_clients": [client],
            "outbounds": [{"type": "socks", "tag": "fixture-proxy", "server": "127.0.0.1", "server_port": socks.server_address[1]}],
            "route": {"default_domain_resolver": generated["route"]["default_domain_resolver"], "default_http_client": client["tag"], "rule_set": [{"type": "remote", "tag": "cold", "format": "source", "url": f"http://cold-rules.invalid:{http.server_address[1]}/rules.json"}], "rules": [{"rule_set": ["cold"], "outbound": "fixture-proxy"}]}
        }
        # Each launch gets a fresh directory, so cache cannot mask a failure.
        baseline = copy.deepcopy(config)
        baseline["http_clients"][0].pop("domain_resolver", None)
        assert not run(binary, baseline), "fault injection did not reproduce the old failure"
        assert run(binary, config), "generated downloader still depends on proxy/system DNS"
        direct = copy.deepcopy(config)
        direct["http_clients"][0].pop("detour", None)
        assert run(binary, direct), "direct-only cold startup failed"
        cached = copy.deepcopy(config)
        cached["experimental"] = {"cache_file": {"enabled": True}}
        with tempfile.TemporaryDirectory(prefix="tower-rule-cache-") as directory:
            assert run(binary, cached, directory), "initial cache population failed"
            http.fail_requests = True
            assert run(binary, cached, directory), "warm start did not reuse the valid cache"
            assert not run(binary, config), "fresh download failure was hidden"
            http.fail_requests = False
            assert run(binary, config), "retry after download recovery failed"
        for server in [dns, http, socks]:
            server.shutdown()
    print("PASS: old downloader fails; proxy/direct cold starts, warm cache, download failure and recovery verified")


if __name__ == "__main__":
    main()
