#!/usr/bin/env python3
"""Syntax-check every Swift file with tree-sitter.

This is NOT a compiler: it catches unbalanced braces, stray tokens and other
parse errors, but knows nothing about types. It exists so the Swift sources can
be sanity-checked on machines without Xcode (for example Linux CI).

    pip install tree-sitter tree-sitter-swift
    python3 ios/scripts/check_swift_syntax.py
"""
import pathlib
import sys

import tree_sitter_swift
from tree_sitter import Language, Parser

ROOT = pathlib.Path(__file__).resolve().parents[1]
parser = Parser(Language(tree_sitter_swift.language()))


def first_errors(node, source, found, limit=3):
    if len(found) >= limit:
        return
    if node.type == "ERROR" or node.is_missing:
        line = node.start_point[0] + 1
        text = source[node.start_byte:node.end_byte].decode("utf8", "replace").split("\n")[0][:80]
        found.append((line, "missing " + node.type if node.is_missing else text))
        return
    for child in node.children:
        if child.has_error or child.is_missing:
            first_errors(child, source, found, limit)


def main() -> int:
    files = sorted(p for p in ROOT.rglob("*.swift") if ".build" not in p.parts)
    failures = 0
    lines = 0
    for path in files:
        source = path.read_bytes()
        lines += source.count(b"\n")
        tree = parser.parse(source)
        if tree.root_node.has_error:
            failures += 1
            found = []
            first_errors(tree.root_node, source, found)
            for line, text in found:
                print(f"{path.relative_to(ROOT)}:{line}: syntax error near: {text}")
    print(f"{len(files)} Swift files, {lines} lines, {failures} with syntax errors")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
