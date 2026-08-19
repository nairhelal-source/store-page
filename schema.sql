CREATE TABLE users (
    id SERIAL PRIMARY KEY,
    username VARCHAR(50) NOT NULL UNIQUE,
    email VARCHAR(100) NOT NULL UNIQUE,
    password_hash VARCHAR(255) NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE products (
    product_id SERIAL PRIMARY KEY,
    name VARCHAR(255) NOT NULL,
    description TEXT,
    price NUMERIC(10, 2) NOT NULL,
    stock INTEGER NOT NULL
);

CREATE TABLE shopping_cart (
    cart_id INTEGER REFERENCES users(id),
    products_id INTEGER REFERENCES products(product_id),
    quantity INTEGER NOT NULL,
    added_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (cart_id, products_id)
);

CREATE TABLE orders (
    id SERIAL PRIMARY KEY,
    user_id INTEGER REFERENCES users(id),
    total_amount NUMERIC(10, 2) NOT NULL,
    order_items JSONB NOT NULL,
    status VARCHAR(20) NOT NULL DEFAULT 'pending',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);


CREATE OR REPLACE FUNCTION update_stock_and_cart()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$

DECLARE
    cart_quantity INTEGER;
    old_stock INTEGER;
    cart_product_id INTEGER;
    remove_quantity INTEGER;

BEGIN

    cart_product_id :=
        (NEW.order_items ->> 'product_id')::INTEGER;

    remove_quantity :=
        (NEW.order_items ->> 'quantity')::INTEGER;


    old_stock := (
        SELECT stock
        FROM products
        WHERE product_id = cart_product_id
    );


    cart_quantity := (
        SELECT quantity
        FROM shopping_cart
        WHERE cart_id = NEW.user_id
        AND products_id = cart_product_id
    );

    IF cart_quantity IS NULL THEN
    RAISE EXCEPTION 'Product is not in the shopping cart';
    END IF;


    IF remove_quantity IS NULL THEN
        remove_quantity := 0;
    END IF;


    IF NEW.status = 'placed' THEN

        -- Update stock and shopping cart when an order is placed

        IF remove_quantity > old_stock THEN

            RAISE EXCEPTION
            'Not enough stock available for product %',
            cart_product_id;

        ELSE

            IF remove_quantity > cart_quantity THEN

                RAISE EXCEPTION
                'Not enough items in the shopping cart';

            END IF;


            IF cart_quantity = 0 THEN

                RAISE EXCEPTION
                'There are no items in the shopping cart';


            ELSIF cart_quantity != remove_quantity
                  AND remove_quantity > 0 THEN

                UPDATE shopping_cart
                SET quantity = cart_quantity - remove_quantity
                WHERE cart_id = NEW.user_id
                AND products_id = cart_product_id;


                UPDATE products
                SET stock = products.stock - remove_quantity
                WHERE product_id = cart_product_id;


            ELSE

                UPDATE shopping_cart
                SET quantity = cart_quantity - remove_quantity
                WHERE cart_id = NEW.user_id
                AND products_id = cart_product_id;


                UPDATE products
                SET stock = products.stock - remove_quantity
                WHERE product_id = cart_product_id;

            END IF;

        END IF;


    ELSIF NEW.status = 'cancelled' THEN

        -- Restore stock when the order is cancelled

        IF cart_quantity = 0 THEN

            UPDATE products
            SET stock = products.stock + remove_quantity
            WHERE product_id = cart_product_id;


            UPDATE shopping_cart
            SET quantity = remove_quantity
            WHERE cart_id = NEW.user_id
            AND products_id = cart_product_id;


        ELSIF cart_quantity != remove_quantity
              AND remove_quantity > 0 THEN

            UPDATE products
            SET stock = products.stock + remove_quantity
            WHERE product_id = cart_product_id;


            UPDATE shopping_cart
            SET quantity = cart_quantity + remove_quantity
            WHERE cart_id = NEW.user_id
            AND products_id = cart_product_id;


        ELSE

            UPDATE products
            SET stock = products.stock + remove_quantity
            WHERE product_id = cart_product_id;


            UPDATE shopping_cart
            SET quantity = cart_quantity + remove_quantity
            WHERE cart_id = NEW.user_id
            AND products_id = cart_product_id;

        END IF;

    END IF;


    RETURN NEW;

END;
$$;


CREATE TRIGGER update_stock_and_cart_trigger
AFTER UPDATE OF status
ON orders
FOR EACH ROW
WHEN (OLD.status IS DISTINCT FROM NEW.status)
EXECUTE FUNCTION update_stock_and_cart();
