#!/usr/bin/env python3
"""Structural check of ReplyRight.xcodeproj/project.pbxproj.

Parses the project file with a small, independent parser (it shares no code
with generate_xcodeproj.py) and verifies that it is well formed:
every referenced object exists, every Swift file on disk is compiled by the
right target, and every file named in build settings exists.

This cannot prove Xcode will build the project. It catches a malformed or
inconsistent project file on machines without Xcode.
"""
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parents[1]
PBXPROJ = ROOT / "ReplyRight.xcodeproj" / "project.pbxproj"


class Parser:
    """A minimal reader for the OpenStep property list format used by Xcode."""

    def __init__(self, text: str) -> None:
        self.text = text
        self.pos = 0

    def skip(self) -> None:
        while self.pos < len(self.text):
            if self.text[self.pos].isspace():
                self.pos += 1
            elif self.text.startswith("/*", self.pos):
                self.pos = self.text.index("*/", self.pos) + 2
            elif self.text.startswith("//", self.pos):
                end = self.text.find("\n", self.pos)
                self.pos = len(self.text) if end < 0 else end
            else:
                return

    def expect(self, token: str) -> None:
        self.skip()
        if not self.text.startswith(token, self.pos):
            line = self.text.count("\n", 0, self.pos) + 1
            raise SyntaxError(f"line {line}: expected {token!r}, found {self.text[self.pos:self.pos + 20]!r}")
        self.pos += len(token)

    def value(self):
        self.skip()
        char = self.text[self.pos]
        if char == "{":
            self.pos += 1
            result = {}
            while True:
                self.skip()
                if self.text[self.pos] == "}":
                    self.pos += 1
                    return result
                key = self.value()
                self.expect("=")
                result[key] = self.value()
                self.expect(";")
        if char == "(":
            self.pos += 1
            items = []
            while True:
                self.skip()
                if self.text[self.pos] == ")":
                    self.pos += 1
                    return items
                items.append(self.value())
                self.skip()
                if self.text[self.pos] == ",":
                    self.pos += 1
        if char == '"':
            self.pos += 1
            out = []
            while self.text[self.pos] != '"':
                if self.text[self.pos] == "\\":
                    self.pos += 1
                    out.append({"n": "\n", "t": "\t"}.get(self.text[self.pos], self.text[self.pos]))
                else:
                    out.append(self.text[self.pos])
                self.pos += 1
            self.pos += 1
            return "".join(out)
        match = re.compile(r"[A-Za-z0-9_./$-]+").match(self.text, self.pos)
        if not match:
            line = self.text.count("\n", 0, self.pos) + 1
            raise SyntaxError(f"line {line}: unexpected character {char!r}")
        self.pos = match.end()
        return match.group()


def main() -> int:
    text = PBXPROJ.read_text()
    parser = Parser(text)
    root = parser.value()
    parser.skip()
    problems: list[str] = []
    if parser.pos != len(text):
        problems.append("trailing content after the root object")

    objects = root["objects"]
    ids = set(objects)
    hex_id = re.compile(r"[0-9A-F]{24}")

    def references(value):
        if isinstance(value, dict):
            for key, item in value.items():
                if hex_id.fullmatch(key):
                    yield key
                yield from references(item)
        elif isinstance(value, list):
            for item in value:
                yield from references(item)
        elif isinstance(value, str) and hex_id.fullmatch(value):
            yield value

    for identifier, fields in objects.items():
        for ref in references(fields):
            if ref not in ids:
                problems.append(f"{fields['isa']} {identifier} refers to missing object {ref}")
    if root["rootObject"] not in ids:
        problems.append("rootObject is missing")

    # Resolve each file reference to a path on disk by walking the group tree.
    paths: dict[str, pathlib.Path] = {}

    def walk(group_id: str, base: pathlib.Path) -> None:
        group = objects[group_id]
        here = base / group["path"] if "path" in group else base
        for child in group.get("children", []):
            item = objects[child]
            if item["isa"] == "PBXGroup":
                walk(child, here)
            elif item.get("sourceTree") == "<group>":
                paths[child] = here / item["path"]

    project = objects[root["rootObject"]]
    walk(project["mainGroup"], ROOT)
    for identifier, path in paths.items():
        if not path.exists():
            problems.append(f"file reference {identifier} points at a missing path: {path.relative_to(ROOT)}")

    print(f"objects: {len(objects)}, file references resolved: {len(paths)}")
    for target_id in project["targets"]:
        target = objects[target_id]
        compiled: set[pathlib.Path] = set()
        summary = []
        for phase_id in target["buildPhases"]:
            phase = objects[phase_id]
            kind = phase["isa"].replace("PBX", "").replace("BuildPhase", "")
            summary.append(f"{kind}={len(phase['files'])}")
            if phase["isa"] == "PBXSourcesBuildPhase":
                for build_file in phase["files"]:
                    compiled.add(paths[objects[build_file]["fileRef"]])
        folder = ROOT / target["name"]
        on_disk = set(folder.rglob("*.swift"))
        for path in sorted(on_disk - compiled):
            problems.append(f"{target['name']}: {path.relative_to(ROOT)} is not compiled")
        for path in sorted(compiled - on_disk):
            problems.append(f"{target['name']}: compiles a file outside its folder: {path.relative_to(ROOT)}")
        if not compiled:
            problems.append(f"{target['name']}: no sources")

        packages = [objects[p]["productName"] for p in target.get("packageProductDependencies", [])]
        dependencies = [objects[objects[d]["target"]]["name"] for d in target.get("dependencies", [])]
        print(f"  {target['name']:20} {' '.join(summary):48} packages={packages} depends_on={dependencies}")

        configs = objects[target["buildConfigurationList"]]["buildConfigurations"]
        for config_id in configs:
            settings = objects[config_id]["buildSettings"]
            for key in ("INFOPLIST_FILE", "CODE_SIGN_ENTITLEMENTS"):
                if key in settings and not (ROOT / settings[key]).exists():
                    problems.append(f"{target['name']}: {key} points at a missing file: {settings[key]}")

    for reference in project.get("packageReferences", []):
        package = ROOT / objects[reference]["relativePath"] / "Package.swift"
        if not package.exists():
            problems.append(f"local package is missing: {package.relative_to(ROOT)}")

    for problem in problems:
        print("PROBLEM:", problem)
    print("project file is consistent" if not problems else f"{len(problems)} problem(s)")
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
