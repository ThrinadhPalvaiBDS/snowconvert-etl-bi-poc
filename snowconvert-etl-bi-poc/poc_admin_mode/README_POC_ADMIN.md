# POC_ADMIN mode — full enterprise layout with delegated privileges

With POC_ADMIN (CREATE DATABASE / WAREHOUSE / INTEGRATION, EXECUTE TASK / ALERT,
IMPORTED PRIVILEGES on SNOWFLAKE) plus USERADMIN, the original design runs almost unchanged:
own databases, layered schemas, a real `DBO` schema (no Power Query edits), three warehouses,
dbt Projects on Snowflake and a task DAG. This mode supersedes `restricted_mode/`.

## Ownership model
| Object | Owner | Why |
|---|---|---|
| Databases, schemas (managed access), warehouses, integrations, tasks | POC_ADMIN | Only role with the account privileges; managed access lets it define future grants |
| Functional roles, service users | USERADMIN | You hold it; admin not needed to change keys/tokens |
| Git repository secret | POC_ADMIN; READ/WRITE granted to TRANSFORMER | |
| dbt project | TRANSFORMER | CI user can add versions without POC_ADMIN |
| dbt-built tables/views | TRANSFORMER | Future grants give BI_READER SELECT automatically |

## Run order (as THRINADHP)
1. `00_verify_admin_grants.sql` — confirm the admin's work; check `SVC_POC_POWERBI` type.
2. Send `ADMIN_FOLLOWUP.sql` items 1 (Power BI PAT policy) and 2 (resource monitor, after step 3).
3. `01_bootstrap_poc_admin.sql` — roles, users, warehouses, databases, grants, integrations.
4. `02_raw_landing.sql`, `04_governance.sql`, `07_observability.sql`.
5. CDC ingest (see `docs/cdc_design.md`):
   a. DBA runs `legacy/sqlserver/03_enable_cdc.sql` on the SQL Server source.
   b. Run `10_cdc_raw.sql` (change tables + checkpoint).
   c. `.env` → `SNOWFLAKE_LOADER_USER=SVC_POC_PIPELINE`, then
      `python ingestion/cdc_extract_sqlserver.py --no-trigger` (first run = snapshot).
6. Push the repo to `github.com/ThrinadhPalvaiBDS/snowconvert-etl-bi-poc`, then `05_dbt_project_deploy.sql`.
7. `06_orchestration_tasks.sql`, then `EXECUTE TASK SALES_DW_PROD.AUDIT.T_ROOT_SALES_DW;`
   From now on schedule the extractor every 15 min; it triggers the DAG whenever changes landed.
8. `08_alerts.sql` (after the first successful build).
9. `09_powerbi_access.sql` (after ADMIN_FOLLOWUP item 1) → Power BI with server/`WH_BI`/`SALES_DW_PROD`; schema stays `DBO`.
10. Copy `dbt_deploy_poc_admin.yml` to `.github/workflows/dbt_deploy.yml`.

Everything after step 4 follows the main README phases unchanged.

## Not available in this mode
* Network policies (needs SECURITYADMIN-level privilege) → PAT waiver policy for the POC.
* Resource monitors → ADMIN_FOLLOWUP item 2; meanwhile watch `AUDIT.V_WAREHOUSE_COST`.
