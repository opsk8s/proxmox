#!/usr/bin/env python3
"""Generate OpenSearch Dashboards saved-object NDJSON from the human-readable
definitions next to it.

Inputs (committed):
    llm-dashboard.json / nginx-dashboard.json  - dashboard layout
    llm-charts.json / nginx-charts.json        - line/area chart definitions
Outputs (committed, imported by the playbook):
    llm-dashboards.ndjson / nginx-dashboards.ndjson
        one saved object per line: data view, then charts, then dashboard

Run locally after editing the definitions:
    python3 modules/elk/dashboards/generate_ods_objects.py

The playbook imports each file via
    POST /api/saved_objects/_import?overwrite=true (header: osd-xsrf: true)
which is idempotent (objects are replaced in place on every run).

Object shapes are the CLASSIC Kibana 7.10 / ODS 2.x forms, verified against a
live ODS 2.19.6 on 2026-09-06:
  - index-pattern: attributes {title, name, timeFieldName, fields, fieldFormats}
  - visualization: attributes.visState (JSON string, vislib line/area) +
    kibanaSavedObjectMeta.searchSourceJSON (index + lucene query)
  - dashboard: panelsJSON/optionsJSON strings with 7.3.0-format panels
Type migrationVersions are pinned to the fork point so no stale migrations
run on import (e.g. ODS has no 7.x "visualization object" schema — using one
blows up migrateTableSplits with "Unexpected token u in JSON").
"""

import json
from pathlib import Path

HERE = Path(__file__).resolve().parent

# Type-specific migration versions at the Kibana 7.10 fork point.
VIZ_MIGRATION = "7.10.0"
DASH_MIGRATION = "7.9.3"
CORE_MIGRATION = "7.8.0"


def _search_source(data_view_id: str, filters: list) -> str:
    # lucene query on .keyword fields: the classic searchSource query shape.
    if filters:
        query = " AND ".join(f"{f['field']}:{f['value']}" for f in filters)
    else:
        query = "*"
    return json.dumps(
        {
            "index": data_view_id,
            "query": {"query": query, "language": "lucene"},
            "filter": [],
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
        "coreMigrationVersion": CORE_MIGRATION,
        "id": dash["data_view_id"],
        "references": [],
        "type": "index-pattern",
    }


def _vislib_vis_state(chart: dict) -> dict:
    chart_type = chart["chart"]
    metrics = chart["metrics"]
    aggs = [
        {
            "id": "1",
            "enabled": True,
            "type": "date_histogram",
            "schema": "segment",
            "params": {
                "field": "@timestamp",
                "useNormalizedOpenSearchInterval": True,
                "interval": "auto",
                "drop_partials": False,
                "customInterval": "2h",
                "min_doc_count": 0,
                "extended_bounds": {},
            },
        }
    ]
    for i, m in enumerate(metrics, start=2):
        params = {"field": m["field"]} if m.get("field") else {}
        aggs.append(
            {
                "id": str(i),
                "enabled": True,
                "type": m["type"],
                "schema": "metric",
                "params": params,
            }
        )
    return {
        "title": chart["title"],
        "type": chart_type,
        "params": {
            "type": chart_type,
            "grid": {"categoryLines": False, "style": {"color": "#eee"}},
            "categoryAxes": [
                {
                    "id": "CategoryAxis-1",
                    "type": "category",
                    "position": "bottom",
                    "show": True,
                    "style": {},
                    "scale": {"type": "linear"},
                    "labels": {"show": True, "filter": True, "truncate": 100},
                    "title": {},
                }
            ],
            "valueAxes": [
                {
                    "id": "ValueAxis-1",
                    "name": "LeftAxis-1",
                    "type": "value",
                    "position": "left",
                    "show": True,
                    "style": {},
                    "scale": {"type": "linear", "mode": "normal"},
                    "labels": {"show": True, "rotate": 0, "filter": False, "truncate": 100},
                    "title": {"text": ""},
                }
            ],
            "seriesParams": [
                {
                    "show": True,
                    "type": chart_type,
                    "mode": "normal",
                    "data": {"label": m["label"], "id": str(i)},
                    "valueAxis": "ValueAxis-1",
                    "drawLinesBetweenPoints": True,
                    "showCircles": True,
                }
                for i, m in enumerate(metrics, start=2)
            ],
            "addTooltip": True,
            "addLegend": True,
            "legendPosition": "right",
            "timeseries": [],
            "thresholdLine": {"show": False, "value": 10, "width": 1, "style": "full", "color": "#34130C"},
        },
        "aggs": aggs,
    }


def visualization_object(dash: dict, chart: dict) -> dict:
    return {
        "attributes": {
            "title": chart["title"],
            "description": chart.get("description", ""),
            "visState": json.dumps(_vislib_vis_state(chart), separators=(",", ":")),
            "uiStateJSON": "{}",
            "kibanaSavedObjectMeta": {
                "searchSourceJSON": _search_source(dash["data_view_id"], chart.get("filters", [])),
            },
        },
        "coreMigrationVersion": CORE_MIGRATION,
        "id": chart["viz_id"],
        "references": [
            {
                "id": dash["data_view_id"],
                "name": "kibanaSavedObjectMeta.searchSourceJSON.index",
                "type": "index-pattern",
            }
        ],
        "migrationVersion": {"visualization": VIZ_MIGRATION},
        "type": "visualization",
    }


def dashboard_object(dash: dict, charts: list) -> dict:
    viz_by_title = {c["title"]: c["viz_id"] for c in charts}
    panels = []
    references = []
    for i, panel in enumerate(dash["panels"], start=1):
        viz_id = viz_by_title[panel["title"]]
        panels.append(
            {
                "version": "7.3.0",
                "type": "visualization",
                "panelIndex": str(i),
                "embeddableConfig": {},
                "gridData": {
                    "x": panel["x"], "y": panel["y"], "w": panel["w"], "h": panel["h"], "i": str(i),
                },
                "id": viz_id,
            }
        )
        references.append({"id": viz_id, "name": f"panel_{i}", "type": "visualization"})
    return {
        "attributes": {
            "title": dash["title"],
            "description": dash.get("description", ""),
            "hits": 0,
            "version": 1,
            "timeRestore": False,
            "optionsJSON": json.dumps({"useMargins": False, "hidePanelTitles": False}, separators=(",", ":")),
            "panelsJSON": json.dumps(panels, separators=(",", ":")),
        },
        "coreMigrationVersion": CORE_MIGRATION,
        "id": dash["id"],
        "references": references,
        "migrationVersion": {"dashboard": DASH_MIGRATION},
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
