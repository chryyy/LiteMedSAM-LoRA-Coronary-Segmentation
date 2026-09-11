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
