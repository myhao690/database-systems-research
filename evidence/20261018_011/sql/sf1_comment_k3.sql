SELECT l_suppkey,
       unnest(max_by(struct_pack(id := l_orderkey, comment := l_comment),
                     date_diff('day', DATE '1992-01-01', l_shipdate)::BIGINT, 3)) AS row
FROM lineitem GROUP BY l_suppkey;
