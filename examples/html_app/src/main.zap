import templates

# One request on a loopback ephemeral port, then exit. No web framework needed.
def serve_one(channel[int64] ports):
    auto env = templates.filesystem_environment("pages", True, True)
    auto listener = net.listen("127.0.0.1", 0)
    ports <- net.port(listener)
    auto connection = net.accept(listener)
    auto request = http.read_request(connection)
    dict[str, JsonValue] context = {
        "title": JsonValue.Str("People & roles"),
        "users": json.loads(
            "[{\"name\":\"Ada <script>\",\"role\":\"Developer\"},{\"name\":\"Zoë 😀\",\"role\":\"Designer\"}]",
        ),
    }
    auto page = templates.render_named(env, "index.html", context)
    http.respond(connection, 200, page, {"Content-Type": "text/html; charset=utf-8"})
    net.close_conn(connection)
    net.close_listener(listener)

def main():
    auto ports = channel[int64]()
    spawn serve_one(ports)
    auto port = <-ports
    auto response = http.get(http.url("127.0.0.1", port, "/"))
    assert http.status(response) == 200
    assert http.header(response, "content-type") == "text/html; charset=utf-8"
    auto body = http.body(response)
    assert "People &amp; roles" in body
    assert "Ada &lt;script&gt;" in body
    assert not "<script>" in body
    assert "Zoë 😀" in body
    assert "People — Zap templates" in body
    print(body)
    print("server-rendered HTML example: PASS")
