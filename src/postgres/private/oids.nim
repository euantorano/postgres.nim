## Mapping of Postgres OIDs to types.
##
## This file is generated automatically by the `tools/generate_oids` program.

type
  Oid* {.pure.} = enum
    Bool = int32(16)
    Bytea = int32(17)
    Char = int32(18)
    Name = int32(19)
    Int8 = int32(20)
    Int2 = int32(21)
    Int2vector = int32(22)
    Int4 = int32(23)
    Regproc = int32(24)
    Text = int32(25)
    Oid = int32(26)
    Tid = int32(27)
    Xid = int32(28)
    Cid = int32(29)
    Oidvector = int32(30)
    Pg_ddl_command = int32(32)
    Pg_type = int32(71)
    Pg_attribute = int32(75)
    Pg_proc = int32(81)
    Pg_class = int32(83)
    Json = int32(114)
    Xml = int32(142)
    T_xml = Oid(143)
    Pg_node_tree = int32(194)
    T_json = Oid(199)
    Smgr = int32(210)
    Point = int32(600)
    Lseg = int32(601)
    Path = int32(602)
    Box = int32(603)
    Polygon = int32(604)
    Line = int32(628)
    T_line = Oid(629)
    Cidr = int32(650)
    T_cidr = Oid(651)
    Float4 = int32(700)
    Float8 = int32(701)
    Abstime = int32(702)
    Reltime = int32(703)
    Tinterval = int32(704)
    Unknown = int32(705)
    Circle = int32(718)
    T_circle = Oid(719)
    Money = int32(790)
    T_money = Oid(791)
    Macaddr = int32(829)
    Inet = int32(869)
    T_bool = Oid(1000)
    T_bytea = Oid(1001)
    T_char = Oid(1002)
    T_name = Oid(1003)
    T_int2 = Oid(1005)
    T_int2vector = Oid(1006)
    T_int4 = Oid(1007)
    T_regproc = Oid(1008)
    T_text = Oid(1009)
    T_tid = Oid(1010)
    T_xid = Oid(1011)
    T_cid = Oid(1012)
    T_oidvector = Oid(1013)
    T_bpchar = Oid(1014)
    T_varchar = Oid(1015)
    T_int8 = Oid(1016)
    T_point = Oid(1017)
    T_lseg = Oid(1018)
    T_path = Oid(1019)
    T_box = Oid(1020)
    T_float4 = Oid(1021)
    T_float8 = Oid(1022)
    T_abstime = Oid(1023)
    T_reltime = Oid(1024)
    T_tinterval = Oid(1025)
    T_polygon = Oid(1027)
    T_oid = Oid(1028)
    Aclitem = int32(1033)
    T_aclitem = Oid(1034)
    T_macaddr = Oid(1040)
    T_inet = Oid(1041)
    Bpchar = int32(1042)
    Varchar = int32(1043)
    Date = int32(1082)
    Time = int32(1083)
    Timestamp = int32(1114)
    T_timestamp = Oid(1115)
    T_date = Oid(1182)
    T_time = Oid(1183)
    Timestamptz = int32(1184)
    T_timestamptz = Oid(1185)
    Interval = int32(1186)
    T_interval = Oid(1187)
    T_numeric = Oid(1231)
    Pg_database = int32(1248)
    T_cstring = Oid(1263)
    Timetz = int32(1266)
    T_timetz = Oid(1270)
    Bit = int32(1560)
    T_bit = Oid(1561)
    Varbit = int32(1562)
    T_varbit = Oid(1563)
    Numeric = int32(1700)
    Refcursor = int32(1790)
    T_refcursor = Oid(2201)
    Regprocedure = int32(2202)
    Regoper = int32(2203)
    Regoperator = int32(2204)
    Regclass = int32(2205)
    Regtype = int32(2206)
    T_regprocedure = Oid(2207)
    T_regoper = Oid(2208)
    T_regoperator = Oid(2209)
    T_regclass = Oid(2210)
    T_regtype = Oid(2211)
    Record = int32(2249)
    Cstring = int32(2275)
    Any = int32(2276)
    Anyarray = int32(2277)
    Void = int32(2278)
    Trigger = int32(2279)
    Language_handler = int32(2280)
    Internal = int32(2281)
    Opaque = int32(2282)
    Anyelement = int32(2283)
    T_record = Oid(2287)
    Anynonarray = int32(2776)
    Pg_authid = int32(2842)
    Pg_auth_members = int32(2843)
    T_txid_snapshot = Oid(2949)
    Uuid = int32(2950)
    T_uuid = Oid(2951)
    Txid_snapshot = int32(2970)
    Fdw_handler = int32(3115)
    Pg_lsn = int32(3220)
    T_pg_lsn = Oid(3221)
    Tsm_handler = int32(3310)
    Anyenum = int32(3500)
    Tsvector = int32(3614)
    Tsquery = int32(3615)
    Gtsvector = int32(3642)
    T_tsvector = Oid(3643)
    T_gtsvector = Oid(3644)
    T_tsquery = Oid(3645)
    Regconfig = int32(3734)
    T_regconfig = Oid(3735)
    Regdictionary = int32(3769)
    T_regdictionary = Oid(3770)
    Jsonb = int32(3802)
    T_jsonb = Oid(3807)
    Anyrange = int32(3831)
    Event_trigger = int32(3838)
    Int4range = int32(3904)
    T_int4range = Oid(3905)
    Numrange = int32(3906)
    T_numrange = Oid(3907)
    Tsrange = int32(3908)
    T_tsrange = Oid(3909)
    Tstzrange = int32(3910)
    T_tstzrange = Oid(3911)
    Daterange = int32(3912)
    T_daterange = Oid(3913)
    Int8range = int32(3926)
    T_int8range = Oid(3927)
    Regnamespace = int32(4089)
    T_regnamespace = Oid(4090)
    Regrole = int32(4096)
    T_regrole = Oid(4097)
