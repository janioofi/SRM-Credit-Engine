CREATE TABLE IF NOT EXISTS exchange_rates (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    base_currency   VARCHAR(3) NOT NULL,
    quote_currency  VARCHAR(3) NOT NULL,
    rate            NUMERIC(20, 8) NOT NULL,
    effective_at    TIMESTAMPTZ NOT NULL,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT ck_exchange_rates_pair
        CHECK (base_currency = 'USD' AND quote_currency = 'BRL'),
    CONSTRAINT ck_exchange_rates_rate
        CHECK (rate > 0),
    CONSTRAINT uq_exchange_rates_pair_effective
        UNIQUE (base_currency, quote_currency, effective_at)
);

CREATE INDEX IF NOT EXISTS idx_exchange_rates_pair_effective
    ON exchange_rates (base_currency, quote_currency, effective_at DESC);
