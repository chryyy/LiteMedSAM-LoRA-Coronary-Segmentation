# 📊 ASOCA SQL Analytics: Risultati Query & Clinical Insights

Report generato automaticamente da `sql/run_queries.py` interrogando `asoca_analytics.db`.

## 1. Performance per Gruppo Diagnostico e Split (GROUP BY & Aggregazioni)

> **Descrizione:** Valuta la robustezza del modello LiteMedSAM-LoRA tra scansioni Normal e Diseased nei 3 split.

```sql
-- ============================================================================
-- QUERY 1: Aggregazioni per Gruppo Diagnostico e Split
-- ============================================================================
-- OBIETTIVO CLINICO/ML:
-- Verificare come varia la qualità della segmentazione (Dice, HD95, Sensitività)
-- tra pazienti sani (Normal) e pazienti con patologia coronarica (Diseased),
-- suddivisi nei set di Train, Validation e Test.
--
-- CONCETTI SQL DIMOSTRATI:
-- - INNER JOIN su più tabelle con chiavi primarie/esterne
-- - GROUP BY multi-livello (diagnosi, split)
-- - Funzioni di aggregazione: COUNT, AVG, MIN, MAX
-- - Formattazione numerica con ROUND()
-- - Ordinamento custom con CASE WHEN
-- ============================================================================

SELECT 
    p.diagnosis                                         AS diagnosi,
    s.dataset_split                                     AS split,
    COUNT(s.scan_id)                                    AS numero_scansioni,
    ROUND(AVG(e.dice_score), 4)                         AS dice_medio,
    ROUND(MIN(e.dice_score), 4)                         AS dice_minimo,
    ROUND(MAX(e.dice_score), 4)                         AS dice_massimo,
    ROUND(AVG(e.hd95_mm), 2)                            AS hd95_medio_mm,
    ROUND(AVG(e.sensitivity), 4)                        AS recall_medio,
    ROUND(AVG(e.inference_time_sec), 1)                 AS tempo_medio_sec
FROM scans s
INNER JOIN patients p 
    ON s.patient_id = p.patient_id
INNER JOIN model_evaluations e 
    ON s.scan_id = e.scan_id
WHERE e.model_variant = 'LiteMedSAM-LoRA-2.5D'
GROUP BY 
    p.diagnosis, 
    s.dataset_split
ORDER BY 
    p.diagnosis DESC,
    CASE s.dataset_split 
        WHEN 'train' THEN 1 
        WHEN 'val'   THEN 2 
        WHEN 'test'  THEN 3 
    END;
```

### Risultati:

| diagnosi | split | numero_scansioni | dice_medio | dice_minimo | dice_massimo | hd95_medio_mm | recall_medio | tempo_medio_sec |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Normal | train | 18 | 0.8974 | 0.8642 | 0.9371 | 1.64 | 0.9273 | 16.3 |
| Normal | val | 6 | 0.9088 | 0.8968 | 0.9282 | 1.4 | 0.9185 | 16.1 |
| Normal | test | 6 | 0.8915 | 0.8576 | 0.9103 | 1.8 | 0.9357 | 15.9 |
| Diseased | train | 18 | 0.8492 | 0.8089 | 0.8809 | 3.6 | 0.8709 | 19.2 |
| Diseased | val | 6 | 0.8476 | 0.8164 | 0.8976 | 3.57 | 0.8684 | 20.7 |
| Diseased | test | 6 | 0.8566 | 0.8362 | 0.8714 | 3.77 | 0.877 | 16.6 |

---

## 2. Impatto di Calcificazioni ed Età (Multi-Table JOIN & CASE Binning)

> **Descrizione:** Correlazione clinica tra grado di calcificazione coronarica, età ed errore di bordo (HD95).

