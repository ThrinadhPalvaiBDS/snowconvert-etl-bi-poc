{#- Post-hook on marts: re-apply PII tags after every CREATE OR REPLACE.
    Tag-based masking then masks the column automatically. -#}
{% macro apply_governance() %}
  {%- set tag = 'CORTEX_AI.GOVERNANCE.POC_PII_CLASS' if target.name == 'cortex'
               else 'PLATFORM.GOVERNANCE.PII_CLASS' -%}
  {%- if target.name in ('prod', 'cortex') and this.identifier | upper == 'DIM_CUSTOMER' -%}
    alter table {{ this }} modify column email set tag {{ tag }} = 'EMAIL'
  {%- else -%}
    select 1
  {%- endif -%}
{% endmacro %}
