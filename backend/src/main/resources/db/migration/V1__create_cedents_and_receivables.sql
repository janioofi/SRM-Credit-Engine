CREATE TABLE IF NOT EXISTS cedents (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    document        VARCHAR(14) NOT NULL UNIQUE,
    name            VARCHAR(160) NOT NULL,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT ck_cedents_document
        CHECK (document ~ '^[0-9]{14}$'),
    CONSTRAINT ck_cedents_name
        CHECK (LENGTH(BTRIM(name)) >= 2)
);

CREATE TABLE IF NOT EXISTS receivables (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    cedent_id       UUID NOT NULL REFERENCES cedents(id) ON DELETE RESTRICT,
    type            VARCHAR(24) NOT NULL,
    face_value_brl  NUMERIC(20, 2) NOT NULL,
    due_date        DATE NOT NULL,
    status          VARCHAR(16) NOT NULL DEFAULT 'PENDING',
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT ck_receivables_type
        CHECK (type IN ('DUPLICATA_MERCANTIL', 'CHEQUE_PRE_DATADO')),
    CONSTRAINT ck_receivables_face_value
        CHECK (face_value_brl > 0),
    CONSTRAINT ck_receivables_status
        CHECK (status IN ('PENDING', 'SETTLED'))
);

CREATE INDEX IF NOT EXISTS idx_receivables_cedent_id ON receivables (cedent_id);
CREATE INDEX IF NOT EXISTS idx_receivables_status_due_date ON receivables (status, due_date);