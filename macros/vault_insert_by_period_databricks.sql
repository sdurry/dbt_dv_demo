{#
  Databricks override of automate_dv's vault_insert_by_period materialization.
  Instead of looping through time-period batches, this does a single native INSERT INTO,
  relying on the LEFT ANTI JOIN already in the hub/link/sat SQL for deduplication.
  The __PERIOD_FILTER__ placeholder is replaced with TRUE so no period slicing occurs.
#}
{% materialization vault_insert_by_period, adapter='databricks' %}

    {%- set full_refresh_mode = (should_full_refresh()) -%}
    {%- set target_relation = this.incorporate(type='table') -%}
    {%- set existing_relation = load_relation(this) -%}

    {#- Strip the period placeholder — the LEFT ANTI JOIN handles dedup -#}
    {%- set full_sql = sql | replace('__PERIOD_FILTER__', 'TRUE') -%}

    {{ run_hooks(pre_hooks, inside_transaction=False) }}
    {{ run_hooks(pre_hooks, inside_transaction=True) }}

    {% if existing_relation is none or full_refresh_mode %}

        {% if existing_relation is not none and full_refresh_mode %}
            {% do adapter.drop_relation(existing_relation) %}
        {% endif %}

        {% call statement('main') %}
            {{ create_table_as(False, target_relation, full_sql) }}
        {% endcall %}

    {% else %}

        {%- set target_columns = adapter.get_columns_in_relation(target_relation) -%}
        {%- set target_cols_csv = target_columns | map(attribute='quoted') | join(', ') -%}

        {% call statement('main') %}
            INSERT INTO {{ target_relation }} ({{ target_cols_csv }})
            {{ full_sql }}
        {% endcall %}

    {% endif %}

    {{ run_hooks(post_hooks, inside_transaction=True) }}
    {{ run_hooks(post_hooks, inside_transaction=False) }}
    {{ adapter.commit() }}

    {{ return({'relations': [target_relation]}) }}

{% endmaterialization %}
