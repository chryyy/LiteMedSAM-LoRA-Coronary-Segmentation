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
