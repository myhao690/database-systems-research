SELECT SUM(q) AS result FROM (
 SELECT l.l_quantity AS q, ROW_NUMBER() OVER (PARTITION BY l.l_partkey
 ORDER BY l.l_orderkey * 10 + l.l_linenumber DESC) AS rn FROM lineitem AS l
) WHERE rn <= 3;
