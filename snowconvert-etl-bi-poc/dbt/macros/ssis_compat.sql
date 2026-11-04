{#- Helpers for SSIS expression semantics that SnowConvert flags as functional differences -#}

{# SSIS: ISNULL(col) ? 'Unknown' : TRIM(col) - also treats blank strings as missing #}
{% macro ssis_default_unknown(col, default="'Unknown'") -%}
    coalesce(nullif(trim({{ col }}), ''), {{ default }})
{%- endmacro %}

{# SSIS Data Conversion MONEY -> DT_NUMERIC(19,4) #}
{% macro money_to_decimal(col) -%}
    cast(round({{ col }}, 4) as number(19,4))
{%- endmacro %}

{# yyyymmdd integer surrogate used by legacy DimDate #}
{% macro date_key(col) -%}
    cast(to_char(cast({{ col }} as date), 'YYYYMMDD') as integer)
{%- endmacro %}
