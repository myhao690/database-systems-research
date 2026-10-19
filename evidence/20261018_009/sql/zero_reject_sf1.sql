SELECT l_suppkey, unnest(max_by(lineitem, l_orderkey, 3)) AS row
FROM lineitem GROUP BY l_suppkey;
