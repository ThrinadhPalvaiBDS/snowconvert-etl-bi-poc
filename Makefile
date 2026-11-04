include .env
export

.PHONY: setup snowflake-bootstrap ingest dbt-build dbt-deploy reconcile pbi-cutover dax-parity

setup:
	pip install -r validation/requirements.txt
	cd dbt && dbt deps

snowflake-bootstrap:
	for f in snowflake/0[0-2]*.sql snowflake/05*.sql snowflake/06*.sql snowflake/07*.sql; do \
	  echo "==> $$f"; snow sql -f $$f --connection poc_admin || exit 1; done

ingest:
	python ingestion/extract_sqlserver_to_snowflake.py --config ingestion/extract_config.yaml

dbt-build:
	cd dbt && dbt build --target dev

dbt-deploy:
	snow sql -f snowflake/03_dbt_project_deploy.sql --connection poc_admin
	snow sql -f snowflake/04_orchestration_tasks.sql --connection poc_admin
	snow sql -f snowflake/08_alerts.sql --connection poc_admin

reconcile:
	python validation/reconcile.py --config validation/reconciliation_config.yaml

pbi-cutover:
	python powerbi/pbi_cutover.py --config powerbi/cutover_config.yaml

dax-parity:
	python powerbi/dax_parity_test.py --config powerbi/cutover_config.yaml

# ---------- restricted mode (no ACCOUNTADMIN) ----------
.PHONY: r-setup r-ingest r-dbt r-run r-reconcile
r-setup:
	for f in restricted_mode/R01*.sql restricted_mode/R02*.sql restricted_mode/R03*.sql; do \
	  echo "==> $$f"; snow sql -f $$f --connection poc_user || exit 1; done
r-ingest:
	python ingestion/extract_sqlserver_to_snowflake.py --config restricted_mode/extract_config_restricted.yaml
r-dbt:
	cd dbt && dbt build --target cortex --profiles-dir .
r-run:
	python restricted_mode/run_pipeline.py
r-reconcile:
	python validation/reconcile.py --config restricted_mode/reconciliation_config_restricted.yaml
