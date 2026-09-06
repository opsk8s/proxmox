#!/usr/bin/env python3
"""Generate OpenSearch Dashboards saved-object NDJSON from the human-readable
definitions next to it.

Inputs (committed):
    llm-dashboard.json / nginx-dashboard.json  - dashboard layout
    llm-charts.json / nginx-charts.json        - TSVB chart definitions
Outputs (committed, imported by the playbook):
    llm-dashboards.ndjson / nginx-dashboards.ndjson
        one saved object per line: data view, then charts, then dashboard

Run locally after editing the definitions:
    python3 modules/elk/dashboards/generate_ods_objects.py

The playbook imports each file via
    POST /api/saved_objects/_import?overwrite=true
which is idempotent (objects are replaced in place on every run).
"""

import json
from pathlib import Path

HERE = Path(__file__).resolve().parent

# ODS is a Kibana 7.10 fork: classic saved objects with this migration
# version import and render cleanly.
MIGRATION_VERSION = "7.8.0"

# Default Kibana series palette.
PALETTE = ["#61dafb", "#61a0eb", "#f5a700", "#d87c7c", "#956cb4"]

# TSVB time-bucket x-axis: same as the Lens charts these replace.
BUCKET_ID = "bucket-1"
BUCKET_AGG = {
    "id": BUCKET_ID,
    "type": "date_histogram",
    "settings": {
        "field": "@timestamp",
        "interval": "auto",
        "min_doc_count": 0,
        "extended_bounds": {},
    },
}


def tsvb_params(chart_type: str) -> dict:
    params = {
        "type": chart_type,
        "groups": [],
        "styles": [],
        "addTooltip": True,
        "addLegend": True,
        "scale": "Linear",
        "timezone": "browser",
        "interpolate": "linear",
        "radius": True,
        "yAxis": {"style": {}, "show": True, "log": False, "mask": False, "reversed": False},
        "setPos": None,
    }
    if chart_type == "area":
        params["smoothLines"] = True
    return params


def tsvb_aggs(metrics: list) -> list:
    aggs = [BUCKET_AGG]
    for i, m in enumerate(metrics, start=1):
        aggs.append({
            "id": f"metric-{i}",
            "type": m["type"],
            "settings": {"field": m["field"]} if m.get("field") else {},
        })
    return aggs


def tsvb_aggs_schema(metrics: list) -> dict:
    return {
        "groups": [{
            "id": BUCKET_ID,
            "type": "date_histogram",
            "schema": {"id": "bucket", "type": "string"},
            "rowStyle": {},
            "rowColor": "",
        }],
        "metrics": [
            {
                "id": f"metric-{i}",
                "type": m["type"],
                "schema": {"id": "metric", "type": "number"},
                "decimals": 0 if m["type"] == "count" else 3,
                "labels": True,
                "label": m["label"],
                "color": PALETTE[(i - 1) % len(PALETTE)],
            }
            for i, m in enumerate(metrics, start=1)
        ],
    }


def search_source(data_view_id: str, filters: list) -> str:
    # query_string is the most portable saved-object query shape across
    # Kibana 7.x / ODS — field:value terms on .keyword fields match exactly.
    if filters:
        query = " AND ".join(f"{f['field']}:{f['value']}" for f in filters)
        q = {"query_string": {"query": query, "analyze_wildcard": True, "default_operator": "and"}}
    else:
        q = {"query_string": {"query": "*", "analyze_wildcard": True}}
    return json.dumps(
        {
            "index": data_view_id,
            "filter": [],
            "highlight": {
                "pre_tags": ["@kibana-highlighted-field@"],
                "post_tags": ["@/kibana-highlighted-field@"],
                "fields": ["*"],
                "require_field_match": False,
                "test_field": "message",
            },
            "query": q,
        },
        separators=(",", ":"),
    )


def data_view_object(dash: dict) -> dict:
    # `fields`/`fieldFormats` are JSON-encoded strings in Kibana 7.x
    # index-patterns; ODS refreshes the field list from the live index on
    # first open of the data view.
    return {
        "attributes": {
            "title": dash["data_view_title"],
            "name": dash["data_view_pattern"],
            "timeFieldName": "@timestamp",
            "fields": "[]",
            "fieldFormats": "{}",
        },
        "coreMigrationVersion": MIGRATION_VERSION,
        "id": dash["data_view_id"],
        "references": [],
        "type": "index-pattern",
    }


def visualization_object(dash: dict, chart: dict) -> dict:
    return {
        "attributes": {
            "title": chart["title"],
            "description": chart.get("description", ""),
            "visualization": {
                "id": chart["chart"],
                "type": chart["chart"],
                "params": tsvb_params(chart["chart"]),
                "aggs": tsvb_aggs(chart["metrics"]),
                "aggsSchema": tsvb_aggs_schema(chart["metrics"]),
            },
            "searchSourceJSON": search_source(dash["data_view_id"], chart.get("filters", [])),
        },
        "coreMigrationVersion": MIGRATION_VERSION,
        "id": chart["viz_id"],
        "references": [
            {"id": dash["data_view_id"], "name": "index", "type": "index-pattern"}
        ],
        "type": "visualization",
    }


def dashboard_object(dash: dict, charts: list) -> dict:
    viz_by_title = {c["title"]: c["viz_id"] for c in charts}
    panels = []
    references = []
    for i, panel in enumerate(dash["panels"]):
        index = f"p-{i + 1}"
        viz_id = viz_by_title[panel["title"]]
        panels.append({
            "embeddableConfig": {"id": viz_id, "type": "visualization"},
            "gridData": {"x": panel["x"], "y": panel["y"], "w": panel["w"], "h": panel["h"], "i": index},
            "panelIndex": index,
            "version": 1,
        })
        references.append({"id": viz_id, "name": index, "type": "visualization"})
    return {
        "attributes": {
            "title": dash["title"],
            "description": dash.get("description", ""),
            "panels": panels,
            "attributesSchemaVersion": 2,
            "options": {"useMargins": False, "hidePanelTitles": False, "adhocDatasets": []},
            "refreshInterval": {"display": "10 seconds", "pause": False, "value": 10000},
            "timeRestore": False,
            "version": 1,
        },
        "coreMigrationVersion": MIGRATION_VERSION,
        "id": dash["id"],
        "references": references,
        "type": "dashboard",
    }


def build_stack(dash: dict, charts: list) -> list:
    # Topological order: data view first, then charts, then dashboard.
    return [
        data_view_object(dash),
        *(visualization_object(dash, c) for c in charts),
        dashboard_object(dash, charts),
    ]


def write_ndjson(path: Path, objects: list) -> None:
    path.write_text(
        "".join(json.dumps(o, separators=(",", ":")) + "\n" for o in objects),
        encoding="utf-8",
    )
    print(f"{path.name}: {len(objects)} objects")


def main() -> None:
    for dash_name, charts_name, out_name in [
        ("llm-dashboard.json", "llm-charts.json", "llm-dashboards.ndjson"),
        ("nginx-dashboard.json", "nginx-charts.json", "nginx-dashboards.ndjson"),
    ]:
        dash = json.loads((HERE / dash_name).read_text(encoding="utf-8"))
        charts = json.loads((HERE / charts_name).read_text(encoding="utf-8"))
        write_ndjson(HERE / out_name, build_stack(dash, charts))


if __name__ == "__main__":
    main()
