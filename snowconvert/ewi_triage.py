"""
Build a prioritized remediation backlog from SnowConvert AI issue reports.

SnowConvert emits CSV reports in its output 'Reports' folder and inline markers in code
(e.g. '--** SSC-EWI-SSIS0004 ... **'). Report file names/columns can vary between releases,
so this script scans BOTH the CSV reports (any *.csv whose header contains a code column)
and the generated code, and normalizes them into one backlog.
"""
import argparse
import csv
import re
from collections import Counter
from pathlib import Path

CODE_RE = re.compile(r"\b(SSC-(?:EWI|FDM|PRF)-[A-Z]{2,6}\d{4})\b")

# Severity/effort heuristics for this POC (tune per program)
PRIORITY_RULES = [
    ("SSC-EWI-SSIS0004", "P1", "Unsupported control-flow element or loop logic - manual rewrite"),
    ("SSC-EWI-SSIS0014", "P1", "ForEach file enumerator stage placeholder - map to real stage"),
    ("SSC-EWI-SSIS0005", "P2", "Execute Package runs async as TASK - confirm sync requirements"),
    ("SSC-EWI-SSIS0011", "P2", "Execute SQL result binding not converted"),
    ("SSC-EWI", "P2", "Functional gap - review"),
    ("SSC-FDM", "P3", "Functional difference - verify behaviour, usually no change"),
    ("SSC-PRF", "P3", "Performance review"),
]


def classify(code: str):
    for prefix, prio, note in PRIORITY_RULES:
        if code.startswith(prefix):
            return prio, note
    return "P3", "Review"


def scan_code(root: Path):
    exts = {".sql", ".yml", ".yaml", ".m", ".pq", ".txt"}
    for f in root.rglob("*"):
        if f.suffix.lower() not in exts or not f.is_file():
            continue
        for lineno, line in enumerate(f.read_text(errors="ignore").splitlines(), 1):
            for code in CODE_RE.findall(line):
                yield {"code": code, "file": str(f.relative_to(root)), "line": lineno,
                       "detail": line.strip()[:240], "source": "code"}


def scan_reports(root: Path):
    for f in root.rglob("*.csv"):
        try:
            with f.open(newline="", encoding="utf-8-sig") as fh:
                reader = csv.DictReader(fh)
                if not reader.fieldnames:
                    continue
                code_col = next((c for c in reader.fieldnames if "code" in c.lower()), None)
                if not code_col:
                    continue
                file_col = next((c for c in reader.fieldnames if "file" in c.lower()), None)
                desc_col = next((c for c in reader.fieldnames
                                 if any(k in c.lower() for k in ("description", "message"))), None)
                for row in reader:
                    m = CODE_RE.search(row.get(code_col, "") or "")
                    if m:
                        yield {"code": m.group(1), "file": row.get(file_col, "") if file_col else "",
                               "line": "", "detail": (row.get(desc_col, "") or "")[:240] if desc_col else "",
                               "source": f.name}
        except (UnicodeDecodeError, csv.Error):
            continue


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("output_dir", type=Path)
    ap.add_argument("--out", type=Path, default=Path("ewi_backlog.csv"))
    args = ap.parse_args()

    seen, rows = set(), []
    for item in list(scan_reports(args.output_dir)) + list(scan_code(args.output_dir)):
        key = (item["code"], item["file"], item["line"])
        if key in seen:
            continue
        seen.add(key)
        item["priority"], item["guidance"] = classify(item["code"])
        item["owner"], item["status"] = "", "Open"
        rows.append(item)

    rows.sort(key=lambda r: (r["priority"], r["code"], r["file"]))
    fields = ["priority", "code", "guidance", "file", "line", "detail", "source", "owner", "status"]
    with args.out.open("w", newline="") as fh:
        w = csv.DictWriter(fh, fieldnames=fields)
        w.writeheader()
        w.writerows(rows)

    print(f"{len(rows)} findings -> {args.out}")
    for (prio, code), n in sorted(Counter((r["priority"], r["code"]) for r in rows).items()):
        print(f"  {prio}  {code:<20} {n}")


if __name__ == "__main__":
    main()
