#!/usr/bin/env python3
"""Generate OpenSearch Dashboards saved-object NDJSON from the human-readable
definitions next to it.

Inputs (committed):
    <stack>-dashboard.json                     - dashboard layout + data views
    <stack>-charts.json                        - chart definitions
        (llm, nginx, query-insights, llm-body-metrics, llm-body-traces)
    llm-body-logs.json                         - data views + Discover search
Outputs (committed, imported by the playbook):
    llm-dashboards.ndjson / nginx-dashboards.ndjson
    query-insights-dashboards.ndjson
    llm-body-observability.ndjson
        one saved object per line: data views, charts, dashboards, search

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
    # A filter may carry a "raw" lucene clause instead of field/value (e.g.
    # a range: {"raw": "upstream_status:>=400"}).
    if filters:
        query = " AND ".join(
            f["raw"] if "raw" in f else f"{f['field']}:{f['value']}" for f in filters
        )
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


def data_views_of(dash: dict) -> list:
    # A dashboard may span several data views (e.g. LLM Body Metrics joins
    # the combined body view with the per-side request/response views).
    # Default: the single data view defined on the dashboard itself.
    dvs = dash.get("data_views")
    if dvs is None:
        dvs = [
            {
                "id": dash["data_view_id"],
                "title": dash["data_view_title"],
                "pattern": dash["data_view_pattern"],
                "time_field": dash.get("time_field", "@timestamp"),
            }
        ]
    return dvs


def data_view_object(dv: dict) -> dict:
    # title MUST be the index pattern: ODS matches the pattern against
    # indices via attributes.title (attributes.name is only a display
    # label). Getting this inverted yields Discover/dashboard errors
    # "No indices match pattern <title>". `fields`/`fieldFormats` are
    # JSON-encoded strings in Kibana 7.x index-patterns; ODS refreshes
    # the field list from the live index on first open of the data view.
    return {
        "attributes": {
            "title": dv["pattern"],
            "name": dv["title"],
            "timeFieldName": dv.get("time_field", "@timestamp"),
            "fields": "[]",
            "fieldFormats": "{}",
        },
        "coreMigrationVersion": CORE_MIGRATION,
        "id": dv["id"],
        "references": [],
        "type": "index-pattern",
    }


def _metric_agg(i: int, m: dict) -> dict:
    # percentiles metrics carry a percents list; plain count has no field.
    if m.get("percents"):
        mtype, params = "percentiles", {"field": m["field"], "percents": m["percents"]}
    elif m.get("field"):
        mtype, params = m["type"], {"field": m["field"]}
    else:
        mtype, params = m["type"], {}
    return {"id": str(i), "enabled": True, "type": mtype, "schema": "metric", "params": params}


def _vislib_vis_state(chart: dict) -> dict:
    chart_type = chart["chart"]
    metrics = chart["metrics"]
    splits = chart.get("splits", [])
    # table (row dimension = a terms split, no time segment) and metric
    # (single value, no time segment) charts have no date_histogram, so
    # their metric ids start at 1; line/area keep the segment as id 1.
    no_segment = chart_type in ("table", "metric")
    base = 1 if no_segment else 2

    aggs = []
    if not no_segment:
        aggs.append(
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
        )
    for i, m in enumerate(metrics):
        aggs.append(_metric_agg(i + base, m))
    # Optional category splits (e.g. per upstream instance / per request
    # id) → one series per bucket, vislib split_group schema. For table
    # charts the split is the row dimension.
    for j, s in enumerate(splits, start=1):
        aggs.append(
            {
                "id": f"s{j}",
                "enabled": True,
                "type": "split_group",
                "schema": "group",
                "params": {
                    "id": f"s{j}",
                    "split_mode": "aggregation",
                    "field": s["field"],
                    "size": s.get("size", 10),
                    "order": "desc",
                    "orderBy": str(base),
                    "customLabel": "",
                },
            }
        )

    if chart_type == "table":
        series = [
            {
                "show": True,
                "type": "column",
                "data": {"label": m["label"], "id": str(i + base)},
                **({"split_id": [f"s{j}" for j in range(1, len(splits) + 1)]} if splits else {}),
                "valueAxis": "",
                "drawLinesBetweenPoints": False,
                "showCircles": False,
            }
            for i, m in enumerate(metrics)
        ]
        params = {
            "type": "table",
            "series": series,
            "addTooltip": True,
            "addLegend": False,
            "legendPosition": "right",
            "timeseries": [],
            "thresholdLine": {"show": False, "value": 10, "width": 1, "style": "full", "color": "#34130C"},
        }
    elif chart_type == "metric":
        series = [
            {
                "show": True,
                "type": "metric",
                "data": {"label": m["label"], "id": str(i + base)},
                "valueAxis": "",
                "drawLinesBetweenPoints": False,
                "showCircles": False,
            }
            for i, m in enumerate(metrics)
        ]
        params = {
            "type": "metric",
            "series": series,
            "addTooltip": True,
            "addLegend": True,
            "legendPosition": "right",
            "timeseries": [],
            "thresholdLine": {"show": False, "value": 10, "width": 1, "style": "full", "color": "#34130C"},
        }
    else:
        params = {
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
                    "data": {"label": m["label"], "id": str(i + base)},
                    **({"split_id": [f"s{j}" for j in range(1, len(splits) + 1)]} if splits else {}),
                    "valueAxis": "ValueAxis-1",
                    "drawLinesBetweenPoints": True,
                    "showCircles": True,
                }
                for i, m in enumerate(metrics)
            ],
            "addTooltip": True,
            "addLegend": True,
            "legendPosition": "right",
            "timeseries": [],
            "thresholdLine": {"show": False, "value": 10, "width": 1, "style": "full", "color": "#34130C"},
        }
    return {"title": chart["title"], "type": chart_type, "params": params, "aggs": aggs}


def visualization_object(dash: dict, chart: dict) -> dict:
    # A chart may target a data view other than the dashboard's default
    # (multi-data-view dashboards like LLM Body Metrics).
    dv_id = chart.get("data_view") or dash.get("data_view_id")
    return {
        "attributes": {
            "title": chart["title"],
            "description": chart.get("description", ""),
            "visState": json.dumps(_vislib_vis_state(chart), separators=(",", ":")),
            "uiStateJSON": "{}",
            "kibanaSavedObjectMeta": {
                "searchSourceJSON": _search_source(dv_id, chart.get("filters", [])),
            },
        },
        "coreMigrationVersion": CORE_MIGRATION,
        "id": chart["viz_id"],
        "references": [
            {
                "id": dv_id,
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


def search_object(s: dict) -> dict:
    # Core "search" (Discover) saved object — the log browser. Shape
    # copied verbatim from a live ODS 2.19.6 search doc (.kibana_1).
    dv = s["data_view"]
    return {
        "attributes": {
            "title": s["title"],
            "description": s.get("description", ""),
            "hits": 0,
            "columns": s["columns"],
            "sort": [s.get("sort_field", "@timestamp"), "desc"],
            "version": 1,
            "kibanaSavedObjectMeta": {
                "searchSourceJSON": json.dumps(
                    {
                        "highlightAll": True,
                        "version": True,
                        "query": {"language": "kuery", "query": ""},
                        "filter": [],
                        "indexRefName": "kibanaSavedObjectMeta.searchSourceJSON.index",
                    },
                    separators=(",", ":"),
                )
            },
        },
        "coreMigrationVersion": CORE_MIGRATION,
        "id": s["id"],
        "references": [
            {
                "id": dv["id"],
                "name": "kibanaSavedObjectMeta.searchSourceJSON.index",
                "type": "index-pattern",
            }
        ],
        "migrationVersion": {"search": DASH_MIGRATION},
        "type": "search",
    }


def build_stack(dash: dict, charts: list) -> list:
    # Topological order: data views first, then charts, then dashboard.
    return [
        *(data_view_object(dv) for dv in data_views_of(dash)),
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
        ("query-insights-dashboard.json", "query-insights-charts.json", "query-insights-dashboards.ndjson"),
    ]:
        dash = json.loads((HERE / dash_name).read_text(encoding="utf-8"))
        charts = json.loads((HERE / charts_name).read_text(encoding="utf-8"))
        write_ndjson(HERE / out_name, build_stack(dash, charts))

    # LLM body observability: two dashboards (metrics + traces) over the
    # body indices, plus the log views (a core Discover search and the
    # Observability app's Logs Explorer saved searches). Data views may be
    # declared by several objects, so dedupe by id, first occurrence wins.
    body_objects = []
    for dash_name, charts_name in [
        ("llm-body-metrics-dashboard.json", "llm-body-metrics-charts.json"),
        ("llm-body-traces-dashboard.json", "llm-body-traces-charts.json"),
    ]:
        dash = json.loads((HERE / dash_name).read_text(encoding="utf-8"))
        charts = json.loads((HERE / charts_name).read_text(encoding="utf-8"))
        body_objects.extend(build_stack(dash, charts))
    # Note: ODS 2.19.6 (this build) does not register the
    # "observability-search" saved object type (import returns 422), so the
    # Logs Explorer saved-search idea is not viable here — the Discover
    # search below is the log browser.
    logs = json.loads((HERE / "llm-body-logs.json").read_text(encoding="utf-8"))
    body_objects.extend(data_view_object(dv) for dv in logs.get("data_views", []))
    body_objects.extend(search_object(s) for s in logs.get("searches", []))
    seen = set()
    deduped = []
    for obj in body_objects:
        if obj["id"] in seen:
            continue
        seen.add(obj["id"])
        deduped.append(obj)
    write_ndjson(HERE / "llm-body-observability.ndjson", deduped)


if __name__ == "__main__":
    main()
