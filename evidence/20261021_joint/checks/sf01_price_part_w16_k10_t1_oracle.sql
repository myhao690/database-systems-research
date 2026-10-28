SELECT SUM(q) AS result FROM (
 SELECT l.l_quantity AS q, ROW_NUMBER() OVER (PARTITION BY l.l_partkey
 ORDER BY CAST(l.l_extendedprice * 100 AS BIGINT) * 100000000 + l.rowid DESC) AS rn FROM lineitem AS l
) WHERE rn <= 10;
