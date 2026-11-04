"""
Report-level parity: run identical DAX against the legacy (SQL Server) semantic model and the
repointed (Snowflake) model and compare row by row. This proves "no report rebuild" end to end:
same measures, same relationships, same numbers.
"""
import argparse
import json
import sys

import yaml

from pbi_client import PowerBIClient


def norm_key(row, numeric_cols):
    return tuple(sorted((k, str(v)) for k, v in row.items() if k not in numeric_cols))


def compare(legacy, new, tol_abs, tol_pct):
    if not legacy and not new:
        return []
    sample = legacy[0] if legacy else new[0]
    numeric = {k for k, v in sample.items() if isinstance(v, (int, float)) and not isinstance(v, bool)}
    L = {norm_key(r, numeric): r for r in legacy}
    N = {norm_key(r, numeric): r for r in new}
    diffs = []
    for key in L.keys() | N.keys():
        a, b = L.get(key), N.get(key)
        if a is None or b is None:
            diffs.append({"key": dict(key), "issue": "missing in " + ("new" if b is None else "legacy")})
            continue
        for col in numeric:
            x, y = a.get(col) or 0, b.get(col) or 0
            if abs(x - y) > max(tol_abs, abs(x) * tol_pct):
                diffs.append({"key": dict(key), "column": col, "legacy": x, "snowflake": y, "delta": y - x})
    return diffs


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--config", required=True)
    ap.add_argument("--cutover-log", help="cutover_log_*.json to resolve new dataset ids")
    args = ap.parse_args()

    cfg = yaml.safe_load(open(args.config))
    queries = yaml.safe_load(open(cfg["dax_parity"]["queries_file"]))
    new_ids = {}
    if args.cutover_log:
        new_ids = {r["report"]: r.get("dataset_id") for r in json.load(open(args.cutover_log))}

    pbi = PowerBIClient.from_config(cfg)
    tol_abs, tol_pct = cfg["dax_parity"]["tolerance_abs"], cfg["dax_parity"]["tolerance_pct"]
    failures = 0
    for rpt in cfg["reports"]:
        name = rpt["name"]
        new_ds = new_ids.get(name) or rpt.get("new_dataset_id")
        if not new_ds:
            print(f"SKIP {name}: no repointed dataset id (pass --cutover-log)")
            continue
        for q in queries.get(name, []):
            legacy_rows = pbi.execute_dax(rpt["legacy_dataset_id"], q["dax"])
            new_rows = pbi.execute_dax(new_ds, q["dax"])
            diffs = compare(legacy_rows, new_rows, tol_abs, tol_pct)
            status = "PASS" if not diffs else "FAIL"
            failures += bool(diffs)
            print(f"{status} {name} :: {q['name']} (legacy={len(legacy_rows)} rows, snowflake={len(new_rows)} rows)")
            for d in diffs[:10]:
                print("      ", d)
    sys.exit(1 if failures else 0)


if __name__ == "__main__":
    main()
