SELECT l_suppkey,
       unnest(max_by(struct_pack(q := l_quantity, price := l_extendedprice,
                                 discount := l_discount, tax := l_tax),
                     date_diff('day', DATE '1992-01-01', l_shipdate)::BIGINT, 3)) AS row
FROM lineitem GROUP BY l_suppkey;
