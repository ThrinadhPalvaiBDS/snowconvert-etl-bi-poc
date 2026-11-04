"""
Restricted-mode orchestrator (replaces the Snowflake Task DAG until the admin grants
CREATE DBT PROJECT + a Git integration). Mirrors the SSIS control flow:

  Get watermark / extract  -> ingestion (incremental)
  SEQ - Dimensions         -> dbt build: snapshot + dims
  DFT - FactSales          -> dbt build: rejects + fact + compat views
  Update watermark / mail  -> audit row in POC_PIPELINE_RUN + optional Teams/Slack webhook

Schedule it with Windows Task Scheduler / cron on a machine that can reach SQL Server,
or on a self-hosted GitHub Actions runner inside the corporate network.
"""
import os
import subprocess
import sys
import uuid
from datetime import datetime, timezone

import requests
import snowflake.connector
from cryptography.hazmat.primitives import serialization

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RUN_ID = f"{datetime.now(timezone.utc):%Y%m%dT%H%M%S}-{uuid.uuid4().hex[:6]}"

STEPS = [
    ("ingest", [sys.executable, "ingestion/extract_sqlserver_to_snowflake.py",
                "--config", "restricted_mode/extract_config_restricted.yaml"], ROOT),
    ("dbt_deps", ["dbt", "deps"], os.path.join(ROOT, "dbt")),
    ("dbt_dimensions", ["dbt", "build", "--target", "cortex", "--profiles-dir", ".",
                        "--select", "country_region +snap_customer +dim_customer +dim_product dim_date"],
     os.path.join(ROOT, "dbt")),
    ("dbt_facts", ["dbt", "build", "--target", "cortex", "--profiles-dir", ".",
                   "--select", "stg_orders_cdc+ stg_order_lines_cdc+", "--exclude", "+dim_customer +dim_product dim_date"],
     os.path.join(ROOT, "dbt")),
]


def sf_conn():
    with open(os.environ["SNOWFLAKE_PRIVATE_KEY_PATH"], "rb") as fh:
        pw = os.environ.get("SNOWFLAKE_PRIVATE_KEY_PASSPHRASE")
        key = serialization.load_pem_private_key(fh.read(), password=pw.encode() if pw else None)
    return snowflake.connector.connect(
        account=os.environ["SNOWFLAKE_ACCOUNT"], user=os.environ["SNOWFLAKE_USER"],
        private_key=key.private_bytes(serialization.Encoding.DER, serialization.PrivateFormat.PKCS8,
                                      serialization.NoEncryption()),
        role="CORTEX_AI_FULL_ACCESS_ROLE", warehouse="CORTEX_AI_WH",
        database="CORTEX_AI", schema="DATA",
        session_parameters={"QUERY_TAG": "app=snowconvert_poc;layer=orchestrator"})


def audit(conn, status, detail=None, start=False):
    cur = conn.cursor()
    if start:
        cur.execute("INSERT INTO POC_PIPELINE_RUN (RUN_ID, PIPELINE, STATUS, STARTED_AT) "
                    "VALUES (%s, 'Load_SalesDW', 'RUNNING', CURRENT_TIMESTAMP())", (RUN_ID,))
    else:
        cur.execute("UPDATE POC_PIPELINE_RUN SET STATUS = %s, FINISHED_AT = CURRENT_TIMESTAMP(), "
                    "ERROR_DETAIL = %s WHERE RUN_ID = %s", (status, detail, RUN_ID))


def notify(text):
    hook = os.getenv("POC_WEBHOOK_URL")      # Teams / Slack incoming webhook (optional)
    if hook:
        try:
            requests.post(hook, json={"text": text}, timeout=15)
        except requests.RequestException as exc:
            print(f"webhook failed: {exc}")


def main():
    conn = sf_conn()
    audit(conn, "RUNNING", start=True)
    failed = None
    for name, cmd, cwd in STEPS:
        print(f"==> {name}: {' '.join(cmd)}", flush=True)
        res = subprocess.run(cmd, cwd=cwd)
        if res.returncode != 0:
            failed = f"step '{name}' exited with {res.returncode}"
            break
    status = "FAILED" if failed else "SUCCEEDED"
    audit(conn, status, failed)
    conn.close()
    notify(f"Load_SalesDW (SnowConvert POC) {status} - run {RUN_ID}" + (f": {failed}" if failed else ""))
    print(f"{status} run {RUN_ID}")
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
