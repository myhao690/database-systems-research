SELECT SUM(list_sum(list_transform(top, lambda x: x.l_quantity))) AS result FROM (
  SELECT arg_max(struct_pack(l_orderkey := l.l_orderkey, l_partkey := l.l_partkey, l_suppkey := l.l_suppkey, l_linenumber := l.l_linenumber, l_quantity := l.l_quantity, l_extendedprice := l.l_extendedprice, l_discount := l.l_discount, l_tax := l.l_tax, l_returnflag := l.l_returnflag, l_linestatus := l.l_linestatus, l_shipdate := l.l_shipdate, l_commitdate := l.l_commitdate, l_receiptdate := l.l_receiptdate, l_shipinstruct := l.l_shipinstruct, l_shipmode := l.l_shipmode, l_comment := l.l_comment), l.l_orderkey * 10 + l.l_linenumber, 3) AS top
  FROM lineitem AS l GROUP BY l.l_partkey
);
