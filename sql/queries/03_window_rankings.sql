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
