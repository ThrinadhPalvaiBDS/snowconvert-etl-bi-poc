"""
SQL Server CDC -> Snowflake RAW change tables (<TABLE>_CT).

Per table:
  * No checkpoint yet          -> SNAPSHOT: read max LSN, copy the full table as op 'S' stamped
                                  with that LSN, store it as the checkpoint.
  * Checkpoint exists          -> INCREMENTAL: read cdc.fn_cdc_get_all_changes_<instance>
                                  from (checkpoint + 1) to current max LSN; ops I/U/D.
  * Checkpoint older than CDC
    retention (min LSN)        -> gap: re-snapshot (auto_resnapshot_on_gap) or fail.

Delivery is at-least-once: the checkpoint is advanced only after rows are written, and
dbt de-duplicates on (key, LSN, seqval), so a crash/re-run never corrupts state.
Rows changed while a snapshot runs appear in both the snapshot and the change stream;
the change stream has the higher LSN and wins downstream.
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
log = logging.getLogger("cdc")

OPS = {1: "D", 2: "I", 4: "U"}          # 3 (update-before image) is excluded by N'all'
ZERO_SEQ = "0" * 20


def lsn_hex(b):
    return b.hex().upper() if b is not None else None


def sqlserver_conn():
    return pyodbc.connect(
        "DRIVER={ODBC Driver 18 for SQL Server};"
        f"SERVER={os.environ['MSSQL_SERVER']};DATABASE={os.environ['MSSQL_OLTP_DB']};"
        f"UID={os.environ['MSSQL_USER']};PWD={os.environ['MSSQL_PASSWORD']};"
        "Encrypt=yes;TrustServerCertificate=no;", autocommit=True)


def snowflake_conn(cfg):
    with open(os.environ["SNOWFLAKE_PRIVATE_KEY_PATH"], "rb") as fh:
        pw = os.environ.get("SNOWFLAKE_PRIVATE_KEY_PASSPHRASE")
        key = serialization.load_pem_private_key(fh.read(), password=pw.encode() if pw else None)
    return snowflake.connector.connect(
        account=os.environ["SNOWFLAKE_ACCOUNT"],
        user=os.getenv("SNOWFLAKE_LOADER_USER", "SVC_POC_PIPELINE"),
        private_key=key.private_bytes(serialization.Encoding.DER, serialization.PrivateFormat.PKCS8,
                                      serialization.NoEncryption()),
        role=cfg["role"], warehouse=cfg["warehouse"],
        database=cfg["target_database"], schema=cfg["target_schema"],
        session_parameters={"QUERY_TAG": "app=ingestion;mode=cdc;pipeline=Load_SalesDW"})


# ---------------- checkpoint ----------------
def get_checkpoint(sf, table):
    cur = sf.cursor()
    cur.execute("SELECT LAST_LSN FROM CDC_CHECKPOINT WHERE TABLE_NAME = %s", (table,))
    row = cur.fetchone()
    return row[0] if row else None


def set_checkpoint(sf, table, instance, lsn, mode, rows):
    sf.cursor().execute(
        """MERGE INTO CDC_CHECKPOINT t
           USING (SELECT %s AS TABLE_NAME, %s AS CI, %s AS LSN, %s AS MODE, %s AS N) s
           ON t.TABLE_NAME = s.TABLE_NAME
           WHEN MATCHED THEN UPDATE SET CAPTURE_INSTANCE = s.CI, LAST_LSN = s.LSN, LAST_MODE = s.MODE,
                                        ROWS_LAST_RUN = s.N, UPDATED_AT = CURRENT_TIMESTAMP()
           WHEN NOT MATCHED THEN INSERT VALUES (s.TABLE_NAME, s.CI, s.LSN, s.MODE, s.N, CURRENT_TIMESTAMP())""",
        (table, instance, lsn, mode, rows))


# ---------------- helpers ----------------
def source_columns(ms, source):
    cur = ms.cursor()
    cur.execute(f"SELECT TOP 0 * FROM {source}")
    return [d[0] for d in cur.description]


def prepare(df, batch_id):
    df.columns = [c.upper() for c in df.columns]
    for col in df.select_dtypes(include=["datetime64[ns]"]).columns:
        df[col] = df[col].dt.tz_localize(None)
    df["_BATCH_ID"] = batch_id
    df["_SOURCE_SYSTEM"] = "SalesOLTP"
    return df


def write(sf, df, target):
    ok, _, nrows, _ = write_pandas(sf, df, target, use_logical_type=True, quote_identifiers=False)
    if not ok:
        raise RuntimeError(f"write_pandas failed for {target}")
    return nrows


# ---------------- snapshot ----------------
def snapshot(ms, sf, spec, batch_id, batch_size):
    target = spec["target"]
    max_lsn = lsn_hex(ms.cursor().execute("SELECT sys.fn_cdc_get_max_lsn()").fetchone()[0])
    log.info("%s: SNAPSHOT at LSN %s", target, max_lsn)
    # Clear rows from any earlier (failed or superseded) snapshot/changes for a clean restart
    sf.cursor().execute(f"DELETE FROM {target}")
    total = 0
    for chunk in pd.read_sql(f"SELECT * FROM {spec['source']}", ms, chunksize=batch_size):
        chunk["_CDC_OP"] = "S"
        chunk["_CDC_LSN"] = max_lsn
        chunk["_CDC_SEQVAL"] = ZERO_SEQ
        chunk["_CDC_COMMIT_TS"] = pd.Timestamp.utcnow().tz_localize(None)
        total += write(sf, prepare(chunk, batch_id), target)
    set_checkpoint(sf, target, spec["capture_instance"], max_lsn, "SNAPSHOT", total)
    log.info("%s: snapshot loaded %d rows", target, total)
    return total


# ---------------- incremental ----------------
def incremental(ms, sf, spec, last_lsn_hex, batch_id, batch_size, auto_resnapshot):
    target, ci = spec["target"], spec["capture_instance"]
    cur = ms.cursor()
    last_lsn = bytes.fromhex(last_lsn_hex)
    min_lsn = cur.execute("SELECT sys.fn_cdc_get_min_lsn(?)", ci).fetchone()[0]
    max_lsn = cur.execute("SELECT sys.fn_cdc_get_max_lsn()").fetchone()[0]
    if min_lsn is None or min_lsn == b"\x00" * 10:
        raise RuntimeError(f"{ci}: capture instance not found or CDC disabled")

    from_lsn = cur.execute("SELECT sys.fn_cdc_increment_lsn(?)", last_lsn).fetchone()[0]
    if from_lsn < min_lsn:
        msg = (f"{target}: checkpoint {last_lsn_hex} is older than CDC retention "
               f"(min LSN {lsn_hex(min_lsn)}) - changes were cleaned up before extraction")
        if auto_resnapshot:
            log.warning("%s -> re-snapshotting", msg)
            return snapshot(ms, sf, spec, batch_id, batch_size)
        raise RuntimeError(msg)
    if from_lsn > max_lsn:
        log.info("%s: no new changes", target)
        return 0

    cols = ", ".join(f"[{c}]" for c in source_columns(ms, spec["source"]))
    sql = f"""
        SELECT {cols},
               __$operation AS _CDC_OPCODE,
               __$start_lsn AS _CDC_LSN_BIN,
               __$seqval    AS _CDC_SEQ_BIN,
               sys.fn_cdc_map_lsn_to_time(__$start_lsn) AS _CDC_COMMIT_TS
        FROM cdc.fn_cdc_get_all_changes_{ci}(?, ?, N'all')
        ORDER BY __$start_lsn, __$seqval"""
    total = 0
    for chunk in pd.read_sql(sql, ms, params=[from_lsn, max_lsn], chunksize=batch_size):
        chunk["_CDC_OP"] = chunk.pop("_CDC_OPCODE").map(OPS)
        chunk["_CDC_LSN"] = chunk.pop("_CDC_LSN_BIN").map(lsn_hex)
        chunk["_CDC_SEQVAL"] = chunk.pop("_CDC_SEQ_BIN").map(lsn_hex)
        total += write(sf, prepare(chunk, batch_id), target)

    set_checkpoint(sf, target, ci, lsn_hex(max_lsn), "INCREMENTAL", total)
    log.info("%s: %d changes (LSN %s -> %s)", target, total, lsn_hex(from_lsn), lsn_hex(max_lsn))
    return total


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--config", default="ingestion/cdc_config.yaml")
    ap.add_argument("--resnapshot", nargs="*", metavar="TARGET",
                    help="force a fresh snapshot for these targets (no value = all)")
    ap.add_argument("--no-trigger", action="store_true", help="do not start the Snowflake DAG")
    args = ap.parse_args()
    cfg = yaml.safe_load(open(args.config))

    batch_id = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%S") + "-" + uuid.uuid4().hex[:6]
    force = None if args.resnapshot is None else (set(args.resnapshot) or {t["target"] for t in cfg["tables"]})
    ms, sf = sqlserver_conn(), snowflake_conn(cfg)
    summary = {}
    try:
        for spec in cfg["tables"]:
            last = get_checkpoint(sf, spec["target"])
            if last is None or (force and spec["target"] in force):
                summary[spec["target"]] = snapshot(ms, sf, spec, batch_id, cfg["batch_size"])
            else:
                summary[spec["target"]] = incremental(ms, sf, spec, last, batch_id, cfg["batch_size"],
                                                      cfg.get("auto_resnapshot_on_gap", False))
        log.info("batch %s: %s", batch_id, summary)
        if cfg.get("trigger_task") and not args.no_trigger and sum(summary.values()) > 0:
            sf.cursor().execute(f"EXECUTE TASK {cfg['trigger_task']}")
            log.info("triggered %s", cfg["trigger_task"])
    finally:
        ms.close()
        sf.close()


if __name__ == "__main__":
    main()
