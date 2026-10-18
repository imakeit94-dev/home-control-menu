"""Run the Swift API client against a disposable local HTTP fixture, never a real AC."""
import json
import subprocess
import sys
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

calls = []

class Handler(BaseHTTPRequestHandler):
    def log_message(self, *args):
        pass

    def reply(self, value, code=200):
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.end_headers()
        self.wfile.write(json.dumps(value).encode())

    def do_GET(self):
        if self.headers.get("Authorization") != "Bearer fixture-token":
            return self.reply({}, 401)
        if self.path.startswith("/unauthorized/"):
            return self.reply({}, 401)
        if self.path.startswith("/broken/"):
            return self.reply({}, 503)
        if self.path.startswith("/redirect/"):
            self.send_response(302)
            self.send_header("Location", "http://localhost:1/do-not-follow")
            self.end_headers()
            return
        if self.path == "/api/config":
            return self.reply({"unit_system": {"temperature": "°F"}})
        if self.path == "/api/services":
            return self.reply([
                {"domain": "fan", "services": {"set_percentage": {}}},
                {"domain": "light", "services": {"turn_on": {}}},
            ])
        if self.path == "/api/states":
            return self.reply([
                {"entity_id": "sensor.unrelated", "state": "OK", "attributes": {"temperature": "not-a-number"}},
                {"entity_id": "climate.bedroom", "state": "cool", "attributes": {
                    "friendly_name": "示例空调一", "temperature": 24, "current_temperature": None,
                    "target_temp_step": 0.5, "supported_features": 9, "fan_modes": ["auto", "low"]}},
                {"entity_id": "climate.living", "state": "unavailable", "attributes": {"friendly_name": "示例空调二"}},
                {"entity_id": "fan.fixture", "state": "on", "attributes": {"friendly_name": "测试风扇", "percentage": 40, "percentage_step": 10, "supported_features": 59}},
                {"entity_id": "light.indicator", "state": "off", "attributes": {"friendly_name": "指示灯", "supported_color_modes": ["onoff"]}},
                {"entity_id": "number.delay", "state": "-18", "attributes": {"min": -24, "max": -16, "step": 1}},
                {"entity_id": "select.mode", "state": "自然风", "attributes": {"options": ["自然风", "直吹风"]}},
                {"entity_id": "button.reset", "state": "unknown", "attributes": {"friendly_name": "重置滤芯"}},
            ])
        self.reply({}, 404)

    def do_POST(self):
        assert self.headers.get("Authorization") == "Bearer fixture-token"
        body = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
        calls.append((self.path, body))
        self.reply([])

server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
threading.Thread(target=server.serve_forever, daemon=True).start()
try:
    subprocess.run([sys.argv[1], f"http://127.0.0.1:{server.server_port}"], check=True)
    assert calls == [
        ("/api/services/climate/set_temperature", {"entity_id": "climate.bedroom", "temperature": 24.5}),
        ("/api/services/climate/set_hvac_mode", {"entity_id": "climate.bedroom", "hvac_mode": "off"}),
        ("/api/services/climate/set_fan_mode", {"entity_id": "climate.bedroom", "fan_mode": "auto"}),
        ("/api/services/fan/set_percentage", {"entity_id": "fan.fixture", "percentage": 30}),
        ("/api/services/light/turn_on", {"entity_id": "light.indicator", "brightness_pct": 70}),
        ("/api/services/number/set_value", {"entity_id": "number.delay", "value": -18}),
        ("/api/services/select/select_option", {"entity_id": "select.mode", "option": "自然风"}),
    ], calls
    print("All service paths and request bodies match the Home Assistant API contract.")
finally:
    server.shutdown()
