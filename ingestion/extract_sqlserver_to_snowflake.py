"""
POC extractor: SQL Server (SalesOLTP) -> Snowflake RAW, watermark-based incremental.

Replaces the OLE DB Source side of the SSIS data flows. RAW is append-only; dbt staging
de-duplicates on the business key keeping the latest ModifiedDate.
For production use Snowflake Openflow or a CDC tool; RAW table contracts stay identical.
"""
import argparse
import logging
import os
import uuid
from datetime import datetime, timezone

import pandas as pd
import pyodbc
import snowflake.connector
import yaml
from cryptography.hazmat.primitives import serialization
from snowflake.connector.pandas_tools import write_pandas

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
log = logging.getLogger("extract")


def sqlserver_conn():
    return pyodbc.connect(
        "DRIVER={ODBC Driver 18 for SQL Server};"
        f"SERVER={os.environ['MSSQL_SERVER']};DATABASE={os.environ['MSSQL_OLTP_DB']};"
        f"UID={os.environ['MSSQL_USER']};PWD={os.environ['MSSQL_PASSWORD']};"
        "Encrypt=yes;TrustServerCertificate=no;"
    )


def snowflake_conn(cfg):
    with open(os.environ["SNOWFLAKE_PRIVATE_KEY_PATH"], "rb") as fh:
        passphrase = os.environ.get("SNOWFLAKE_PRIVATE_KEY_PASSPHRASE") or None
        pkey = serialization.load_pem_private_key(
            fh.read(), password=passphrase.encode() if passphrase else None)
    pkb = pkey.private_bytes(serialization.Encoding.DER, serialization.PrivateFormat.PKCS8,
                             serialization.NoEncryption())
    return snowflake.connector.connect(
        account=os.environ["SNOWFLAKE_ACCOUNT"], user=os.getenv("SNOWFLAKE_LOADER_USER", "SVC_LOADER"),
        private_key=pkb, role=cfg.get("role", "LOADER"), warehouse=cfg.get("warehouse", "WH_LOAD"),
        database=cfg["target_database"], schema=cfg["target_schema"],
        session_parameters={"QUERY_TAG": "app=ingestion;pipeline=Load_SalesDW"},
    )


WM_TABLE = "LOAD_WATERMARK"


def get_watermark(sf, table):
    cur = sf.cursor()
    cur.execute(f"SELECT HIGH_WATERMARK FROM {WM_TABLE} WHERE TABLE_NAME = %s", (table,))
    row = cur.fetchone()
    return row[0] if row and row[0] else datetime(1900, 1, 1)


def set_watermark(sf, table, hwm, rows):
    sf.cursor().execute(
        f"""MERGE INTO {WM_TABLE} t
           USING (SELECT %s AS TABLE_NAME, %s::TIMESTAMP_NTZ AS HWM, %s AS N) s
           ON t.TABLE_NAME = s.TABLE_NAME
           WHEN MATCHED THEN UPDATE SET HIGH_WATERMARK = s.HWM, ROWS_LOADED = s.N, UPDATED_AT = CURRENT_TIMESTAMP()
           WHEN NOT MATCHED THEN INSERT VALUES (s.TABLE_NAME, s.HWM, s.N, CURRENT_TIMESTAMP())""",
        (table, hwm, rows))


def load_table(ms, sf, spec, batch_id, batch_size):
    target, wm_col = spec["target"], spec["watermark_column"]
    since = get_watermark(sf, target)
    sql = f"SELECT * FROM {spec['source']} WHERE {wm_col} > ? ORDER BY {wm_col}"
    log.info("%s: extracting rows where %s > %s", target, wm_col, since)

    total, hwm = 0, since
    for chunk in pd.read_sql(sql, ms, params=[since], chunksize=batch_size):
        if chunk.empty:
            continue
        chunk.columns = [c.upper() for c in chunk.columns]
        for col in chunk.select_dtypes(include=["datetime64[ns]"]).columns:
            chunk[col] = chunk[col].dt.tz_localize(None)
        chunk["_BATCH_ID"] = batch_id
        chunk["_SOURCE_SYSTEM"] = "SalesOLTP"
        ok, _, nrows, _ = write_pandas(sf, chunk, target, use_logical_type=True, quote_identifiers=False)
        if not ok:
            raise RuntimeError(f"write_pandas failed for {target}")
        total += nrows
        hwm = max(hwm, chunk[wm_col.upper()].max().to_pydatetime())

    if total:
        set_watermark(sf, target, hwm, total)
    log.info("%s: loaded %d rows, new watermark %s", target, total, hwm)
    return total


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--config", required=True)
    ap.add_argument("--full-refresh", action="store_true", help="ignore watermarks")
    args = ap.parse_args()
    cfg = yaml.safe_load(open(args.config))
    global WM_TABLE
    WM_TABLE = cfg.get("watermark_table", "LOAD_WATERMARK")

    batch_id = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%S") + "-" + uuid.uuid4().hex[:6]
    ms, sf = sqlserver_conn(), snowflake_conn(cfg)
    try:
        if args.full_refresh:
            sf.cursor().execute(f"TRUNCATE TABLE {WM_TABLE}")
        summary = {t["target"]: load_table(ms, sf, t, batch_id, cfg["batch_size"]) for t in cfg["tables"]}
        log.info("batch %s complete: %s", batch_id, summary)
    finally:
        ms.close()
        sf.close()


if __name__ == "__main__":
    main()
