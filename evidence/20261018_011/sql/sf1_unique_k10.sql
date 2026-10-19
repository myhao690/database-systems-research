SELECT l_suppkey, unnest(max_by(lineitem, l_orderkey * 10 + l_linenumber, 10)) AS row
FROM lineitem GROUP BY l_suppkey;
