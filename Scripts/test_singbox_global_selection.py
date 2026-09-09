#!/usr/bin/env python3
"""Verify the generated Chinese Global selector changes both data and DNS peers.
Uses only loopback synthetic peers, without touching TUN or system proxy settings.
"""
import copy
import json
from pathlib import Path
import select
import socket
import struct
import subprocess
import sys
import tempfile
import time
import urllib.parse
import urllib.request
from test_singbox_modes import DNS, exact, free_port, server


class HTTP(DNS):
    def handle(self):
        self.request.recv(8192)
        self.request.sendall(b"HTTP/1.1 200 OK\r\nContent-Length: 2\r\nConnection: close\r\n\r\nOK")


class Peer(DNS):
    def handle(self):
        try:
            sock = self.request
            _, count = exact(sock, 2)
            exact(sock, count)
            sock.sendall(b"\x05\x00")
            _, _, _, kind = exact(sock, 4)
            if kind != 1:
                return
            host = socket.inet_ntoa(exact(sock, 4))
            port = struct.unpack("!H", exact(sock, 2))[0]
            if host != "127.0.0.1" or port not in self.server.allowed or self.server.fail:
                sock.sendall(b"\x05\x04\x00\x01" + bytes(6))
                return
            self.server.hits.append(port)
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


def check(binary, original):
    with server(DNS) as local, server(DNS) as remote, server(HTTP) as web, server(Peer) as a, server(Peer) as b, tempfile.TemporaryDirectory() as work:
        config = copy.deepcopy(original)
        api, inlet = free_port(), free_port()
        for peer in [a, b]:
            peer.allowed = [remote.server_address[1], web.server_address[1]]
            peer.hits = []
        nodes = {"test-proxy": a, "second-proxy": b}
        for outbound in config["outbounds"]:
            if outbound["type"] == "urltest":
                outbound["url"] = "http://127.0.0.1:9/"
            if outbound["tag"] in nodes:
                tag = outbound["tag"]
                outbound.clear()
                outbound.update(type="socks", tag=tag, server="127.0.0.1", server_port=nodes[tag].server_address[1], version="5")
        remotes = [s for s in config["dns"]["servers"] if s["tag"].startswith("remote")]
        config["dns"]["servers"] = [{"type": "tcp", "tag": "local", "server": "127.0.0.1", "server_port": local.server_address[1]}] + [
            {"type": "tcp", "tag": s["tag"], "server": "127.0.0.1", "server_port": remote.server_address[1], "detour": s["detour"]} for s in remotes]
        config["dns"].update(disable_cache=True, timeout="1s")
        config["inbounds"] = [{"type": "mixed", "tag": "test-http", "listen": "127.0.0.1", "listen_port": inlet}]
        config["experimental"]["cache_file"]["enabled"] = False
        config["experimental"]["clash_api"]["external_controller"] = f"127.0.0.1:{api}"
        path = Path(work) / "config.json"
        path.write_text(json.dumps(config))
        http = urllib.request.build_opener(urllib.request.ProxyHandler({}))
        def call(path, method="GET", data=None):
            request = urllib.request.Request(f"http://127.0.0.1:{api}{path}", method=method,
                data=json.dumps(data).encode() if data is not None else None, headers={"Content-Type": "application/json"})
            with http.open(request, timeout=2) as response:
                raw = response.read()
                return json.loads(raw) if raw else None
        def fetch(domain):
            with socket.create_connection(("127.0.0.1", inlet), timeout=3) as sock:
                port = web.server_address[1]
                sock.sendall(f"GET http://{domain}:{port}/ HTTP/1.1\r\nHost: {domain}:{port}\r\nConnection: close\r\n\r\n".encode())
                result = b""
                while chunk := sock.recv(8192):
                    result += chunk
                return result
        with open(Path(work) / "core.log", "w+") as log:
            process = subprocess.Popen([binary, "run", "-c", str(path)], cwd=work, stdout=log, stderr=log)
            try:
                for _ in range(80):
                    if process.poll() is not None:
                        log.seek(0)
                        raise AssertionError(log.read())
                    try:
                        status = call("/configs")
                        break
                    except OSError:
                        time.sleep(0.1)
                else:
                    raise AssertionError("core API did not start")
                assert status["mode"] == "规则判定", status
                call("/configs", "PATCH", {"mode": "全局代理"})
                group = next(r["outbound"] for r in config["route"]["rules"] if r.get("clash_mode") == "全局代理")
                endpoint = "/proxies/" + urllib.parse.quote(group, safe="")
                for tag, peer, other in [("test-proxy", a, b), ("second-proxy", b, a)]:
                    call(endpoint, "PUT", {"name": tag})
                    assert call(endpoint)["now"] == tag
                    peer.hits.clear()
                    other.hits.clear()
                    before = local.queries
                    assert fetch(tag + ".example.com").endswith(b"OK")
                    assert remote.server_address[1] in peer.hits, "DNS did not follow selection"
                    assert web.server_address[1] in peer.hits, "data did not follow selection"
                    assert not other.hits, other.hits
                    assert local.queries == before, "Global used direct DNS"
                b.fail = True
                time.sleep(2.2)
                a.hits.clear()
                before = local.queries
                try:
                    assert not fetch("failure.example.com").endswith(b"OK")
                except (OSError, EOFError):
                    pass
                assert not a.hits and local.queries == before, "failed manual selection fell back to another path"
                call("/configs", "PATCH", {"mode": "直接连接"})
                a.hits.clear()
                b.hits.clear()
                before = local.queries
                assert fetch("direct.example.com").endswith(b"OK")
                assert local.queries > before and not a.hits and not b.hits
                print("PASS Chinese default/modes: selected A then B changes data and DNS; Direct uses neither proxy")
            finally:
                process.terminate()
                try:
                    process.wait(timeout=4)
                except subprocess.TimeoutExpired:
                    process.kill()
                    process.wait()


if __name__ == "__main__":
    check(str(Path(sys.argv[1]).resolve()), json.loads(Path(sys.argv[2]).read_text()))
