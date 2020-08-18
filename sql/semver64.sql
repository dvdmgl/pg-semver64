SET client_min_messages TO warning;
SET log_min_messages    TO warning;

-- Create a semantic version data type.
--
-- https://semver64.org/.
--

-- 1. A normal version number MUST take the form X.Y.Z where X, Y, and Z are
-- integers. X is the major version, Y is the minor version, and Z is the
-- patch version. Each element MUST increase numerically. For instance: 1.9.0
-- < 1.10.0 < 1.11.0.
--
-- 2. A special version number MAY be denoted by appending an arbitrary string
-- immediately following the patch version. The string MUST be comprised of
-- only alphanumerics plus dash [0-9A-Za-z-] and MUST begin with an alpha
-- character [A-Za-z]. Special versions satisfy but have a lower precedence
-- than the associated normal version. Precedence SHOULD be determined by
-- lexicographic ASCII sort order. For instance: 1.0.0beta1 < 1.0.0beta2 <
-- 1.0.0.

CREATE TYPE semver64;

--
-- essential IO
--
CREATE OR REPLACE FUNCTION semver64_in(cstring)
	RETURNS semver64
	AS 'semver64'
	LANGUAGE C STRICT IMMUTABLE;

CREATE OR REPLACE FUNCTION semver64_out(semver64)
	RETURNS cstring
	AS 'semver64'
	LANGUAGE C STRICT IMMUTABLE;

-- add recv/send functions

CREATE FUNCTION semver64_recv(internal)
    RETURNS semver64
    AS 'semver64'
    LANGUAGE C IMMUTABLE STRICT;

CREATE FUNCTION semver64_send(semver64)
    RETURNS bytea
    AS 'semver64'
    LANGUAGE C IMMUTABLE STRICT;

--
--  The type itself.
--

CREATE TYPE semver64 (
	INPUT = semver64_in,
	OUTPUT = semver64_out,
-- values of passedbyvalue and alignment are copied from the named type.
    STORAGE = plain,
	INTERNALLENGTH = variable,
-- string category, to automatically try string conversion, etc.
	CATEGORY = 'S',
    RECEIVE = semver64_recv,
    SEND = semver64_send,
	PREFERRED = false
);

--
--  A lax constructor function.
--

CREATE OR REPLACE FUNCTION to_semver64(text)
	RETURNS semver64
	AS 'semver64'
	LANGUAGE C STRICT IMMUTABLE;

--
--  Typecasting functions.
--

CREATE OR REPLACE FUNCTION semver64(text)
	RETURNS semver64
    AS 'semver64', 'text_to_semver64'
	LANGUAGE C STRICT IMMUTABLE;

CREATE OR REPLACE FUNCTION text(semver64)
	RETURNS text
    AS 'semver64', 'semver64_to_text'
	LANGUAGE C STRICT IMMUTABLE;

CREATE OR REPLACE FUNCTION semver64(numeric)
	RETURNS semver64 AS $$ SELECT to_semver64($1::text) $$
    LANGUAGE SQL STRICT IMMUTABLE;

CREATE OR REPLACE FUNCTION semver64(real)
	RETURNS semver64 AS $$ SELECT to_semver64($1::text) $$
    LANGUAGE SQL STRICT IMMUTABLE;

CREATE OR REPLACE FUNCTION semver64(double precision)
	RETURNS semver64 AS $$ SELECT to_semver64($1::text) $$
    LANGUAGE SQL STRICT IMMUTABLE;

CREATE OR REPLACE FUNCTION semver64(integer)
	RETURNS semver64 AS $$ SELECT to_semver64($1::text) $$
    LANGUAGE SQL STRICT IMMUTABLE;

CREATE OR REPLACE FUNCTION semver64(smallint)
	RETURNS semver64 AS $$ SELECT to_semver64($1::text) $$
    LANGUAGE SQL STRICT IMMUTABLE;

CREATE OR REPLACE FUNCTION semver64(bigint)
	RETURNS semver64 AS $$ SELECT to_semver64($1::text) $$
    LANGUAGE SQL STRICT IMMUTABLE;

--
--  Explicit type casts.
--

CREATE CAST (semver64 AS text)             WITH FUNCTION text(semver64);
CREATE CAST (text AS semver64)             WITH FUNCTION semver64(text);
CREATE CAST (numeric AS semver64)          WITH FUNCTION semver64(numeric);
CREATE CAST (real AS semver64)             WITH FUNCTION semver64(real);
CREATE CAST (double precision AS semver64) WITH FUNCTION semver64(double precision);
CREATE CAST (integer AS semver64)          WITH FUNCTION semver64(integer);
CREATE CAST (smallint AS semver64)         WITH FUNCTION semver64(smallint);
CREATE CAST (bigint AS semver64)           WITH FUNCTION semver64(bigint);

--
--	Comparison functions and their corresponding operators.
--

CREATE OR REPLACE FUNCTION semver64_eq(semver64, semver64)
	RETURNS bool
	AS 'semver64'
	LANGUAGE C STRICT IMMUTABLE;

