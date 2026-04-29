CREATE TABLE IF NOT EXISTS products (
    id TEXT PRIMARY KEY,
    sku TEXT NOT NULL UNIQUE,
    name TEXT NOT NULL,
    price NUMERIC(10, 2) NOT NULL,
    currency CHAR(3) NOT NULL,
    active BOOLEAN NOT NULL DEFAULT true
);

CREATE TABLE IF NOT EXISTS carts (
    id TEXT PRIMARY KEY,
    user_id TEXT NOT NULL,
    status TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS cart_items (
    cart_id TEXT NOT NULL REFERENCES carts(id) ON DELETE CASCADE,
    product_id TEXT NOT NULL REFERENCES products(id) ON DELETE CASCADE,
    quantity INTEGER NOT NULL DEFAULT 1,
    PRIMARY KEY (cart_id, product_id)
);

CREATE TABLE IF NOT EXISTS purchases (
    id TEXT PRIMARY KEY,
    user_id TEXT NOT NULL,
    product_id TEXT NOT NULL REFERENCES products(id),
    amount NUMERIC(10, 2) NOT NULL,
    currency CHAR(3) NOT NULL,
    status TEXT NOT NULL,
    purchased_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

INSERT INTO products (id, sku, name, price, currency) VALUES
    ('product-001', 'coins-1000', '1000 Coins', 9.99, 'USD'),
    ('product-002', 'skin-neon', 'Neon Skin', 4.99, 'USD')
ON CONFLICT DO NOTHING;

INSERT INTO carts (id, user_id, status) VALUES
    ('cart-001', 'usr-001', 'Open')
ON CONFLICT DO NOTHING;

INSERT INTO cart_items (cart_id, product_id, quantity) VALUES
    ('cart-001', 'product-001', 1)
ON CONFLICT DO NOTHING;

INSERT INTO purchases (id, user_id, product_id, amount, currency, status) VALUES
    ('purchase-001', 'usr-001', 'product-001', 9.99, 'USD', 'Paid')
ON CONFLICT DO NOTHING;
