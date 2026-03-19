import json
import os
import subprocess
from pathlib import Path


def test_device_center_renders_malicious_values_as_text(tmp_path):
    node = os.getenv("NODE_BIN") or "node"
    try:
        subprocess.run([node, "--version"], check=True, capture_output=True, text=True)  # nosec B603
    except Exception:
        return

    repo_root = Path(__file__).resolve().parents[2]
    source_path = repo_root / "static" / "js" / "device_center.js"
    script_path = tmp_path / "device_center_render_test.js"

    script_path.write_text(
        f"""
const fs = require('fs');
const vm = require('vm');

const source = fs.readFileSync({json.dumps(str(source_path))}, 'utf8');

class Element {{
  constructor(tagName) {{
    this.tagName = tagName.toLowerCase();
    this.children = [];
    this.attributes = {{}};
    this.style = {{}};
    this.className = '';
    this._textContent = '';
    this.value = '';
    this.disabled = false;
    this.type = '';
  }}

  appendChild(child) {{
    this.children.push(child);
    return child;
  }}

  set textContent(value) {{
    this._textContent = String(value);
    this.children = [];
  }}

  get textContent() {{
    return this._textContent;
  }}

  setAttribute(name, value) {{
    this.attributes[name] = String(value);
  }}

  getAttribute(name) {{
    return Object.prototype.hasOwnProperty.call(this.attributes, name) ? this.attributes[name] : null;
  }}

  addEventListener() {{}}

  querySelectorAll(selector) {{
    const attrMatch = selector.match(/^\\[([^=\\]]+)(?:="([^"]*)")?\\]$/);
    const results = [];
    if (!attrMatch) return results;
    const attrName = attrMatch[1];
    const attrValue = attrMatch[2];

    function walk(node) {{
      const current = node.getAttribute ? node.getAttribute(attrName) : null;
      if (current !== null && (attrValue === undefined || current === attrValue)) {{
        results.push(node);
      }}
      if (node.children) {{
        node.children.forEach(walk);
      }}
    }}

    walk(this);
    return results;
  }}

  querySelector(selector) {{
    const matches = this.querySelectorAll(selector);
    return matches.length > 0 ? matches[0] : null;
  }}
}}

const tbody = new Element('tbody');
const document = {{
  createElement(tag) {{
    return new Element(tag);
  }},
  querySelector(selector) {{
    if (selector === '[data-devices-body]') return tbody;
    return null;
  }},
  addEventListener() {{}},
}};

const context = {{
  document,
  window: {{ confirm: () => true }},
  console,
  setTimeout,
  clearTimeout,
  Date,
  JSON,
  Promise,
}};

vm.createContext(context);
vm.runInContext(source, context);

context.renderDevices({{
  devices: [{{
    id: 7,
    name: '<img src=x onerror=alert(1)>',
    device_type: '<svg onload=alert(1)>',
    ip_address: '<script>alert(1)</script>',
    last_handshake: null,
    server_id: null,
  }}],
  servers: [{{
    server_id: 'region-1',
    location: '<img src=x onerror=alert(2)>',
  }}],
}});

function serialize(node) {{
  return {{
    tag: node.tagName,
    text: node.textContent,
    attrs: node.attributes,
    children: (node.children || []).map(serialize),
  }};
}}

process.stdout.write(JSON.stringify(serialize(tbody)));
""",
        encoding="utf-8",
    )

    proc = subprocess.run(  # nosec B603
        [node, str(script_path)],
        check=True,
        capture_output=True,
        text=True,
    )
    rendered = json.loads(proc.stdout)

    def walk(node):
        yield node
        for child in node.get("children", []):
            yield from walk(child)

    tags = [node["tag"] for node in walk(rendered)]
    texts = [node["text"] for node in walk(rendered)]

    assert "img" not in tags
    assert "script" not in tags
    assert "<img src=x onerror=alert(1)>" in texts
    assert "<svg onload=alert(1)>" in texts
    assert "<script>alert(1)</script>" in texts

