-- Current (non-deleted) products, maintained by SQL Server CDC via stg_products_cdc.
-- Same columns as before, plus cdc_loaded_at for incremental change detection downstream.
select * exclude (is_deleted, cdc_operation, cdc_lsn, cdc_commit_ts)
from {{ ref('stg_products_cdc') }}
where not is_deleted
