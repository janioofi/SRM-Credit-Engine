-- V3: liquidacoes. Os valores e taxas sao snapshots imutaveis da operacao.
-- So permitimos uma liquidacao por recebivel.

CREATE TABLE settlements (
    id                      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    receivable_id           UUID NOT NULL UNIQUE
                            REFERENCES receivables(id) ON DELETE RESTRICT,
    cedent_id               UUID NOT NULL
                            REFERENCES cedents(id) ON DELETE RESTRICT,
    cedent_document         VARCHAR(14) NOT NULL,
    cedent_name             VARCHAR(160) NOT NULL,
    receivable_type         VARCHAR(24) NOT NULL,
    face_value_brl          NUMERIC(20, 2) NOT NULL,
    term_months             INTEGER NOT NULL,
    base_rate_monthly       NUMERIC(20, 8) NOT NULL,
    spread_monthly          NUMERIC(20, 8) NOT NULL,
    present_value_brl       NUMERIC(20, 2) NOT NULL,
    discount_brl            NUMERIC(20, 2) NOT NULL,
    payment_currency        VARCHAR(3) NOT NULL,
    payment_amount          NUMERIC(20, 2) NOT NULL,
    exchange_rate_id        UUID REFERENCES exchange_rates(id) ON DELETE RESTRICT,
    fx_rate_brl_per_usd     NUMERIC(20, 8),
    fx_rate_effective_at    TIMESTAMPTZ,
    idempotency_key         VARCHAR(120) NOT NULL UNIQUE,
    settled_at              TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    -- Apoia a FK composta da V4: chave deve pertencer a esta liquidacao.
    CONSTRAINT uq_settlements_id_key UNIQUE (id, idempotency_key),
    CONSTRAINT ck_settlements_receivable_type
        CHECK (receivable_type IN ('DUPLICATA_MERCANTIL', 'CHEQUE_PRE_DATADO')),
    CONSTRAINT ck_settlements_term_months CHECK (term_months >= 1),
    CONSTRAINT ck_settlements_rates
        CHECK (base_rate_monthly >= 0 AND spread_monthly >= 0),
    CONSTRAINT ck_settlements_amounts
        CHECK (
            face_value_brl > 0 AND present_value_brl > 0 AND
            discount_brl >= 0 AND payment_amount > 0 AND
            face_value_brl = present_value_brl + discount_brl
        ),
    CONSTRAINT ck_settlements_currency_fx
        CHECK (
            (payment_currency = 'BRL' AND
             payment_amount = present_value_brl AND
             exchange_rate_id IS NULL AND fx_rate_brl_per_usd IS NULL AND
             fx_rate_effective_at IS NULL)
            OR
            (payment_currency = 'USD' AND
             exchange_rate_id IS NOT NULL AND
             fx_rate_brl_per_usd IS NOT NULL AND fx_rate_brl_per_usd > 0 AND
             fx_rate_effective_at IS NOT NULL)
        )
);

-- Filtros de extrato por data, moeda e cedente (paginacao server-side).
CREATE INDEX idx_settlements_settled_at
    ON settlements (settled_at DESC);
CREATE INDEX idx_settlements_currency_settled_at
    ON settlements (payment_currency, settled_at DESC);
CREATE INDEX idx_settlements_cedent_settled_at
    ON settlements (cedent_id, settled_at DESC);

-- Trava de auditoria no banco: liquidações e cotacoes nao podem ser editadas
-- nem apagadas pelas operacoes normais da aplicacao.
CREATE OR REPLACE FUNCTION reject_financial_record_mutation()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    RAISE EXCEPTION 'O registro financeiro de % e imutavel', TG_TABLE_NAME
        USING ERRCODE = 'check_violation';
END;
$$;

CREATE TRIGGER trg_settlements_immutable
BEFORE UPDATE OR DELETE ON settlements
FOR EACH ROW EXECUTE FUNCTION reject_financial_record_mutation();

CREATE TRIGGER trg_exchange_rates_immutable
BEFORE UPDATE OR DELETE ON exchange_rates
FOR EACH ROW EXECUTE FUNCTION reject_financial_record_mutation();
