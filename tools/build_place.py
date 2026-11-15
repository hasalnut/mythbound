#!/usr/bin/env python3
"""Packs src/ into Mythbound.rbxlx, a place file Roblox Studio can open directly.

It follows Rojo's naming rules, so the same src/ folder also works with `rojo serve`:
  Name.server.luau -> Script, Name.client.luau -> LocalScript, Name.luau -> ModuleScript,
  folders -> Folder.

Usage:  python3 tools/build_place.py            (writes Mythbound.rbxlx in the repo root)
        python3 tools/build_place.py --check    (only runs the Luau sanity checks)

With Rojo installed, `rojo build -o Mythbound.rbxlx` gives the same result.
"""
from __future__ import annotations

import pathlib
import re
import sys
from xml.sax.saxutils import escape

ROOT = pathlib.Path(__file__).resolve().parent.parent
SRC = ROOT / "src"
OUT = ROOT / "Mythbound.rbxlx"

_ref = 0


def ref() -> str:
    global _ref
    _ref += 1
    return f"RBX{_ref:08X}"


def prop(kind: str, name: str, value: str) -> str:
    return f'<{kind} name="{name}">{value}</{kind}>'


def source_prop(code: str) -> str:
    # CDATA can't contain "]]>", so split it across two sections if it ever appears.
    code = code.replace("]]>", "]]]]><![CDATA[>")
    return f'<ProtectedString name="Source"><![CDATA[{code}]]></ProtectedString>'


def item(cls: str, name: str, props: list[str] | None = None, children: list[str] | None = None) -> str:
    body = [prop("string", "Name", escape(name))] + (props or [])
    kids = "".join(children or [])
    return f'<Item class="{cls}" referent="{ref()}"><Properties>{"".join(body)}</Properties>{kids}</Item>'


def script_item(path: pathlib.Path) -> str:
    name = path.name
    code = path.read_text(encoding="utf-8")
    if name.endswith(".server.luau"):
        return item("Script", name[: -len(".server.luau")], [source_prop(code)])
    if name.endswith(".client.luau"):
        return item("LocalScript", name[: -len(".client.luau")], [source_prop(code)])
    return item("ModuleScript", name[: -len(".luau")], [source_prop(code)])


def folder_item(name: str, directory: pathlib.Path) -> str:
    children = []
    for path in sorted(directory.iterdir()):
        if path.is_dir():
            children.append(folder_item(path.name, path))
        elif path.suffix == ".luau":
            children.append(script_item(path))
    return item("Folder", name, children=children)


def build() -> str:
    services = [
        # Streaming off for now: client code expects creatures and dummies to exist on every client.
        item("Workspace", "Workspace", [prop("bool", "StreamingEnabled", "false")]),
        item("Lighting", "Lighting", [prop("token", "Technology", "4")]),  # 4 = Future lighting
        item("ReplicatedStorage", "ReplicatedStorage", children=[folder_item("Shared", SRC / "shared")]),
        item("ServerScriptService", "ServerScriptService", children=[folder_item("Server", SRC / "server")]),
        item(
            "StarterPlayer",
            "StarterPlayer",
            [prop("float", "CameraMaxZoomDistance", "45"), prop("bool", "EnableMouseLockOption", "true")],
            [item("StarterPlayerScripts", "StarterPlayerScripts", children=[folder_item("Client", SRC / "client")])],
        ),
        item("Players", "Players", [prop("bool", "CharacterAutoLoads", "false"), prop("float", "RespawnTime", "3")]),
    ]
    return (
        '<roblox xmlns:xmime="http://www.w3.org/2005/05/xmlmime" '
        'xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" '
        'xsi:noNamespaceSchemaLocation="http://www.roblox.com/roblox.xsd" version="4">'
        + "".join(services)
        + "</roblox>\n"
    )


# --- Luau sanity checks -------------------------------------------------------------
# Not a real parser: it catches unbalanced blocks and brackets, which are the most common
# mistakes when code is written without Studio open. Studio's Script Analysis is the real check.

TOKEN = re.compile(
    r"--\[(=*)\[.*?\]\1\]"  # long comment
    r"|--[^\n]*"  # line comment
    r"|\[(=*)\[.*?\]\2\]"  # long string
    r'|"(?:\\.|[^"\\\n])*"'
    r"|'(?:\\.|[^'\\\n])*'"
    r"|`(?:\\.|[^`\\])*`"
    r"|[A-Za-z_][A-Za-z0-9_]*"
    r"|\d+(?:\.\d+)?(?:e[+-]?\d+)?|0x[0-9a-fA-F]+"
    r"|::|\.\.\.|\.\.|==|~=|<=|>=|->|\+=|-=|\*=|/=|[-+*/%^#<>=(){}\[\];:,.?|&]",
    re.S,
)

EXPRESSION_BEFORE_IF = {"=", "(", ",", "return", "and", "or", "{", "..", "+", "-", "*", "/", "not",
                        "==", "~=", "<", ">", "<=", ">=", "in", "+=", "-=", "*=", "/=", "then", "else", "["}


def check(path: pathlib.Path) -> list[str]:
    text = path.read_text(encoding="utf-8")
    tokens = [m.group(0) for m in TOKEN.finditer(text)]
    tokens = [t for t in tokens if not t.startswith("--")]
    problems: list[str] = []
    blocks: list[tuple[str, int]] = []  # (opener, bracket depth when it opened)
    brackets: list[str] = []
    pairs = {")": "(", "]": "[", "}": "{"}
    prev = ""

    def function_base() -> int:
        # Bracket depth of the innermost function: code inside `Connect(function() ... end)`
        # is statement code even though it sits inside parentheses.
        for opener, depth in reversed(blocks):
            if opener == "function":
                return depth
        return 0

    for i, tok in enumerate(tokens):
        if tok in ("(", "[", "{"):
            brackets.append(tok)
        elif tok in pairs:
            if not brackets or brackets[-1] != pairs[tok]:
                problems.append(f"unbalanced '{tok}' near: {' '.join(tokens[max(0, i - 10):i + 1])}")
                return problems
            brackets.pop()
        elif tok == "function":
            blocks.append(("function", len(brackets)))
        elif tok == "if":
            inside_expression = len(brackets) > function_base()
            if prev in EXPRESSION_BEFORE_IF and (prev not in ("then", "else") or inside_expression):
                pass  # if-expression: no `end`
            else:
                blocks.append(("if", len(brackets)))
        elif tok in ("do", "repeat"):
            blocks.append((tok, len(brackets)))
        elif tok == "until":
            if not blocks or blocks[-1][0] != "repeat":
                problems.append(f"'until' without 'repeat' near token {i}")
                return problems
            blocks.pop()
        elif tok == "end":
            if not blocks:
                problems.append(f"extra 'end' near: {' '.join(tokens[max(0, i - 12):i + 1])}")
                return problems
            blocks.pop()
        prev = tok
    if blocks:
        problems.append(f"missing 'end' for: {[b[0] for b in blocks]}")
    if brackets:
        problems.append(f"unclosed brackets: {brackets}")
    return problems


def main() -> int:
    failed = False
    for path in sorted(SRC.rglob("*.luau")):
        problems = check(path)
        if problems:
            failed = True
            for p in problems:
                print(f"{path.relative_to(ROOT)}: {p}")
    if failed:
        return 1
    print("Luau sanity checks passed.")
    if "--check" in sys.argv:
        return 0
    OUT.write_text(build(), encoding="utf-8")
    print(f"Wrote {OUT.relative_to(ROOT)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