```sql
-- ============================================================================
-- QUERY 2: Relational JOIN - Impatto di Calcificazioni ed Età su Dice e HD95
-- ============================================================================
-- OBIETTIVO CLINICO/ML:
-- Nelle TAC cardiache, le calcificazioni coronariche (placca dura) producono
-- artefatti da indurimento del fascio ("blooming artifacts") che "ingannano"
-- le reti neurali allargando i confini del vaso.
-- Questa query quantifica la perdita di Dice score e l'aumento dell'errore di bordo (HD95)
-- in base al livello di calcificazione e alla fascia d'età del paziente.
--
-- CONCETTI SQL DIMOSTRATI:
-- - INNER JOIN su 3 tabelle (patients -> scans -> model_evaluations)
-- - Discretizzazione (binning) di una variabile continua con CASE WHEN
-- - GROUP BY su categoria clinica derivata
-- - Filtro su aggregati con clausola HAVING
-- - Calcolo del gap percentuale di errore
-- ============================================================================

SELECT 
    p.calcification_level                               AS livello_calcificazione,
    CASE 
        WHEN p.age < 50 THEN '< 50 anni'
        WHEN p.age BETWEEN 50 AND 65 THEN '50-65 anni'
        ELSE '> 65 anni'
    END                                                 AS fascia_eta,
    COUNT(DISTINCT p.patient_id)                        AS totale_pazienti,
    ROUND(AVG(e.dice_score), 4)                         AS dice_medio,
    ROUND(AVG(e.hd95_mm), 2)                            AS hd95_medio_mm,
    ROUND(AVG(e.sensitivity), 4)                        AS recall_medio,
    ROUND(AVG(s.coronary_volume_mm3), 1)                AS vol_coronarico_medio_mm3
FROM patients p
INNER JOIN scans s 
    ON p.patient_id = s.patient_id
INNER JOIN model_evaluations e 
    ON s.scan_id = e.scan_id
WHERE e.model_variant = 'LiteMedSAM-LoRA-2.5D'
GROUP BY 
    p.calcification_level,
    fascia_eta
HAVING COUNT(DISTINCT p.patient_id) >= 2
ORDER BY 
    CASE p.calcification_level
        WHEN 'None'     THEN 1
        WHEN 'Mild'     THEN 2
        WHEN 'Moderate' THEN 3
        WHEN 'Severe'   THEN 4
    END,
    dice_medio DESC;
```

### Risultati:

| livello_calcificazione | fascia_eta | totale_pazienti | dice_medio | hd95_medio_mm | recall_medio | vol_coronarico_medio_mm3 |
| --- | --- | --- | --- | --- | --- | --- |
| None | > 65 anni | 6 | 0.9075 | 1.9 | 0.9254 | 4374.3 |
| None | 50-65 anni | 9 | 0.8946 | 1.59 | 0.9326 | 4350.0 |
| None | < 50 anni | 9 | 0.892 | 1.52 | 0.9285 | 4477.7 |
| Mild | > 65 anni | 5 | 0.8949 | 2.65 | 0.9091 | 3529.8 |
| Mild | 50-65 anni | 5 | 0.8869 | 1.9 | 0.9216 | 3879.2 |
| Moderate | 50-65 anni | 6 | 0.8585 | 3.83 | 0.8789 | 3258.3 |
| Moderate | > 65 anni | 10 | 0.8397 | 3.45 | 0.8627 | 3232.7 |
| Severe | 50-65 anni | 3 | 0.8516 | 4.08 | 0.8559 | 2973.1 |
| Severe | > 65 anni | 5 | 0.8397 | 3.94 | 0.8544 | 3668.1 |

---

## 3. Classifica Scan e Deviazione da Media Coorte (Window Function RANK() & AVG() OVER)

> **Descrizione:** Classifica gli scan dentro ciascuno split e calcola lo scostamento individuale dal Dice medio.

