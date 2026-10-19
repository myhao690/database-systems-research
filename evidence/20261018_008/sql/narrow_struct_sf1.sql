SELECT l_suppkey,
       unnest(max_by(struct_pack(order_id := l_orderkey, ship_date := l_shipdate), l_shipdate, 3)) AS recent
FROM lineitem GROUP BY l_suppkey;
