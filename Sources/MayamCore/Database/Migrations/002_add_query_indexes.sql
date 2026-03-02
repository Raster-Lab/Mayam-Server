-- Mayam — PostgreSQL Query/Retrieve Performance Index Migration
-- Migration: 002_add_query_indexes
-- Description: Adds series and instance tables, plus query performance indexes
--              for C-FIND, C-MOVE, and C-GET operations.

BEGIN;

-- ============================================================
-- Series
-- ============================================================
CREATE TABLE IF NOT EXISTS series (
    id                    BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    series_instance_uid   TEXT        NOT NULL UNIQUE,
    study_id              BIGINT      NOT NULL REFERENCES studies(id) ON DELETE CASCADE,
    series_number         INTEGER,
    modality              TEXT,
    series_description    TEXT,
    instance_count        INTEGER     NOT NULL DEFAULT 0,
    created_at            TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at            TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_series_study_id           ON series (study_id);
CREATE INDEX idx_series_modality           ON series (modality);
CREATE INDEX idx_series_series_instance_uid ON series (series_instance_uid);

-- ============================================================
-- Instances
-- ============================================================
CREATE TABLE IF NOT EXISTS instances (
    id                    BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    sop_instance_uid      TEXT        NOT NULL UNIQUE,
    sop_class_uid         TEXT        NOT NULL,
    series_id             BIGINT      NOT NULL REFERENCES series(id) ON DELETE CASCADE,
    instance_number       INTEGER,
    transfer_syntax_uid   TEXT        NOT NULL,
    checksum_sha256       TEXT,
    file_size_bytes       BIGINT      NOT NULL,
    file_path             TEXT        NOT NULL,
    calling_ae_title      TEXT,
    created_at            TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at            TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_instances_series_id        ON instances (series_id);
CREATE INDEX idx_instances_sop_instance_uid ON instances (sop_instance_uid);
CREATE INDEX idx_instances_sop_class_uid    ON instances (sop_class_uid);

-- ============================================================
-- Query Performance Indexes
-- ============================================================

-- Patient-level query indexes
CREATE INDEX idx_patients_patient_name ON patients (patient_name);

-- Study-level query indexes
CREATE INDEX idx_studies_study_instance_uid ON studies (study_instance_uid);
CREATE INDEX idx_studies_modality           ON studies (modality);
CREATE INDEX idx_studies_study_description  ON studies (study_description);

COMMENT ON INDEX idx_patients_patient_name IS 'Supports C-FIND patient name wildcard queries.';
COMMENT ON INDEX idx_studies_modality IS 'Supports C-FIND modality filtering queries.';
COMMENT ON INDEX idx_studies_study_date IS 'Supports C-FIND study date range queries.';

COMMIT;
