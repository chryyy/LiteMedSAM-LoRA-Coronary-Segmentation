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
