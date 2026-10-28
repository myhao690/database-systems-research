SELECT SUM(list_sum(list_transform(topk, lambda x: x.l_quantity))) AS result
FROM (
 SELECT arg_max(struct_pack(l_orderkey := l.l_orderkey, l_partkey := l.l_partkey, l_linenumber := l.l_linenumber, l_quantity := l.l_quantity), CAST(l.l_extendedprice * 100 AS BIGINT) * 100000000 + l.rowid, 3) AS topk
 FROM lineitem AS l GROUP BY l.l_partkey
);
