SELECT l_suppkey, unnest(max_by(lineitem, l_shipdate, 10)) AS row
FROM lineitem GROUP BY l_suppkey;
