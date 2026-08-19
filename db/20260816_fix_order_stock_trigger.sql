-- Run this once against the existing database after the original schema has
-- already been created.
CREATE TABLE IF NOT EXISTS order_items (
    order_id INTEGER NOT NULL REFERENCES orders(id),
    product_id INTEGER NOT NULL REFERENCES products(id),
    quantity INTEGER NOT NULL CHECK (quantity > 0),
    unit_price NUMERIC(10, 2) NOT NULL CHECK (unit_price >= 0),
    PRIMARY KEY (order_id, product_id)
);

DROP TRIGGER IF EXISTS update_stock_and_cart ON orders;

CREATE OR REPLACE FUNCTION update_stock_and_cart()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    IF NEW.status = 'placed' AND OLD.status IS DISTINCT FROM 'placed' THEN
        INSERT INTO order_items (order_id, product_id, quantity, unit_price)
        SELECT NEW.id, cart.product_id, cart.quantity, product.price
        FROM shopping_cart AS cart
        JOIN products AS product ON product.id = cart.product_id
        WHERE cart.id = NEW.user_id
          AND cart.quantity > 0;

        IF NOT FOUND THEN
            RAISE EXCEPTION 'Cannot place order %: the cart is empty', NEW.id;
        END IF;

        IF EXISTS (
            SELECT 1
            FROM order_items AS item
            JOIN products AS product ON product.id = item.product_id
            WHERE item.order_id = NEW.id
              AND product.stock < item.quantity
        ) THEN
            RAISE EXCEPTION 'Not enough stock available to place order %', NEW.id;
        END IF;

        -- Update block 1: products only.
        UPDATE products AS product
        SET stock = product.stock - item.quantity
        FROM order_items AS item
        WHERE item.order_id = NEW.id
          AND product.id = item.product_id;

        -- Update block 2: shopping_cart only.
        UPDATE shopping_cart
        SET quantity = 0
        WHERE id = NEW.user_id;

    ELSIF NEW.status = 'cancelled' AND OLD.status = 'placed' THEN
        -- Update block 1: products only.
        UPDATE products AS product
        SET stock = product.stock + item.quantity
        FROM order_items AS item
        WHERE item.order_id = NEW.id
          AND product.id = item.product_id;

        -- Update block 2: shopping_cart only.
        UPDATE shopping_cart
        SET quantity = 0
        WHERE id = NEW.user_id;
    END IF;

    RETURN NEW;
END;
$$;

CREATE TRIGGER update_stock_and_cart
AFTER UPDATE OF status ON orders
FOR EACH ROW
WHEN (OLD.status IS DISTINCT FROM NEW.status)
EXECUTE FUNCTION update_stock_and_cart();