```sql
-- ============================================================================
-- QUERY 3: Window Functions - Ranking degli Scan e Deviazione dalla Media
-- ============================================================================
-- OBIETTIVO CLINICO/ML:
-- 1. Assegnare a ciascuna scansione una posizione in classifica (RANK) all'interno
--    del proprio split di appartenenza (train, val, test), basata sul Dice score.
-- 2. Calcolare la deviazione (delta) del Dice di ogni paziente rispetto alla media
--    della sua specifica coorte (Normal vs Diseased) per individuare gli outlier.
--
-- CONCETTI SQL DIMOSTRATI:
-- - Window Function RANK() OVER (PARTITION BY ... ORDER BY ...)
-- - Window Function aggregata AVG() OVER (PARTITION BY ...)
-- - Window Function ROW_NUMBER() per numerazione assoluta
-- - Calcolo del delta istantaneo senza subquery annidate
-- - CTE (Common Table Expression) per filtrare sui risultati della window function
-- ============================================================================

WITH ranked_evaluations AS (
    SELECT 
        s.scan_id,
        p.patient_id,
        p.diagnosis,
        p.calcification_level,
        s.dataset_split,
        e.dice_score,
        e.hd95_mm,
        -- Window Function 1: Classifica per Dice score dentro a ciascuno split
        RANK() OVER (
            PARTITION BY s.dataset_split 
            ORDER BY e.dice_score DESC
        ) AS rank_nello_split,

        -- Window Function 2: Media della coorte diagnostica (senza raggruppare le righe)
        ROUND(AVG(e.dice_score) OVER (
            PARTITION BY p.diagnosis
        ), 4) AS dice_medio_coorte,

        -- Window Function 3: Differenza tra il Dice del paziente e la media del suo gruppo
        ROUND(e.dice_score - AVG(e.dice_score) OVER (
            PARTITION BY p.diagnosis
        ), 4) AS delta_vs_media_coorte

    FROM scans s
    INNER JOIN patients p 
        ON s.patient_id = p.patient_id
    INNER JOIN model_evaluations e 
        ON s.scan_id = e.scan_id
    WHERE e.model_variant = 'LiteMedSAM-LoRA-2.5D'
)
SELECT 
    dataset_split               AS split,
    rank_nello_split            AS ranking,
    scan_id,
    patient_id,
    diagnosis                   AS diagnosi,
    calcification_level         AS calcificazione,
    dice_score,
    dice_medio_coorte,
    delta_vs_media_coorte,
    hd95_mm
FROM ranked_evaluations
-- Mostriamo la Top-5 di ogni split per sintesi e chiarezza
WHERE rank_nello_split <= 5
ORDER BY 
    CASE dataset_split 
        WHEN 'test'  THEN 1 
        WHEN 'val'   THEN 2 
        WHEN 'train' THEN 3 
    END,
    rank_nello_split ASC;
```

### Risultati:

| split | ranking | scan_id | patient_id | diagnosi | calcificazione | dice_score | dice_medio_coorte | delta_vs_media_coorte | hd95_mm |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| test | 1 | ASOCA_N_04 | P004 | Normal | None | 0.9103 | 0.8985 | 0.0118 | 1.73 |
| test | 2 | ASOCA_N_16 | P016 | Normal | None | 0.9069 | 0.8985 | 0.0084 | 1.62 |
| test | 3 | ASOCA_N_12 | P012 | Normal | None | 0.8949 | 0.8985 | -0.0036 | 1.58 |
| test | 4 | ASOCA_N_22 | P022 | Normal | None | 0.8903 | 0.8985 | -0.0082 | 1.65 |
| test | 5 | ASOCA_N_24 | P024 | Normal | None | 0.889 | 0.8985 | -0.0095 | 2.02 |
| val | 1 | ASOCA_N_19 | P019 | Normal | Mild | 0.9282 | 0.8985 | 0.0297 | 1.51 |
| val | 2 | ASOCA_N_01 | P001 | Normal | None | 0.9151 | 0.8985 | 0.0166 | 1.64 |
| val | 3 | ASOCA_N_27 | P027 | Normal | Mild | 0.9105 | 0.8985 | 0.012 | 1.41 |
| val | 4 | ASOCA_N_05 | P005 | Normal | None | 0.9038 | 0.8985 | 0.0053 | 1.23 |
| val | 5 | ASOCA_N_14 | P014 | Normal | None | 0.8985 | 0.8985 | -0.0 | 1.11 |
| train | 1 | ASOCA_N_28 | P028 | Normal | None | 0.9371 | 0.8985 | 0.0386 | 2.01 |
| train | 2 | ASOCA_N_02 | P002 | Normal | None | 0.9255 | 0.8985 | 0.027 | 1.92 |
| train | 3 | ASOCA_N_29 | P029 | Normal | None | 0.9113 | 0.8985 | 0.0128 | 1.13 |
| train | 4 | ASOCA_N_08 | P008 | Normal | None | 0.9065 | 0.8985 | 0.008 | 1.72 |
| train | 5 | ASOCA_N_17 | P017 | Normal | Mild | 0.9053 | 0.8985 | 0.0068 | 1.98 |

