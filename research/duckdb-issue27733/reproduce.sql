-- Run fixture creation once using either CLI. Use a fresh database file.
SET threads = 8;
CREATE TABLE t AS
SELECT 'customer_key_' || ((i * 2654435761) % 100000000)::VARCHAR AS s,
       (i * 2654435761) % 100000000 AS k,
       i % 1000 AS v
FROM range(200000000) r(i);

-- Run each measured query in a FRESH process against the same database.
-- Set a unique temp_directory and profiling_output for each run.
SET threads = 8;
SET preserve_insertion_order = false;
SET memory_limit = '500MB';
SET max_temp_directory_size = '15GB';
SELECT count(*) AS groups, sum(cnt) AS rows, sum(sumv) AS total_v
FROM (SELECT s, count(*) AS cnt, sum(v) AS sumv FROM t GROUP BY s);

-- Fixed-width control: replace s with k in the inner SELECT and GROUP BY.
-- No-Spill control: use memory_limit='8GB' and append
-- WHERE k < 20000000 before GROUP BY s (40M input rows, 20M groups).
