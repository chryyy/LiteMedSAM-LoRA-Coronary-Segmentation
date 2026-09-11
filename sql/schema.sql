-- ============================================================================
-- ASOCA Coronary Artery Segmentation - Database Schema (SQLite)
-- Relational model for clinical metadata, CT acquisition specs, and
-- LiteMedSAM-LoRA deep learning evaluation metrics.
-- ============================================================================

PRAGMA foreign_keys = ON;

-- ----------------------------------------------------------------------------
-- 1. PATIENTS: Anagrafica e profilo clinico cardiovascolare
-- ----------------------------------------------------------------------------
DROP TABLE IF EXISTS model_evaluations;
DROP TABLE IF EXISTS scans;
DROP TABLE IF EXISTS patients;

CREATE TABLE patients (
    patient_id          TEXT PRIMARY KEY,              -- es. 'P001', 'P002'
    diagnosis           TEXT NOT NULL CHECK (diagnosis IN ('Normal', 'Diseased')),
    age                 INTEGER NOT NULL CHECK (age BETWEEN 18 AND 100),
    sex                 TEXT NOT NULL CHECK (sex IN ('M', 'F')),
    calcification_level TEXT NOT NULL CHECK (calcification_level IN ('None', 'Mild', 'Moderate', 'Severe')),
    stent_present       INTEGER NOT NULL DEFAULT 0 CHECK (stent_present IN (0, 1))
);

-- ----------------------------------------------------------------------------
-- 2. SCANS: Metadati tecnici della TAC cardiaca (CCTA) da SimpleITK
-- ----------------------------------------------------------------------------
CREATE TABLE scans (
    scan_id             TEXT PRIMARY KEY,              -- es. 'ASOCA_N_01', 'ASOCA_D_15'
    patient_id          TEXT NOT NULL,
    dataset_split       TEXT NOT NULL CHECK (dataset_split IN ('train', 'val', 'test')),
    slice_count         INTEGER NOT NULL CHECK (slice_count > 0),
    voxel_spacing_z     REAL NOT NULL CHECK (voxel_spacing_z > 0.0),   -- Spessore fetta (mm)
    voxel_spacing_xy    REAL NOT NULL CHECK (voxel_spacing_xy > 0.0),  -- Risoluzione assiale (mm)
    coronary_volume_mm3 REAL NOT NULL CHECK (coronary_volume_mm3 > 0.0),
    acquisition_date    DATE NOT NULL,
    FOREIGN KEY (patient_id) REFERENCES patients(patient_id) ON DELETE CASCADE
);

-- ----------------------------------------------------------------------------
-- 3. MODEL_EVALUATIONS: Risultati quantitativi di inferenza 3D e post-processing
-- ----------------------------------------------------------------------------
CREATE TABLE model_evaluations (
    eval_id             INTEGER PRIMARY KEY AUTOINCREMENT,
    scan_id             TEXT NOT NULL,
    model_variant       TEXT NOT NULL,                 -- es. 'LiteMedSAM-LoRA-2.5D', 'MedSAM-ZeroShot'
    dice_score          REAL NOT NULL CHECK (dice_score BETWEEN 0.0 AND 1.0),
    iou_score           REAL NOT NULL CHECK (iou_score BETWEEN 0.0 AND 1.0),
    hd95_mm             REAL NOT NULL CHECK (hd95_mm >= 0.0),          -- Hausdorff Distance 95% (mm)
    sensitivity         REAL NOT NULL CHECK (sensitivity BETWEEN 0.0 AND 1.0), -- Recall arterioso
    specificity         REAL NOT NULL CHECK (specificity BETWEEN 0.0 AND 1.0),
    inference_time_sec  REAL NOT NULL CHECK (inference_time_sec > 0.0),
    tta_applied         INTEGER NOT NULL DEFAULT 1 CHECK (tta_applied IN (0, 1)),
    sandwich_cleaned    INTEGER NOT NULL DEFAULT 1 CHECK (sandwich_cleaned IN (0, 1)),
    FOREIGN KEY (scan_id) REFERENCES scans(scan_id) ON DELETE CASCADE
);

-- ----------------------------------------------------------------------------
-- PERFORMANCE INDEXES: Ottimizzazione per JOIN e filtri analitici
-- ----------------------------------------------------------------------------
CREATE INDEX idx_patients_diagnosis ON patients(diagnosis);
CREATE INDEX idx_patients_calcification ON patients(calcification_level);
CREATE INDEX idx_scans_split ON scans(dataset_split);
CREATE INDEX idx_scans_patient ON scans(patient_id);
CREATE INDEX idx_eval_scan_model ON model_evaluations(scan_id, model_variant);
CREATE INDEX idx_eval_dice ON model_evaluations(dice_score);