CREATE OPERATOR = (
	leftarg = semver64,
	rightarg = semver64,
	negator = <>,
	procedure = semver64_eq,
	restrict = eqsel,
	commutator = =,
	join = eqjoinsel,
	hashes, merges
);

CREATE OR REPLACE FUNCTION semver64_ne(semver64, semver64)
	RETURNS bool
	AS 'semver64'
	LANGUAGE C STRICT IMMUTABLE;

CREATE OPERATOR <> (
	leftarg = semver64,
	rightarg = semver64,
	negator = =,
	procedure = semver64_ne,
	restrict = neqsel,
	join = neqjoinsel
);

CREATE OR REPLACE FUNCTION semver64_le(semver64, semver64)
	RETURNS bool
	AS 'semver64'
	LANGUAGE C STRICT IMMUTABLE;

CREATE OPERATOR <= (
	leftarg = semver64,
	rightarg = semver64,
	negator = >,
	procedure = semver64_le
);

CREATE OR REPLACE FUNCTION semver64_lt(semver64, semver64)
	RETURNS bool
	AS 'semver64'
	LANGUAGE C STRICT IMMUTABLE;

CREATE OPERATOR < (
	leftarg = semver64,
	rightarg = semver64,
	negator = >=,
	procedure = semver64_lt
);

CREATE OR REPLACE FUNCTION semver64_ge(semver64, semver64)
	RETURNS bool
	AS 'semver64'
	LANGUAGE C STRICT IMMUTABLE;

CREATE OPERATOR >= (
	leftarg = semver64,
	rightarg = semver64,
	negator = <,
	procedure = semver64_ge
);

CREATE OR REPLACE FUNCTION semver64_gt(semver64, semver64)
	RETURNS bool
	AS 'semver64'
	LANGUAGE C STRICT IMMUTABLE;

CREATE OPERATOR > (
	leftarg = semver64,
	rightarg = semver64,
	negator = <=,
	procedure = semver64_gt
);

--
-- Support functions for indexing.
--

CREATE OR REPLACE FUNCTION semver64_cmp(semver64, semver64)
	RETURNS int4
	AS 'semver64'
	LANGUAGE C STRICT IMMUTABLE;

CREATE OR REPLACE FUNCTION hash_semver64(semver64)
	RETURNS int4
	AS 'semver64'
	LANGUAGE C STRICT IMMUTABLE;

--
-- The btree indexing operator class.
--

CREATE OPERATOR CLASS semver64_ops
DEFAULT FOR TYPE SEMVER64 USING btree AS
    OPERATOR    1   <  (semver64, semver64),
    OPERATOR    2   <= (semver64, semver64),
    OPERATOR    3   =  (semver64, semver64),
    OPERATOR    4   >= (semver64, semver64),
    OPERATOR    5   >  (semver64, semver64),
    FUNCTION    1   semver64_cmp(semver64, semver64);

--
-- The hash indexing operator class.
--

CREATE OPERATOR CLASS semver64_ops
DEFAULT FOR TYPE semver64 USING hash AS
    OPERATOR    1   =  (semver64, semver64),
    FUNCTION    1   hash_semver64(semver64);

--
-- Aggregates.
--

CREATE OR REPLACE FUNCTION semver64_smaller(semver64, semver64)
	RETURNS semver64
	AS 'semver64'
	LANGUAGE C STRICT IMMUTABLE;

CREATE AGGREGATE min(semver64)  (
    SFUNC = semver64_smaller,
    STYPE = semver64,
    SORTOP = <
);

CREATE OR REPLACE FUNCTION semver64_larger(semver64, semver64)
	RETURNS semver64
	AS 'semver64'
	LANGUAGE C STRICT IMMUTABLE;

CREATE AGGREGATE max(semver64)  (
    SFUNC = semver64_larger,
    STYPE = semver64,
    SORTOP = >
);

--
-- Is function.
--

CREATE OR REPLACE FUNCTION is_semver64(text)
	RETURNS bool
	AS 'semver64'
	LANGUAGE C STRICT IMMUTABLE;

--
-- Accessor functions
--

CREATE OR REPLACE FUNCTION get_semver64_major(semver64)
	RETURNS text
	AS 'semver64'
	LANGUAGE C STRICT IMMUTABLE;

CREATE OR REPLACE FUNCTION get_semver64_minor(semver64)
	RETURNS text
	AS 'semver64'
	LANGUAGE C STRICT IMMUTABLE;

CREATE OR REPLACE FUNCTION get_semver64_patch(semver64)
	RETURNS text
	AS 'semver64'
	LANGUAGE C STRICT IMMUTABLE;

CREATE OR REPLACE FUNCTION get_semver64_prerelease(semver64)
        RETURNS text
        AS 'semver64'
        LANGUAGE C STRICT IMMUTABLE;

CREATE TYPE semver64range AS RANGE (SUBTYPE = semver64);
