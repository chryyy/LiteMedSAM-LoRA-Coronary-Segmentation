-- ============================================================================
-- ASOCA Coronary Analytics - Suite Completa di Query SQL
-- Autore: Christian Brandini
-- Progetto: LiteMedSAM-LoRA-Coronary-Segmentation
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. AGGREGAZIONI PER GRUPPO DIAGNOSTICO E SPLIT
-- ----------------------------------------------------------------------------
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


-- ----------------------------------------------------------------------------
-- 2. RELATIONAL JOIN: IMPATTO DI CALCIFICAZIONI ED ETÀ SU ACCURATEZZA
-- ----------------------------------------------------------------------------
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


-- ----------------------------------------------------------------------------
-- 3. WINDOW FUNCTION: RANKING DEGLI SCAN E DEVIAZIONE DALLA MEDIA DI COORTE
-- ----------------------------------------------------------------------------
WITH ranked_evaluations AS (
    SELECT 
        s.scan_id,
        p.patient_id,
        p.diagnosis,
        p.calcification_level,
        s.dataset_split,
        e.dice_score,
        e.hd95_mm,
        RANK() OVER (
            PARTITION BY s.dataset_split 
            ORDER BY e.dice_score DESC
        ) AS rank_nello_split,
        ROUND(AVG(e.dice_score) OVER (
            PARTITION BY p.diagnosis
        ), 4) AS dice_medio_coorte,
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
WHERE rank_nello_split <= 5
ORDER BY 
    CASE dataset_split 
        WHEN 'test'  THEN 1 
        WHEN 'val'   THEN 2 
        WHEN 'train' THEN 3 
    END,
    rank_nello_split ASC;


-- ----------------------------------------------------------------------------
-- 4. CTE MULTI-STAGE: BENCHMARK COMPARATIVO LORa VS. ZERO-SHOT BASELINE
-- ----------------------------------------------------------------------------
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
        (l.dice_lora - b.dice_base)                             AS delta_dice,
        ((l.dice_lora - b.dice_base) / b.dice_base) * 100.0     AS pct_gain_dice,
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


-- ----------------------------------------------------------------------------
-- 5. CONDITIONAL AGGREGATION (CASE WHEN): TIER DI QUALITÀ CLINICA STL
-- ----------------------------------------------------------------------------
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
