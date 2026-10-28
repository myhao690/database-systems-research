SELECT SUM(list_sum(list_transform(topk, lambda x: x.l_quantity))) AS result
FROM (
 SELECT arg_max(l, l.l_orderkey * 10 + l.l_linenumber, 3) AS topk
 FROM lineitem AS l GROUP BY l.l_partkey
);
