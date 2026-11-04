"""
Data reconciliation: legacy SQL Server DW (SSIS output) vs Snowflake (dbt output).

Levels per check:
  L1 row counts
  L2 measure totals (overall and per group_by slice)
  L3 key-level hash diff -> lists missing / extra / changed keys
Produces validation/reconciliation_report.md and exits non-zero on unexplained differences.
"""
import argparse
import hashlib
import os
from datetime import datetime

import pandas as pd
import pyodbc
import snowflake.connector
import yaml
from cryptography.hazmat.primitives import serialization


def mssql(db):
    return pyodbc.connect(
        "DRIVER={ODBC Driver 18 for SQL Server};"
        f"SERVER={os.environ['MSSQL_SERVER']};DATABASE={db};"
        f"UID={os.environ['MSSQL_USER']};PWD={os.environ['MSSQL_PASSWORD']};Encrypt=yes;")


def snow(db):
    with open(os.environ["SNOWFLAKE_PRIVATE_KEY_PATH"], "rb") as fh:
        pw = os.environ.get("SNOWFLAKE_PRIVATE_KEY_PASSPHRASE")
        key = serialization.load_pem_private_key(fh.read(), password=pw.encode() if pw else None)
    return snowflake.connector.connect(
        account=os.environ["SNOWFLAKE_ACCOUNT"], user=os.environ["SNOWFLAKE_USER"],
        private_key=key.private_bytes(serialization.Encoding.DER, serialization.PrivateFormat.PKCS8,
                                      serialization.NoEncryption()),
        role=os.getenv("SNOWFLAKE_ROLE", "TRANSFORMER"), warehouse=os.getenv("SNOWFLAKE_WAREHOUSE", "WH_TRANSFORM"),
        database=db, session_parameters={"QUERY_TAG": "app=reconciliation"})


def fetch(conn, sql, is_snowflake):
    if is_snowflake:
        cur = conn.cursor()
        cur.execute(sql)
        df = cur.fetch_pandas_all()
    else:
        df = pd.read_sql(sql, conn)
    df.columns = [c.upper() for c in df.columns]
    return df


def where(f):
    return f" WHERE {f}" if f else ""


def row_hash(df, cols):
    def h(r):
        parts = []
        for c in cols:
            v = r[c.upper()]
            if isinstance(v, float) or hasattr(v, "quantize"):
                v = f"{float(v):.2f}"
            parts.append("" if pd.isna(v) else str(v).strip())
        return hashlib.md5("|".join(parts).encode()).hexdigest()
    return df.apply(h, axis=1)


def run_check(c, ms, sf, tol):
    out = {"name": c["name"], "status": "PASS", "lines": []}
    key = c["key"].upper()
    lw, sw = where(c.get("filter_legacy")), where(c.get("filter_snowflake"))

    # L1 + L2 overall
    agg = ", ".join([f"SUM({m}) AS {m}" for m in c["measures"]])
    agg = (", " + agg) if agg else ""
    L = fetch(ms, f"SELECT COUNT(*) AS N{agg} FROM {c['legacy']}{lw}", False).iloc[0]
    S = fetch(sf, f"SELECT COUNT(*) AS N{agg} FROM {c['snowflake']}{sw}", True).iloc[0]
    out["lines"].append(f"| rows | {int(L['N']):,} | {int(S['N']):,} | {int(S['N']) - int(L['N']):+,} |")
    if int(L["N"]) != int(S["N"]):
        out["status"] = "FAIL"
    for m in c["measures"]:
        lv, sv = float(L[m.upper()] or 0), float(S[m.upper()] or 0)
        out["lines"].append(f"| sum({m}) | {lv:,.2f} | {sv:,.2f} | {sv - lv:+,.2f} |")
        if abs(lv - sv) > tol:
            out["status"] = "FAIL"

    # L2 by slice
    if c.get("group_by") and c["measures"]:
        g = ", ".join(c["group_by"])
        m0 = c["measures"][0]
        lg = fetch(ms, f"SELECT {g}, SUM({m0}) AS V FROM {c['legacy']}{lw} GROUP BY {g}", False)
        sg = fetch(sf, f"SELECT {g}, SUM({m0}) AS V FROM {c['snowflake']}{sw} GROUP BY {g}", True)
        keys = [x.upper() for x in c["group_by"]]
        mg = lg.merge(sg, on=keys, how="outer", suffixes=("_L", "_S")).fillna(0)
        bad = mg[(mg["V_L"].astype(float) - mg["V_S"].astype(float)).abs() > tol]
        out["lines"].append(f"| slices by {g} with {m0} diff | {len(bad)} of {len(mg)} | | |")
        if len(bad):
            out["status"] = "FAIL"

    # L3 key-level hash diff
    cols = [key] + [x for x in c["hash_columns"]]
    sel = ", ".join(cols)
    ld = fetch(ms, f"SELECT {sel} FROM {c['legacy']}{lw}", False)
    sd = fetch(sf, f"SELECT {sel} FROM {c['snowflake']}{sw}", True)
    ld["H"], sd["H"] = row_hash(ld, c["hash_columns"]), row_hash(sd, c["hash_columns"])
    j = ld[[key, "H"]].merge(sd[[key, "H"]], on=key, how="outer", suffixes=("_L", "_S"), indicator=True)
    missing = j[j["_merge"] == "left_only"][key].tolist()
    extra = j[j["_merge"] == "right_only"][key].tolist()
    changed = j[(j["_merge"] == "both") & (j["H_L"] != j["H_S"])][key].tolist()
    out["lines"].append(f"| keys missing in Snowflake | {len(missing):,} | | sample {missing[:5]} |")
    out["lines"].append(f"| keys extra in Snowflake | | {len(extra):,} | sample {extra[:5]} |")
    out["lines"].append(f"| keys with changed values | {len(changed):,} | | sample {changed[:5]} |")
    if missing or changed:
        out["status"] = "FAIL"
    if extra and out["status"] == "PASS":
        out["status"] = "REVIEW" if c.get("known_difference_note") else "FAIL"
    if c.get("known_difference_note"):
        out["lines"].append(f"| known difference | {c['known_difference_note']} | | |")
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--config", required=True)
    ap.add_argument("--out", default="validation/reconciliation_report.md")
    args = ap.parse_args()
    cfg = yaml.safe_load(open(args.config))

    ms = mssql(os.environ[cfg["mssql_database_env"]])
    sf = snow(cfg["snowflake_database"])
    results = [run_check(c, ms, sf, cfg["amount_tolerance"]) for c in cfg["checks"]]

    with open(args.out, "w") as fh:
        fh.write(f"# Reconciliation report - {datetime.now():%Y-%m-%d %H:%M}\n\n")
        for r in results:
            fh.write(f"## {r['name']} - **{r['status']}**\n\n| check | legacy | snowflake | delta / note |\n|---|---|---|---|\n")
            fh.write("\n".join(r["lines"]) + "\n\n")
    for r in results:
        print(f"{r['status']:<6} {r['name']}")
    print(f"report -> {args.out}")
    raise SystemExit(1 if any(r["status"] == "FAIL" for r in results) else 0)


if __name__ == "__main__":
    main()
