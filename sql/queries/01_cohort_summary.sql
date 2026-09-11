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
