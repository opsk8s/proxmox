#!/usr/bin/env python3
"""Create the LLM Observability Kibana content (data view + lens charts + dashboard).

Kibana 9 notes (all verified against the running 9.5.2 install):
  * `POST /api/saved_objects/index-pattern/<id>` is how data views are created
    (the saved-object type for data views is "index-pattern", not "data_view";
    the as-code `POST /api/data_views` route is tech-preview-gated and not
    available without a feature flag).
  * `POST /api/visualizations` (Lens as-code API, stable in 9.5) takes the
    chart config WITHOUT `id`/`version`; the id is generated and returned.
  * Filters use the as-code condition shape:
    {"type": "condition", "condition": {"field", "operator", "value"}}.
  * The dashboard saved object (type "dashboard") uses the panels+references
    shape; v3 schema ignores unknown keys so attributesSchemaVersion/panels
    pass validation.

Idempotent: re-running deletes the managed lenses (by exact title) and
recreates everything, then rewrites the dashboard with the fresh lens ids.

Usage: python3 build_kibana_content.py <kibana_base_url> <definitions_dir> [lenses_file] [dashboard_file]
(lenses_file/dashboard_file default to llm-lenses.json / llm-dashboard.json —
the playbook runs it once per dashboard definition pair.)
Stdlib only — safe on the ELK VM without extra packages.
"""
import json
import sys
import urllib.error
import urllib.parse
import urllib.request


def req(base, path, method="GET", body=None):
    url = base + path
    data = json.dumps(body).encode() if body is not None else None
    r = urllib.request.Request(url, data=data, method=method)
    r.add_header("kbn-xsrf", "true")
    if data:
        r.add_header("Content-Type", "application/json")
    try:
        with urllib.request.urlopen(r) as resp:
            raw = resp.read().decode()
            return resp.status, (json.loads(raw) if raw else None)
    except urllib.error.HTTPError as e:
        raw = e.read().decode()
        try:
            return e.code, json.loads(raw)
        except json.JSONDecodeError:
            return e.code, raw


def main():
    base = sys.argv[1].rstrip("/")
    defs_dir = sys.argv[2]
    lenses_file = sys.argv[3] if len(sys.argv) > 3 else "llm-lenses.json"
    dash_file = sys.argv[4] if len(sys.argv) > 4 else "llm-dashboard.json"
    lenses = json.load(open(f"{defs_dir}/{lenses_file}"))
    dash = json.load(open(f"{defs_dir}/{dash_file}"))

    # 1. Data view (fixed id so references stay stable across runs)
    st, body = req(
        base,
        f"/api/saved_objects/index-pattern/{dash['data_view_id']}?overwrite=true",
        "POST",
        {
            "attributes": {
                "title": dash["data_view_title"],
                "name": dash["data_view_pattern"],
                "timeFieldName": "@timestamp",
                "fields": "[]",
                "fieldFormats": "{}",
            }
        },
    )
    if st not in (200, 201):
        sys.exit(f"data view failed: {st} {body}")
    print(f"data view OK: {dash['data_view_title']} ({dash['data_view_pattern']})")

    # 2. Lenses: drop any existing chart with the same title, then create
    lens_ids = {}
    for spec in lenses:
        st, found = req(base, f"/api/visualizations?query={urllib.parse.quote(spec['title'])}")
        if st != 200:
            sys.exit(f"lens search failed for {spec['title']}: {st} {found}")
        for item in (found or {}).get("data", []):
            if item.get("data", {}).get("title") == spec["title"]:
                st2, _ = req(base, f"/api/visualizations/{item['id']}", "DELETE")
                if st2 not in (200, 204):
                    sys.exit(f"delete stale lens {item['id']}: {st2}")
        st, created = req(base, "/api/visualizations", "POST", spec)
        if st not in (200, 201):
            sys.exit(f"lens create failed for {spec['title']}: {st} {created}")
        lens_ids[spec["title"]] = created["id"]
        print(f"lens OK: {spec['title']} -> {created['id']}")

    # 3. Dashboard (overwrite; panels reference the fresh lens ids)
    panels, refs = [], []
    for i, p in enumerate(dash["panels"], 1):
        lid = lens_ids[p["title"]]
        panels.append(
            {
                "embeddableConfig": {"id": lid, "type": "lens"},
                "gridData": {"x": p["x"], "y": p["y"], "w": p["w"], "h": p["h"], "i": str(i)},
                "panelIndex": str(i),
            }
        )
        refs.append({"id": lid, "name": lid, "type": "lens"})
    st, body = req(
        base,
        f"/api/saved_objects/dashboard/{dash['id']}?overwrite=true",
        "POST",
        {
            "attributes": {
                "title": dash["title"],
                "description": dash["description"],
                "panels": panels,
                "attributesSchemaVersion": 2,
                "options": {},
                "refreshInterval": {"display": "10 seconds", "pause": False, "value": 10000},
                "timeRestore": False,
                "version": 1,
            },
            "references": refs,
        },
    )
    if st not in (200, 201):
        sys.exit(f"dashboard failed: {st} {body}")
    print(f"dashboard OK: {dash['title']} ({dash['id']})")


if __name__ == "__main__":
    main()