---

## 4. Benchmark Comparativo LoRA vs. Zero-Shot Baseline (Multi-Stage CTE & Self-JOIN)

> **Descrizione:** Quantifica il guadagno netto (+% Dice e -HD95 mm) ottenuto grazie all'adattamento LoRA.

```sql
-- ============================================================================
-- QUERY 4: CTE Multi-Stage - Benchmark Comparativo LoRA vs. Zero-Shot Baseline
-- ============================================================================
-- OBIETTIVO CLINICO/ML:
-- Quantificare il reale valore aggiunto dell'adattamento con LoRA e slicing 2.5D
-- rispetto al modello base MedSAM applicato zero-shot:
-- Calcolo di Delta Dice (+% guadagno) e riduzione dell'errore di Hausdorff (-HD95 mm)
-- segmentando i risultati per coorte clinica (Normal vs Diseased).
--
-- CONCETTI SQL DIMOSTRATI:
-- - Common Table Expressions multiple (WITH cte1 AS (...), cte2 AS (...))
-- - Self-Join / Pairwise Comparison tra varianti dello stesso modello sullo stesso scan
-- - Calcolo di guadagni relativi percentuali
-- - Aggregazione finale sui delta calcolati
-- ============================================================================

WITH lora_model AS (
    SELECT 
        scan_id,
        dice_score          AS dice_lora,
        hd95_mm             AS hd95_lora,
        sensitivity         AS recall_lora
    FROM model_evaluations
    WHERE model_variant = 'LiteMedSAM-LoRA-2.5D'
),

baseline_model AS (
    SELECT 
        scan_id,
        dice_score          AS dice_base,
        hd95_mm             AS hd95_base,
        sensitivity         AS recall_base
    FROM model_evaluations
    WHERE model_variant = 'MedSAM-ZeroShot-Baseline'
),

comparison AS (
    SELECT 
        p.diagnosis,
        p.calcification_level,
        s.scan_id,
        l.dice_lora,
        b.dice_base,
        -- Delta assoluto Dice
        (l.dice_lora - b.dice_base)                             AS delta_dice,
        -- Guadagno percentuale relativo (%)
        ((l.dice_lora - b.dice_base) / b.dice_base) * 100.0     AS pct_gain_dice,
        -- Riduzione errore di bordo HD95 (mm risparmiati di distanza)
        (b.hd95_base - l.hd95_lora)                             AS hd95_reduction_mm
    FROM scans s
    INNER JOIN patients p 
        ON s.patient_id = p.patient_id
    INNER JOIN lora_model l 
        ON s.scan_id = l.scan_id
    INNER JOIN baseline_model b 
        ON s.scan_id = b.scan_id
)

SELECT 
    diagnosis                                           AS diagnosi,
    COUNT(scan_id)                                      AS scansioni_valutate,
    ROUND(AVG(dice_base), 4)                            AS dice_medio_baseline,
    ROUND(AVG(dice_lora), 4)                            AS dice_medio_lora,
    ROUND(AVG(delta_dice), 4)                           AS guadagno_netto_dice,
    ROUND(AVG(pct_gain_dice), 2) || '%'                 AS incremento_percentuale,
    ROUND(AVG(hd95_reduction_mm), 2)                    AS riduzione_errore_hd95_mm
FROM comparison
GROUP BY diagnosis
ORDER BY AVG(delta_dice) DESC;
```

### Risultati:

