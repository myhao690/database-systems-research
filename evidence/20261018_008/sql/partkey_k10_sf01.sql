SELECT l_partkey, unnest(max_by(lineitem, l_shipdate, 10)) AS row
FROM lineitem GROUP BY l_partkey;
