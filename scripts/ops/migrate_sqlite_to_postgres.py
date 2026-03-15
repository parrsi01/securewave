#!/usr/bin/env python3
"""
Migrate SecureWave data from SQLite to PostgreSQL.

Operator flow:
1. Run Alembic against PostgreSQL.
2. Copy table data from SQLite into PostgreSQL.
3. Reset PostgreSQL sequences to the copied maximum IDs.
"""

from __future__ import annotations

import argparse
import os
import subprocess
import sys
from pathlib import Path
from typing import Iterable

from sqlalchemy import MetaData, create_engine, select, text
from sqlalchemy.engine import Engine


IGNORED_TABLES = {"alembic_version"}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source-url", required=True, help="sqlite:///... source URL")
    parser.add_argument("--target-url", required=True, help="postgresql+psycopg2://... target URL")
    parser.add_argument("--batch-size", type=int, default=500, help="Rows per insert batch")
    parser.add_argument("--dry-run", action="store_true", help="Report copy counts without writing")
    parser.add_argument("--truncate", action="store_true", help="Delete existing target rows before copy")
    parser.add_argument("--run-migrations", action="store_true", help="Run `alembic upgrade head` against the target URL first")
    return parser.parse_args()


def reflect_metadata(engine: Engine) -> MetaData:
    metadata = MetaData()
    metadata.reflect(bind=engine)
    return metadata


def iter_copy_tables(source_meta: MetaData, target_meta: MetaData) -> Iterable[str]:
    for table in target_meta.sorted_tables:
        if table.name in IGNORED_TABLES:
            continue
        if table.name in source_meta.tables:
            yield table.name


def run_migrations(target_url: str) -> None:
    repo_root = Path.cwd()
    candidate_root = Path(__file__).resolve()
    if len(candidate_root.parents) >= 3:
        resolved_root = candidate_root.parents[2]
        if (resolved_root / "alembic.ini").exists():
            repo_root = resolved_root

    env = dict(os.environ)
    env["DATABASE_URL"] = target_url
    subprocess.run(
        [sys.executable, "-m", "alembic", "upgrade", "head"],
        cwd=repo_root,
        env=env,
        check=True,
    )


def reset_postgres_sequences(engine: Engine, metadata: MetaData, table_names: Iterable[str]) -> None:
    if engine.dialect.name != "postgresql":
        return

    with engine.begin() as conn:
        for table_name in table_names:
            table = metadata.tables[table_name]
            pk_columns = list(table.primary_key.columns)
            if len(pk_columns) != 1:
                continue

            pk_column = pk_columns[0]
            sequence_name = conn.execute(
                text("SELECT pg_get_serial_sequence(:table_name, :column_name)"),
                {"table_name": table_name, "column_name": pk_column.name},
            ).scalar_one_or_none()
            if not sequence_name:
                continue

            max_pk = conn.execute(select(pk_column).order_by(pk_column.desc()).limit(1)).scalar_one_or_none()
            next_value = int(max_pk or 1)
            conn.execute(
                text("SELECT setval(:sequence_name, :next_value, true)"),
                {"sequence_name": sequence_name, "next_value": next_value},
            )


def copy_rows(source_engine: Engine, target_engine: Engine, batch_size: int, truncate: bool, dry_run: bool) -> list[tuple[str, int]]:
    source_meta = reflect_metadata(source_engine)
    target_meta = reflect_metadata(target_engine)
    table_names = list(iter_copy_tables(source_meta, target_meta))
    summary: list[tuple[str, int]] = []

    with source_engine.connect() as source_conn:
        if dry_run:
            for table_name in table_names:
                source_table = source_meta.tables[table_name]
                count = source_conn.execute(select(text("count(*)")).select_from(source_table)).scalar_one()
                summary.append((table_name, int(count)))
            return summary

        with target_engine.begin() as target_conn:
            if truncate:
                for table_name in reversed(table_names):
                    target_conn.execute(target_meta.tables[table_name].delete())

            for table_name in table_names:
                source_table = source_meta.tables[table_name]
                target_table = target_meta.tables[table_name]
                common_columns = [column.name for column in target_table.columns if column.name in source_table.c]
                result = source_conn.execute(select(*(source_table.c[name] for name in common_columns))).mappings()
                copied = 0

                while True:
                    batch = result.fetchmany(batch_size)
                    if not batch:
                        break
                    target_conn.execute(
                        target_table.insert(),
                        [{name: row[name] for name in common_columns} for row in batch],
                    )
                    copied += len(batch)

                summary.append((table_name, copied))

    reset_postgres_sequences(target_engine, target_meta, table_names)
    return summary


def main() -> int:
    args = parse_args()
    if not args.source_url.startswith("sqlite:///"):
        raise SystemExit("--source-url must be a sqlite:/// URL")
    if not args.target_url.startswith("postgresql"):
        raise SystemExit("--target-url must be a postgresql URL")

    if args.run_migrations:
        run_migrations(args.target_url)

    source_engine = create_engine(args.source_url, future=True)
    target_engine = create_engine(args.target_url, future=True)
    summary = copy_rows(
        source_engine=source_engine,
        target_engine=target_engine,
        batch_size=args.batch_size,
        truncate=args.truncate,
        dry_run=args.dry_run,
    )

    for table_name, copied in summary:
        print(f"{table_name}: {copied}")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
