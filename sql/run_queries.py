#!/usr/bin/env python3
"""
===============================================================================
ASOCA SQL Query Runner & Clinical Report Generator (sql/run_queries.py)
===============================================================================
Esegue la suite di query analitiche SQL sul database 'asoca_analytics.db'
e formatta i risultati in tabelle ASCII direttamente nel terminale.

- 100% libreria standard Python (nessuna dipendenza esterna).
- Se il database non esiste, lo genera automaticamente invocando build_db.py.
- Supporta l'esportazione automatica di un report in formato Markdown.
===============================================================================
"""

import os
import sys
import sqlite3

CURRENT_DIR = os.path.dirname(os.path.abspath(__file__))
DB_PATH = os.path.join(CURRENT_DIR, "asoca_analytics.db")
QUERIES_DIR = os.path.join(CURRENT_DIR, "queries")
REPORT_PATH = os.path.join(CURRENT_DIR, "query_results.md")

QUERY_METADATA = [
    {
        "file": "01_cohort_summary.sql",
        "title": "1. Performance per Gruppo Diagnostico e Split (GROUP BY & Aggregazioni)",
        "description": "Valuta la robustezza del modello LiteMedSAM-LoRA tra scansioni Normal e Diseased nei 3 split."
    },
    {
        "file": "02_clinical_joins.sql",
        "title": "2. Impatto di Calcificazioni ed Età (Multi-Table JOIN & CASE Binning)",
        "description": "Correlazione clinica tra grado di calcificazione coronarica, età ed errore di bordo (HD95)."
    },
    {
        "file": "03_window_rankings.sql",
        "title": "3. Classifica Scan e Deviazione da Media Coorte (Window Function RANK() & AVG() OVER)",
        "description": "Classifica gli scan dentro ciascuno split e calcola lo scostamento individuale dal Dice medio."
    },
    {
        "file": "04_model_benchmark.sql",
        "title": "4. Benchmark Comparativo LoRA vs. Zero-Shot Baseline (Multi-Stage CTE & Self-JOIN)",
        "description": "Quantifica il guadagno netto (+% Dice e -HD95 mm) ottenuto grazie all'adattamento LoRA."
    },
    {
        "file": "05_quality_tiers.sql",
        "title": "5. Classificazione in Tier di Qualità Clinica per STL (Conditional Aggregation)",
        "description": "Percentuale di mesh idonee alla stampa 3D (Clinical Grade) vs. accettabili o da revisionare."
    }
]


def print_table(headers, rows):
    """Formatta e stampa una tabella ASCII allineata."""
    str_rows = [[str(cell) if cell is not None else "NULL" for cell in row] for row in rows]
    col_widths = [len(h) for h in headers]
    for row in str_rows:
        for i, val in enumerate(row):
            if len(val) > col_widths[i]:
                col_widths[i] = len(val)

    # Linee di separazione
    border = "+-" + "-+-".join("-" * w for w in col_widths) + "-+"
    header_str = "| " + " | ".join(h.ljust(col_widths[i]) for i, h in enumerate(headers)) + " |"

    print(border)
    print(header_str)
    print(border)
    for row in str_rows:
        row_str = "| " + " | ".join(row[i].ljust(col_widths[i]) for i in range(len(headers))) + " |"
        print(row_str)
    print(border)


def format_markdown_table(headers, rows):
    """Restituisce una tabella formattata in Markdown."""
    header_line = "| " + " | ".join(headers) + " |"
    sep_line = "| " + " | ".join(["---"] * len(headers)) + " |"
    data_lines = []
    for row in rows:
        cells = [str(c) if c is not None else "NULL" for c in row]
        data_lines.append("| " + " | ".join(cells) + " |")
    return "\n".join([header_line, sep_line] + data_lines)


def run_all_queries():
    # Se il DB non esiste, lo generiamo al volo
    if not os.path.exists(DB_PATH):
        print("⚠️ Database non trovato. Esecuzione build_db.py...")
        from build_db import build_sqlite_database
        build_sqlite_database()

    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()

    report_sections = [
        "# 📊 ASOCA SQL Analytics: Risultati Query & Clinical Insights\n",
        "Report generato automaticamente da `sql/run_queries.py` interrogando `asoca_analytics.db`.\n"
    ]

    print("\n" + "=" * 80)
    print("🚀 ESECUZIONE SUITE ANALITICA SQL - ASOCA & LiteMedSAM-LoRA")
    print("=" * 80 + "\n")

    for item in QUERY_METADATA:
        query_path = os.path.join(QUERIES_DIR, item["file"])
        if not os.path.exists(query_path):
            print(f"❌ File query non trovato: {query_path}")
            continue

        with open(query_path, 'r', encoding='utf-8') as f:
            sql_code = f.read()

        print(f"🔹 {item['title']}")
        print(f"   ℹ️  {item['description']}")
        print("-" * 80)

        cursor.execute(sql_code)
        headers = [desc[0] for desc in cursor.description]
        rows = cursor.fetchall()

        print_table(headers, rows)
        print()

        # Aggiunta al report markdown
        report_sections.append(f"## {item['title']}\n")
        report_sections.append(f"> **Descrizione:** {item['description']}\n")
        report_sections.append("```sql\n" + sql_code.strip() + "\n```\n")
        report_sections.append("### Risultati:\n")
        report_sections.append(format_markdown_table(headers, rows))
        report_sections.append("\n---\n")

    conn.close()

    # Salvataggio del report markdown
    with open(REPORT_PATH, 'w', encoding='utf-8') as f:
        f.write("\n".join(report_sections))

    print("=" * 80)
    print(f"✅ Tutte le 5 query sono state eseguite con successo!")
    print(f"📄 Report Markdown generato in: {REPORT_PATH}")
    print("=" * 80 + "\n")


if __name__ == '__main__':
    run_all_queries()
