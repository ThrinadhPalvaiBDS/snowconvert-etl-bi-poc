# SSIS → dbt / Snowflake mapping (Load_SalesDW)

| SSIS element | What SnowConvert AI generates | Enterprise target in this POC | File |
|---|---|---|---|
| SQL Agent job schedule | — | Root task with CRON, retries, timeout | `snowflake/04_orchestration_tasks.sql` |
| Execute SQL – Get Watermark | Inline SQL in TASK | dbt `is_incremental()` + `LOAD_WATERMARK` | `fct_sales.sql`, ingestion |
| Sequence Container | Inline BEGIN…END in parent TASK | Task `T_DBT_DIMENSIONS` | 04 |
| Data Flow Task | One dbt project per DFT | Single layered dbt project | `dbt/` |
| OLE DB Source | dbt source / staging model | `sources.yml` + `stg_*` with dedup | `models/staging` |
| Derived Column | SQL expressions | Same, + `ssis_compat` macros | `stg_*`, `macros/ssis_compat.sql` |
| Data Conversion | CASTs | `money_to_decimal()` | macros |
| Lookup (full cache) | JOIN | LEFT JOIN + unknown member (-1) | `int_order_lines_enriched.sql` |
| Lookup no-match output | — | Rejected model | `int_order_lines_rejected.sql` |
| Conditional Split | CASE / WHERE models | Accepted path filter + rejected model | `fct_sales.sql`, rejected |
| Slowly Changing Dimension (Type 2) | Manual review | dbt snapshot (check strategy) | `snapshots/snap_customer.yml` |
| SCD Type 1 | MERGE/UPDATE | Rebuilt table | `dim_product.sql` |
| OLE DB Destination (fast load) | Table model | Incremental `merge` + clustering | `fct_sales.sql` |
| Execute SQL – Update Watermark | Inline SQL in TASK | `T_POST_LOAD` | 04 |
| Send Mail Task | TASK + `SYSTEM$SEND_EMAIL` | Finalizer task (success + failure) | 04 |
| OnError event handler | Not converted (EWI) | `FINALIZE` task + `PIPELINE_RUN` audit | 04, 07 |
| Package configurations / params | Task variables | dbt `vars`, task `CONFIG` | `dbt_project.yml` |
| SSIS catalog logging | — | `AUDIT.DBT_RUN_RESULTS`, task history | 07, `log_run_results.sql` |

## Intended behaviour changes (sign-off required)
1. **Point-in-time customer lookup** — SSIS joined facts to the *current* customer row; dbt joins to the
   version valid at order time. Region/segment history becomes correct; historical slices can shift.
2. **Unknown member instead of reject** for customer lookup misses — rows are kept with key -1 and also
   logged in `FACTSALES_ERROR`. Totals become *more* complete than legacy; reconciliation marks these
   `REVIEW`, not `FAIL`.
3. **Lookback window** (3 days) on incremental loads catches late updates the strict SSIS watermark missed.

If the business requires exact legacy parity during parallel run, set `fct_sales` to drop
`is_customer_missing` rows and switch the customer join to `is_current` — both are one-line changes.
