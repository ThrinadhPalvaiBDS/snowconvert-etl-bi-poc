# Restricted mode — running the POC without ACCOUNTADMIN

Built from the grants inventory of user THRINADHP (account DIC19309, AWS_US_EAST_1).

## What you have and how the POC uses it
| Your privilege | Used for |
|---|---|
| CORTEX_AI_FULL_ACCESS_ROLE: CREATE TABLE/VIEW/STAGE/FILE FORMAT/TASK/PROCEDURE/STREAM/DYNAMIC TABLE on `CORTEX_AI.DATA` | All POC layers (RAW_, STG_, INT_, SNAP_, DIM_, FCT_, compat views) |
| CREATE TAG on `CORTEX_AI.GOVERNANCE`; APPLY TAG / MASKING / ROW ACCESS on account | PII tag-based masking, region row access |
| USAGE/OPERATE/MONITOR on `CORTEX_AI_WH` (XS) | All compute (cannot resize; fine for POC volumes) |
| EXECUTE TASK on account | Available later for native orchestration |
| SNOWFLAKE.USAGE_VIEWER | Cost views from ACCOUNT_USAGE |
| USERADMIN: CREATE ROLE / CREATE USER | Service users + POC_BI_READER role |

## What is blocked and the substitute
| Blocked (missing privilege) | Substitute in restricted mode |
|---|---|
| CREATE DATABASE / WAREHOUSE / SCHEMA in CORTEX_AI | One schema (`CORTEX_AI.DATA`), prefixed object names, shared XS warehouse |
| CREATE DBT PROJECT, CREATE GIT REPOSITORY, CREATE INTEGRATION | dbt Core runs outside Snowflake (`--target cortex`), orchestrated by `run_pipeline.py` |
| Email notification integration, EXECUTE ALERT | Audit table `POC_PIPELINE_RUN` + Teams/Slack webhook from `run_pipeline.py` |
| Resource monitor | Query tags + `POC_V_WAREHOUSE_COST` / `POC_V_QUERY_PERF` |
| Granting DB/schema/warehouse USAGE to new roles | Admin tier 1 (one-time, 4 lines) |
| Power BI OAuth security integration | Basic auth with a service user (or your own user in Desktop) |

**Impact on "no report rebuild":** repointed reports reference schema `DBO`; here the compat
views live in `DATA`. In each repointed query change the schema step from `"DBO"` to `"DATA"`
(Power Query → Advanced Editor). That is a connection edit, not a visual/measure rebuild, and it
disappears once the admin grants tier 2 (then create a real `DBO` schema).

## Run order
1. `R00_service_users.sql` (USERADMIN) — then put a key pair on THRINADHP for now.
2. `R01_setup_cortex_ai.sql` — landing objects, watermark, audit tables.
3. `R02_governance.sql` — tag, masking, row access.
4. `R03_observability.sql` — then test `SELECT COUNT(*) FROM SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY;`
5. Ingest: `python ingestion/extract_sqlserver_to_snowflake.py --config restricted_mode/extract_config_restricted.yaml --full-refresh`
6. dbt: `cd dbt && dbt deps && dbt build --target cortex --profiles-dir .`
7. Scheduled runs: `python restricted_mode/run_pipeline.py` (Task Scheduler / cron / self-hosted runner)
8. `R04_powerbi_access.sql` part A (after step 6 so the views exist); send `ADMIN_REQUEST.sql` for part B.
9. Reconcile: `python validation/reconcile.py --config restricted_mode/reconciliation_config_restricted.yaml`
10. Power BI: open repointed .pbit with server/warehouse `CORTEX_AI_WH`/database `CORTEX_AI`, change schema `DBO`→`DATA`, then
    `python powerbi/pbi_cutover.py --config restricted_mode/cutover_config_restricted.yaml` and the DAX parity test.

`.env` for restricted mode: `SNOWFLAKE_USER=THRINADHP` (later `SVC_POC_PIPELINE`),
`SNOWFLAKE_LOADER_USER=THRINADHP`, `SNOWFLAKE_ROLE=CORTEX_AI_FULL_ACCESS_ROLE`, `SNOWFLAKE_WAREHOUSE=CORTEX_AI_WH`.

## Upgrade path as the admin grants each tier
* Tier 1 → switch `.env` to `SVC_POC_PIPELINE`; Power BI Service refresh with `SVC_POC_POWERBI`.
* Tier 2 → create `POC_RAW`, `POC_STAGING`, `POC_MARTS`, `DBO` schemas and point dbt at the standard project layout (target `prod`-style schema mapping); remove the `DBO`→`DATA` edit.
* Tier 3 → `snowflake/03_dbt_project_deploy.sql` + `04_orchestration_tasks.sql` (adapted names) replace `run_pipeline.py`.
* Tier 4 → finalizer email + freshness alert.
