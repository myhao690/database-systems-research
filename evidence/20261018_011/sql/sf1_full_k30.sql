SELECT l_suppkey, unnest(max_by(lineitem, l_shipdate, 30)) AS row
FROM lineitem GROUP BY l_suppkey;
