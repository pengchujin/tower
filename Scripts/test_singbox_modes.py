#!/usr/bin/env python3
"""Run Tower's synthetic exports through the real sing-box core on loopback.

Usage: test_singbox_modes.py CORE FIXTURE_DIRECTORY
Only transport endpoints and listeners are replaced; generated routing, DNS
rules and group membership remain intact. No TUN/system proxy is modified.
"""
import contextlib
import copy
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
import urllib.request
import urllib.parse


def exact(sock, size):
    result = b""
    while len(result) < size:
        data = sock.recv(size - len(result))
        if not data:
            raise EOFError()
        result += data
    return result


class TCP(socketserver.ThreadingTCPServer):
    allow_reuse_address = True
    daemon_threads = True


class DNS(socketserver.BaseRequestHandler):
    def handle(self):
        try:
            while True:
                data = exact(self.request, struct.unpack("!H", exact(self.request, 2))[0])
                self.server.queries += 1
                end = 12
                while data[end]:
                    end += 1 + data[end]
                end += 1
                answer = b"\xc0\x0c\x00\x01\x00\x01\x00\x00\x00\x00\x00\x04\x7f\x00\x00\x01"
                response = data[:2] + struct.pack("!HHHHH", 0x8180, 1, 1, 0, 0) + data[12:end + 4] + answer
                self.request.sendall(struct.pack("!H", len(response)) + response)
        except (OSError, EOFError):
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
                sock.sendall(b"\x05\x04\x00\x01" + bytes(6))
                return
            host = socket.inet_ntoa(exact(sock, 4))
            port = struct.unpack("!H", exact(sock, 2))[0]
            if self.server.fail or host != "127.0.0.1" or port != self.server.dns_port:
                sock.sendall(b"\x05\x04\x00\x01" + bytes(6))
                return
            self.server.connections += 1
            with socket.create_connection((host, port), timeout=2) as upstream:
                sock.sendall(b"\x05\x00\x00\x01" + bytes(6))
                while True:
                    ready, _, _ = select.select([sock, upstream], [], [], 2)
                    if self.server.fail:
                        return
                    for source in ready:
                        data = source.recv(65536)
                        if not data:
                            return
                        (upstream if source is sock else sock).sendall(data)
        except (OSError, EOFError):
            pass


@contextlib.contextmanager
def server(handler):
    with TCP(("127.0.0.1", 0), handler) as value:
        value.queries = value.connections = 0
        value.fail = False
        threading.Thread(target=value.serve_forever, daemon=True).start()
        try:
            yield value
        finally:
            value.shutdown()


def free_port():
    with socket.socket() as sock:
        sock.bind(("127.0.0.1", 0))
        return sock.getsockname()[1]


def query(port, domain):
    labels = b"".join(bytes([len(label)]) + label.encode() for label in domain.split(".")) + b"\0"
    packet = struct.pack("!HHHHHH", 123, 0x100, 1, 0, 0, 0) + labels + b"\x00\x01\x00\x01"
    with socket.create_connection(("127.0.0.1", port), timeout=3) as sock:
        sock.sendall(struct.pack("!H", len(packet)) + packet)
        response = exact(sock, struct.unpack("!H", exact(sock, 2))[0])
        return response[3] & 15


def check(binary, original, strict):
    with server(DNS) as local, server(DNS) as remote, server(SOCKS) as proxy, tempfile.TemporaryDirectory() as work:
        proxy.dns_port = remote.server_address[1]
        config = copy.deepcopy(original)
        port, api = free_port(), free_port()
        config["inbounds"] = [{"type": "direct", "tag": "test-dns", "listen": "127.0.0.1", "listen_port": port}]
        for outbound in config["outbounds"]:
            if outbound["type"] == "urltest":
                outbound["url"] = "http://127.0.0.1:9/"
            if outbound["tag"] == "test-proxy":
                outbound.clear()
                outbound.update(type="socks", tag="test-proxy", server="127.0.0.1", server_port=proxy.server_address[1], version="5")
        remotes = [s for s in config["dns"]["servers"] if s["tag"].startswith("remote")]
        config["dns"]["servers"] = [
            {"type": "tcp", "tag": "local", "server": "127.0.0.1", "server_port": local.server_address[1]},
        ] + [{"type": "tcp", "tag": s["tag"], "server": "127.0.0.1",
              "server_port": remote.server_address[1], "detour": s["detour"]} for s in remotes]
        config["dns"]["timeout"] = "1s"
        config["dns"]["disable_cache"] = True
        config["experimental"]["cache_file"]["enabled"] = False
        config["experimental"]["clash_api"]["external_controller"] = f"127.0.0.1:{api}"
        path = Path(work) / "config.json"
        path.write_text(json.dumps(config))
        log = open(Path(work) / "core.log", "w+")
        process = subprocess.Popen([binary, "run", "-c", str(path)], cwd=work, stdout=log, stderr=log)
        # Ignore host proxy variables even when the user runs Surge on this Mac.
        http = urllib.request.build_opener(urllib.request.ProxyHandler({}))

        def mode(value):
            request = urllib.request.Request(f"http://127.0.0.1:{api}/configs", data=json.dumps({"mode": value}).encode(), method="PATCH", headers={"Content-Type": "application/json"})
            with http.open(request, timeout=2):
                pass

        try:
            for _ in range(80):
                if process.poll() is not None:
                    log.seek(0)
                    raise AssertionError(log.read())
                try:
                    mode("规则判定")
                    break
                except OSError:
                    time.sleep(0.1)
            else:
                raise AssertionError("core API did not start")
            for selected, domain, expected in [
                ("规则判定", "private.example.com", "remote"),
                ("规则判定", "other.example.com", "remote" if strict else "local"),
                ("全局代理", "other.example.com", "remote"),
                ("直接连接", "private.example.com", "local"),
                ("规则判定", "unknown.invalid", "remote"),
            ]:
                mode(selected)
                before = local.queries, remote.queries
                assert query(port, domain) == 0
                counts = local.queries - before[0], remote.queries - before[1]
                assert (counts[0] > 0 and counts[1] == 0) if expected == "local" else (counts[0] == 0 and counts[1] > 0), (selected, domain, counts)
            mode("规则判定")
            assert query(port, "ad.invalid") == 5
            assert proxy.connections > 0, "DNS must actually traverse the SOCKS peer"
            proxy.fail = True
            time.sleep(2.2)  # let the fixture close any reused proxy connection
            before = local.queries
            try:
                assert query(port, "failure.invalid") != 0
            except (OSError, EOFError):
                pass
            assert local.queries == before, "failed proxy DNS leaked to direct DNS"
            print(f"PASS {'strict' if strict else 'standard'}: Chinese modes, ordered domains, reject, DIRECT-selected group, proxy failure")
        finally:
            process.terminate()
            try:
                process.wait(timeout=4)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait()
            log.close()


if __name__ == "__main__":
    binary = str(Path(sys.argv[1]).resolve())
    directory = Path(sys.argv[2])
    for strict in [False, True]:
        check(binary, json.loads((directory / ("strict.json" if strict else "standard.json")).read_text()), strict)
