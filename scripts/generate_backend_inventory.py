#!/usr/bin/env python3
"""Generate a deterministic, source-only backend inventory.

The output contains names and source locations only. It does not import the
application, open a database, read environment values, or serialize runtime
configuration.
"""

from __future__ import annotations

import argparse
import ast
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
ROUTE_METHODS = {"get", "post", "put", "patch", "delete", "websocket"}


def _python_files(*relative_directories: str) -> list[Path]:
    files: set[Path] = set()
    for directory in relative_directories:
        files.update((ROOT / directory).rglob("*.py"))
    return sorted(files, key=lambda path: path.relative_to(ROOT).as_posix())


def _tree(path: Path) -> ast.Module:
    return ast.parse(path.read_text(encoding="utf-8"), filename=str(path))


def _relative(path: Path) -> str:
    return path.relative_to(ROOT).as_posix()


def _call_name(node: ast.AST) -> str:
    try:
        return ast.unparse(node)
    except Exception:
        return type(node).__name__


def _route_rows() -> list[str]:
    rows: list[str] = []
    for path in [ROOT / "main.py", *_python_files("routes", "routers")]:
        tree = _tree(path)
        for node in ast.walk(tree):
            if not isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef)):
                continue
            for decorator in node.decorator_list:
                if not isinstance(decorator, ast.Call) or not isinstance(decorator.func, ast.Attribute):
                    continue
                if decorator.func.attr not in ROUTE_METHODS:
                    continue
                owner = _call_name(decorator.func.value)
                if owner not in {"app", "router", "public_router"}:
                    continue
                declared_path = _call_name(decorator.args[0]) if decorator.args else "<dynamic>"
                rows.append(
                    f"{_relative(path)}:{decorator.lineno} "
                    f"{owner}.{decorator.func.attr}({declared_path}) -> {node.name}"
                )
    return sorted(rows)


def _dependency_rows() -> list[str]:
    rows: list[str] = []
    for path in [ROOT / "main.py", *_python_files("routes", "routers", "services")]:
        tree = _tree(path)
        for node in ast.walk(tree):
            if not isinstance(node, ast.Call) or not isinstance(node.func, ast.Name):
                continue
            if node.func.id != "Depends":
                continue
            target = _call_name(node.args[0]) if node.args else "<implicit>"
            rows.append(f"{_relative(path)}:{node.lineno} Depends({target})")
    return sorted(rows)


def _class_rows(paths: list[Path], *, base_name: str | None = None) -> list[str]:
    rows: list[str] = []
    for path in paths:
        for node in _tree(path).body:
            if not isinstance(node, ast.ClassDef):
                continue
            bases = {_call_name(base) for base in node.bases}
            if base_name is not None and base_name not in bases:
                continue
            rows.append(f"{_relative(path)}:{node.lineno} {node.name}")
    return sorted(rows)


def _service_rows() -> list[str]:
    rows: list[str] = []
    for path in _python_files("services"):
        classes = [
            node.name for node in _tree(path).body if isinstance(node, ast.ClassDef)
        ]
        suffix = f" classes={','.join(classes)}" if classes else ""
        rows.append(f"{_relative(path)}{suffix}")
    return rows


def _background_rows() -> list[str]:
    rows: list[str] = []
    paths = [ROOT / "main.py", ROOT / "background_tasks.py", *_python_files("routes", "services")]
    for path in sorted(set(paths)):
        tree = _tree(path)
        for node in ast.walk(tree):
            if not isinstance(node, ast.Call):
                continue
            called = _call_name(node.func)
            if called in {"asyncio.create_task", "background_tasks.add_task", "task_manager.start_all"}:
                rows.append(f"{_relative(path)}:{node.lineno} {called}")
    return sorted(rows)


def _migration_rows() -> list[str]:
    rows: list[str] = []
    for path in _python_files("alembic/versions"):
        revision = "<unknown>"
        down_revision = "<unknown>"
        for node in _tree(path).body:
            if not isinstance(node, ast.Assign) or len(node.targets) != 1:
                continue
            target = node.targets[0]
            if not isinstance(target, ast.Name):
                continue
            if target.id == "revision":
                revision = _call_name(node.value)
            elif target.id == "down_revision":
                down_revision = _call_name(node.value)
        rows.append(f"{_relative(path)} revision={revision} down_revision={down_revision}")
    return rows


def _test_rows() -> list[str]:
    rows: list[str] = []
    for path in _python_files("tests"):
        tree = _tree(path)
        for node in tree.body:
            if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef)) and node.name.startswith("test_"):
                rows.append(f"{_relative(path)}:{node.lineno} {node.name}")
            elif isinstance(node, ast.ClassDef):
                for child in node.body:
                    if isinstance(child, (ast.FunctionDef, ast.AsyncFunctionDef)) and child.name.startswith("test_"):
                        rows.append(f"{_relative(path)}:{child.lineno} {node.name}.{child.name}")
    return sorted(rows)


def _section(title: str, rows: list[str]) -> list[str]:
    return [f"## {title} ({len(rows)})", *rows, ""]


def build_inventory() -> str:
    routes = _route_rows()
    dependencies = _dependency_rows()
    models = _class_rows(_python_files("models"), base_name="Base")
    services = _service_rows()
    background = _background_rows()
    migrations = _migration_rows()
    tests = _test_rows()
    lines = [
        "# SecureWave backend source inventory",
        "# Generated by scripts/generate_backend_inventory.py; source names and locations only.",
        "",
    ]
    lines += _section("Route decorators", routes)
    lines += _section("FastAPI dependency declarations", dependencies)
    lines += _section("SQLAlchemy mapped models", models)
    lines += _section("Service modules", services)
    lines += _section("Background task scheduling calls", background)
    lines += _section("Alembic revisions", migrations)
    lines += _section("Test functions", tests)
    return "\n".join(lines).rstrip() + "\n"


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--output",
        type=Path,
        default=ROOT / "artifacts/backend-api-refactor/source-inventory.txt",
    )
    args = parser.parse_args()
    output = args.output if args.output.is_absolute() else ROOT / args.output
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(build_inventory(), encoding="utf-8")
    print(output.relative_to(ROOT))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
