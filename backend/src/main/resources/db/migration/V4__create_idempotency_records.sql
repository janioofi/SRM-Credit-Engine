CREATE TABLE IF NOT EXISTS idempotency_records (
    idempotency_key     VARCHAR(120) PRIMARY KEY,
    request_hash        CHAR(64) NOT NULL,
    status              VARCHAR(16) NOT NULL,
    settlement_id       UUID UNIQUE,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    completed_at        TIMESTAMPTZ,
    CONSTRAINT fk_idempotency_settlement_and_key
        FOREIGN KEY (settlement_id, idempotency_key)
        REFERENCES settlements(id, idempotency_key) ON DELETE RESTRICT,
    CONSTRAINT ck_idempotency_hash
        CHECK (request_hash ~ '^[0-9a-f]{64}$'),
    CONSTRAINT ck_idempotency_state
        CHECK (
            (status = 'PROCESSING' AND settlement_id IS NULL AND completed_at IS NULL)
            OR
            (status = 'COMPLETED' AND settlement_id IS NOT NULL AND completed_at IS NOT NULL)
        )
);

CREATE INDEX IF NOT EXISTS idx_idempotency_created_at
    ON idempotency_records (created_at);

-- Fluxo esperado no SettlementService @Transactional:
-- 1) registrar chave + SHA-256 canonico do request (PROCESSING);
-- 2) bloquear o recebivel (SELECT ... FOR UPDATE), exigir PENDING;
-- 3) calcular e inserir settlement (UNIQUE receivable_id);
-- 4) alterar receivables.status para SETTLED e updated_at = NOW();
-- 5) concluir a chave (COMPLETED, settlement_id, completed_at);
-- 6) COMMIT; se qualquer passo falhar, ROLLBACK de tudo.
-- Retry da mesma chave + mesmo hash devolve settlement existente.
-- Mesma chave + hash diferente => HTTP 409 (regra da API).
