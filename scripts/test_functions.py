import duckdb
con = duckdb.connect('duckdb_migrated/analytics.duckdb', read_only=True)
con.execute('LOAD spatial')
# Test regexp_extract (with proper escaping)
r = con.execute("SELECT regexp_extract('<Skill level=\"Expert\">Python</Skill>', 'level=\"([^\"]+)\"', 1)").fetchone()
print('regexp_extract:', r)
# Use Python string for JSON
json_str = '{"a":1}'
r = con.execute("SELECT json_extract_string(?, '$.b')", [json_str]).fetchone()
print('json_extract_string missing key:', r, '-> should be NULL')
# Test json_extract for object (returns JSON value)
r = con.execute("SELECT json_extract(?, '$.b')", [json_str]).fetchone()
print('json_extract obj missing:', r)
# Test json_extract for null literal
r = con.execute("SELECT json_extract(?, '$.a')", ['{"a":null}']).fetchone()
print('json_extract null value:', r)
# Test json_extract_string for null
r = con.execute("SELECT json_extract_string(?, '$.a')", ['{"a":null}']).fetchone()
print('json_extract_string null:', r)
# Test json extract array
r = con.execute("SELECT json_extract(?, '$')", ['[1,2,3]']).fetchone()
print('json_extract array root:', r)
# Test ST functions
r = con.execute("SELECT ST_Distance(ST_Point(0,0), ST_Point(1,1))").fetchone()
print('ST_Distance:', r)
r = con.execute("SELECT ST_GeomFromText('POINT (1 2)')").fetchone()
print('ST_GeomFromText:', r)
# Test ST_X, ST_Y
r = con.execute("SELECT ST_X(ST_GeomFromText('POINT (1 2)')), ST_Y(ST_GeomFromText('POINT (1 2)'))").fetchone()
print('ST_X, ST_Y:', r)
# Test ST_Length on LINESTRING
r = con.execute("SELECT ST_Length(ST_GeomFromText('LINESTRING(-74.0060 40.7128, -0.1278 51.5074, 139.6503 35.6762)'))").fetchone()
print('ST_Length:', r)
# Test ST_NumPoints
r = con.execute("SELECT ST_NumPoints(ST_GeomFromText('LINESTRING(-74.0060 40.7128, -0.1278 51.5074, 139.6503 35.6762)'))").fetchone()
print('ST_NumPoints:', r)
# Test ST_Contains
r = con.execute("SELECT ST_Contains(ST_GeomFromText('MULTIPOLYGON(((-125 25, -100 25, -100 50, -125 50, -125 25)), ((-100 30, -80 30, -80 45, -100 45, -100 30)))'), ST_GeomFromText('POINT (-110 40)'))").fetchone()
print('ST_Contains:', r)
# Test json_extract_string returns for null value
r = con.execute("SELECT json_extract_string('{\"payment_method\":\"crypto\"}', '$.discount_code')").fetchone()
print('json_extract_string missing key 2:', r)
