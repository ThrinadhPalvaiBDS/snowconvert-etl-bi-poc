# CDC incremental processing

## Why CDC instead of the ModifiedDate watermark
| Concern | Watermark on ModifiedDate | SQL Server CDC |
|---|---|---|
| Deletes | Invisible | Captured (op `D`) |
| Updates that don't touch ModifiedDate | Missed | Captured from the transaction log |
| Ordering | Timestamp ties / clock skew | LSN + seqval, strictly ordered |
| Source load | Range scan on base tables | Reads change tables only |

## Flow
```
SQL Server tx log ──CDC capture job──> cdc.dbo_<Table>_CT
      │  cdc_extract_sqlserver.py (every 15 min, near SQL Server)
      ▼
RAW.<TABLE>_CT  (append-only: S/I/U/D + _CDC_LSN/_CDC_SEQVAL)  + RAW.CDC_CHECKPOINT
      │  EXECUTE TASK T_ROOT_SALES_DW (triggered by the extractor when rows landed)
      ▼
STAGING.stg_<x>_cdc  incremental MERGE: latest change per key, soft-delete flag
STAGING.stg_<x>      view: current non-deleted rows (same contract as before)
      ▼
SNAPSHOTS.snap_customer (SCD2, hard deletes -> invalidated)
MARTS.fct_sales      incremental MERGE on changed_at + post-hook DELETE of removed lines
      ▼
DBO compat views -> Power BI (unchanged)
```

## Guarantees
* **At-least-once landing, exactly-once state**: checkpoint advances after the write; dbt dedups on
  (key, LSN, seqval) and refuses to overwrite a newer LSN with an older one.
* **Snapshot consistency**: snapshot rows carry the max LSN read *before* the copy; any change made
  during the copy arrives again with a higher LSN and wins.
* **Retention gap**: if the extractor is down longer than CDC retention (set to 7 days), the table is
  re-snapshotted automatically. Afterwards rebuild its state so keys deleted during the gap disappear:
  `dbt build --full-refresh --select stg_<x>_cdc+`.

## Operating it
* Schedule: `python ingestion/cdc_extract_sqlserver.py` every 15 min (Task Scheduler / cron / self-hosted runner).
* Force a reload: `--resnapshot SALESORDERDETAIL_CT` (or `--resnapshot` for all), then the full-refresh above.
* Monitor: `SALES_DW_PROD.AUDIT.V_CDC_LAG`, `RAW.CDC_CHECKPOINT`, and on SQL Server `sys.dm_cdc_log_scan_sessions`.

## Demo script for the POC
1. In SQL Server: update a customer's City, delete one order line, insert a new order.
2. Run the extractor -> it lands 3+ change rows and triggers the DAG.
3. Show: new SCD2 version in `DIM_CUSTOMER`, the deleted line gone from `FCT_SALES`, the new order present,
   and the Power BI report reflecting all three after refresh.

## Production option
Snowflake Openflow's SQL Server CDC connector replaces the Python extractor with a managed service;
it needs account-level setup by an admin. RAW change-table contracts and all dbt models stay the same.
