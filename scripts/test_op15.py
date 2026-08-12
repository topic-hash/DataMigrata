#!/usr/bin/env python3
"""Test JSON parsing step by step for op 15."""
import duckdb

con = duckdb.connect('/home/z/my-project/duckdb_migrated/analytics.duckdb', read_only=True)

# Test 1: simple JSON
print('1. Parse JSON:')
print(con.execute("""SELECT CAST('[{"product":"Server"},{"product":"Agent"}]' AS JSON)""").fetchone())

print('\n2. Array length:')
print(con.execute("""SELECT json_array_length(CAST('[{"product":"Server"},{"product":"Agent"}]' AS JSON))""").fetchone())

print('\n3. Extract by index:')
print(con.execute("""SELECT json_extract_string(CAST('[{"product":"Server"},{"product":"Agent"}]' AS JSON), '$[0].product')""").fetchone())

print('\n4. With generate_series:')
r = con.execute("""
SELECT json_extract_string(CAST('[{"product":"Server"},{"product":"Agent"}]' AS JSON), '$[' || i || '].product')
FROM generate_series(0::BIGINT, 1::BIGINT) AS t(i)
""").fetchall()
print(r)

print('\n5. Multi-line JSON:')
sql = """
WITH orders AS (
    SELECT CAST('[
        {"product": "Server", "qty": 2, "price": 49999.99},
        {"product": "Agent", "qty": 5, "price": 4999.99}
    ]' AS JSON) AS j
)
SELECT json_array_length(j.j) FROM orders
"""
print(con.execute(sql).fetchone())

print('\n6. Full op 15 with multi-line JSON:')
sql = r"""
WITH orders AS (
    SELECT CAST('[
        {"product": "Server", "qty": 2, "price": 49999.99},
        {"product": "Agent", "qty": 5, "price": 4999.99}
    ]' AS JSON) AS j
)
SELECT
    json_extract_string(j.j, '$[' || i || '].product') AS Product,
    CAST(json_extract_string(j.j, '$[' || i || '].qty') AS INTEGER) AS Quantity,
    CAST(json_extract_string(j.j, '$[' || i || '].price') AS DECIMAL(18,2)) AS Price,
    CAST(json_extract_string(j.j, '$[' || i || '].qty') AS INTEGER) * CAST(json_extract_string(j.j, '$[' || i || '].price') AS DECIMAL(18,2)) AS LineTotal
FROM orders,
    generate_series(0::BIGINT, CAST(json_array_length(j.j) - 1 AS BIGINT)) AS t(i)
"""
try:
    r = con.execute(sql).fetchall()
    print('rows:', len(r))
    for x in r: print(x)
except Exception as e:
    print('ERROR:', e)

print('\n7. Test generate_series with computed end:')
r = con.execute("""
WITH orders AS (
    SELECT CAST('[{"product":"Server"},{"product":"Agent"}]' AS JSON) AS j
)
SELECT generate_series(0::BIGINT, CAST(json_array_length(j.j) - 1 AS BIGINT)) AS i
FROM orders
""").fetchall()
print(r)