| diagnosi | scansioni_valutate | dice_medio_baseline | dice_medio_lora | guadagno_netto_dice | incremento_percentuale | riduzione_errore_hd95_mm |
| --- | --- | --- | --- | --- | --- | --- |
| Diseased | 30 | 0.5921 | 0.8503 | 0.2582 | 44.4% | 8.29 |
| Normal | 30 | 0.6877 | 0.8985 | 0.2108 | 30.95% | 7.03 |

---

## 5. Classificazione in Tier di Qualità Clinica per STL (Conditional Aggregation)

> **Descrizione:** Percentuale di mesh idonee alla stampa 3D (Clinical Grade) vs. accettabili o da revisionare.

```sql
-- ============================================================================
-- QUERY 5: Conditional Aggregation (CASE WHEN) - Tier di Qualità Clinica STL
-- ============================================================================
-- OBIETTIVO CLINICO/ML:
-- Per poter stampare in 3D una mesh coronarica (.stl) o usarla in simulazioni CFD
-- emodinamiche, la segmentazione deve rispettare standard minimi di accuratezza.
-- Questa query classifica le inferenze in 3 classi di affidabilità clinica:
--   1. 'Clinical Grade (3D Print Ready)': Dice >= 0.88 AND HD95 <= 2.5 mm
--   2. 'Acceptable (Minor Review)': Dice BETWEEN 0.82 AND 0.88
--   3. 'Suboptimal (Requires Manual Edit)': Dice < 0.82 OR HD95 > 4.0 mm
-- Calcola la percentuale di conformità per ciascun gruppo diagnostico.
--
-- CONCETTI SQL DIMOSTRATI:
-- - CASE WHEN per classificazione a regole multiple
-- - Pivot/Conditional Aggregation (SUM(CASE WHEN ...) / COUNT(*))
-- - Calcolo di percentuali dirette in SQL
-- ============================================================================

WITH evaluated_tiers AS (
    SELECT 
        p.diagnosis,
        s.dataset_split,
        s.scan_id,
        e.dice_score,
        e.hd95_mm,
        CASE 
            WHEN e.dice_score >= 0.88 AND e.hd95_mm <= 2.5 
                THEN 'Clinical Grade'
            WHEN e.dice_score >= 0.82 AND e.hd95_mm <= 4.0 
                THEN 'Acceptable'
            ELSE 'Suboptimal'
        END AS quality_tier
    FROM scans s
    INNER JOIN patients p 
        ON s.patient_id = p.patient_id
    INNER JOIN model_evaluations e 
        ON s.scan_id = e.scan_id
    WHERE e.model_variant = 'LiteMedSAM-LoRA-2.5D'
)

SELECT 
    diagnosis                                                       AS diagnosi,
    COUNT(*)                                                        AS totale_scansioni,
    SUM(CASE WHEN quality_tier = 'Clinical Grade' THEN 1 ELSE 0 END) AS n_clinical_grade,
    SUM(CASE WHEN quality_tier = 'Acceptable'     THEN 1 ELSE 0 END) AS n_acceptable,
    SUM(CASE WHEN quality_tier = 'Suboptimal'     THEN 1 ELSE 0 END) AS n_suboptimal,
    ROUND(
        SUM(CASE WHEN quality_tier = 'Clinical Grade' THEN 1.0 ELSE 0.0 END) * 100.0 / COUNT(*),
        1
    ) || '%'                                                        AS pct_clinical_grade,
    ROUND(
        SUM(CASE WHEN quality_tier IN ('Clinical Grade', 'Acceptable') THEN 1.0 ELSE 0.0 END) * 100.0 / COUNT(*),
        1
    ) || '%'                                                        AS tasso_usabilita_clinica
FROM evaluated_tiers
GROUP BY diagnosis;
```

### Risultati:

| diagnosi | totale_scansioni | n_clinical_grade | n_acceptable | n_suboptimal | pct_clinical_grade | tasso_usabilita_clinica |
| --- | --- | --- | --- | --- | --- | --- |
| Diseased | 30 | 0 | 17 | 13 | 0.0% | 56.7% |
| Normal | 30 | 26 | 4 | 0 | 86.7% | 100.0% |

---
