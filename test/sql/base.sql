\set ECHO none
BEGIN;

\i test/pgtap-core.sql
\i sql/semver64.sql

SELECT plan(291);
--SELECT * FROM no_plan();

SELECT has_type('semver64');
SELECT is( NULL::semver64, NULL, 'semvers should be NULLable' );

SELECT lives_ok(
    $$ SELECT '$$ || v || $$'::semver64 $$,
    '"' || v || '" is a valid semver'
)  FROM unnest(ARRAY[
    '1.2.2',
    '0.2.2',
    '0.0.0',
    '0.1.999',
    '9999.9999999.823823',
    '18446744073709551615.823823.18446744073709551615',
    '18446744073709551615.823823.18446744073709551615-beta2',
    '1.0.0-beta1',
    '1.0.0-beta2',
    '1.0.0',
    '1.0.0-1',
    '1.0.0-alpha+d34dm34t',
    '1.0.0+d34dm34t',
    '20110204.0.0',
    '1.0.0-alpha.0a',
    '1.0.0+010',
    '1.0.0+alpha.010',
    '1.0.0-0AEF'
]) AS v;

SELECT throws_ok(
    $$ SELECT '$$ || v || $$'::semver64 $$,
    NULL,
    '"' || v || '" is not a valid semver'
)  FROM unnest(ARRAY[
    '1.2',
    '1.2.02',
    '1.2.2-',
    '1.2.3b#5',
    '03.3.3',
    'v1.2.2',
    '1.3b',
    '1.4b.0',
    '1v',
    '1v.2.2v',
    '1.2.4b.5',
    '1.0.0-alpha.010',
    '1.0.0-02799',
    '1.1.2+.123',
    '1.1.2-.123',
    '1.2.3-ñø',
    '1.2.3+ñø1'
]) AS v;

-- Test =, <=, and >=.
SELECT collect_tap(ARRAY[
    ok(semver64_cmp(lv::semver64, rv::semver64) = 0, 'semver64(' || lv || ', ' || rv || ') should = 0'),
    ok(lv::semver64 = rv::semver64, 'v' || lv || ' should = v' || rv),
    ok(lv::semver64 <= rv::semver64, 'v' || lv || ' should be <= v' || rv),
    ok(lv::semver64 >= rv::semver64, 'v' || lv || ' should be >= v' || rv)
]) FROM (VALUES
    ('1.2.2',  '1.2.2'),
    ('1.2.23', '1.2.23'),
    ('0.0.0', '0.0.0'),
    ('999.888.7777', '999.888.7777'),
    ('0.1.2-beta3', '0.1.2-beta3'),
    ('1.0.0-rc-1', '1.0.0-RC-1'),
    ('18446744073709551615.18446744073709551615.18446744073709551615-rc-1', '18446744073709551615.18446744073709551615.18446744073709551615-RC-1')
 ) AS f(lv, rv);

-- Test semver <> semver
SELECT collect_tap(ARRAY[
    ok(semver64_cmp(lv::semver64, rv::semver64) <> 0, 'semver64(' || lv || ', ' || rv || ') should <> 0'),
    ok(lv::semver64 <> rv::semver64, 'v' || lv || ' should not equal v' || rv)
]) FROM (VALUES
    ('0.0.1', '1.0.0'),
    ('1.0.1', '1.1.0'),
    ('1.1.1', '1.1.0'),
    ('1.2.3-b', '1.2.3'),
    ('1.2.3', '1.2.3-b'),
    ('1.2.3-a', '1.2.3-b'),
    ('1.2.3-aaaaaaa1', '1.2.3-aaaaaaa2'),
    ('1.2.3-1.2.3', '1.2.3-1.2.3.4'),
    ('18446744073709551615.18446744073709551615.18446744073709551615', '18446744073709551615.18446744073709551615.18446744073709551614'),
    ('18446744073709551615.18446744073709551615.18446744073709551615-1.2.3', '18446744073709551615.18446744073709551615.18446744073709551615-1.2.3.4')
  ) AS f(lv, rv);

-- Test >, >=, <, and <=.
SELECT collect_tap(ARRAY[
    ok( semver64_cmp(lv::semver64, rv::semver64) > 0, 'semver64(' || lv || ', ' || rv || ') should > 0'),
    ok( semver64_cmp(rv::semver64, lv::semver64) < 0, 'semver64(' || rv || ', ' || lv || ') should < 0'),
    ok(lv::semver64 > rv::semver64, 'v' || lv || ' should be > v' || rv),
    ok(lv::semver64 >= rv::semver64, 'v' || lv || ' should be >= v' || rv),
    ok(rv::semver64 < lv::semver64, 'v' || rv || ' should be < v' || lv),
    ok(rv::semver64 <= lv::semver64, 'v' || rv || ' should be <= v' || lv)
]) FROM (VALUES
    ('2.2.2', '1.1.1'),
    ('18446744073709551615.0.0', '18446744073709551614.18446744073709551615.18446744073709551615'),
    ('2.2.2', '2.1.1'),
    ('2.2.2', '2.2.1'),
    ('2.2.2-b', '2.2.1'),
    ('2.2.2', '2.2.2-b'),
    ('2.2.2-c', '2.2.2-b'),
    ('2.2.2-rc-2', '2.2.2-RC-1'),
    ('0.9.10', '0.9.9'),
    ('1.0.1-1.2.3', '1.0.1-0.9.9.9')
  ) AS f(lv, rv);

-- Test to_semver64().
SELECT has_function('to_semver64');
SELECT has_function('to_semver64', ARRAY['text']);
SELECT function_returns('to_semver64', 'semver64');

-- to_semver still needs to reject truly bad input
SELECT throws_ok(
    $$ SELECT '$$ || v || $$'::semver64 $$,
    NULL,
    '"' || v || '" is not a valid semver'
)  FROM unnest(ARRAY[
   '1.2.0 beta 4',
   '1.2.2-',
   '1.02.2',
   '1.2.3b#5',
   'v1.2.2',
   '1.4b.0',
   '1v.2.2v',
   '1.2.4b.5',
   '1.2.3.4',
   '1.2.3 4',
   '1.2000000000000000.3.4'
]) AS v;

-- Test sort ordering
CREATE TABLE vs (
    version semver64
);

INSERT INTO vs VALUES ('1.2.0'), ('1.0.0'), ('1.0.0-p0'), ('0.9.9'), ('0.9.10');

SELECT is(max(version), '1.2.0', 'max(semver) should work')
  FROM vs;

SELECT is(min(version), '0.9.9', 'min(semver) should work')
  FROM vs;

SELECT results_eq(
    $$ SELECT version FROM vs ORDER BY version USING < $$,
    $$ VALUES ('0.9.9'::semver64), ('0.9.10'::semver64), ('1.0.0-p0'::semver64), ('1.0.0'::semver64), ('1.2.0'::semver64) $$,
    'ORDER BY semver USING < should work'
);

SELECT results_eq(
    $$ SELECT version FROM vs ORDER BY version USING > $$,
    $$ VALUES ('1.2.0'::semver64), ('1.0.0'::semver64), ('1.0.0-p0'::semver64), ('0.9.10'::semver64), ('0.9.9'::semver64) $$,
    'ORDER BY semver USING > should work'
);

-- Test constructors.
SELECT is( text('1.2.0'::semver64), '1.2.0', 'construct to text' );
SELECT is( semver64('1.2.0'), '1.2.0'::semver64, 'construct from text' );
SELECT is( semver64(1.2), '1.2.0'::semver64, 'construct from bare number' );
SELECT is( semver64(1.2::numeric), '1.2.0'::semver64, 'construct from numeric' );
SELECT is( semver64(1), '1.0.0'::semver64, 'construct from bare integer' );
SELECT is( semver64(1::integer), '1.0.0'::semver64, 'construct from integer' );
SELECT is( semver64(1::bigint), '1.0.0'::semver64, 'construct from bigint' );
SELECT is( semver64(1::smallint), '1.0.0'::semver64, 'construct from smallint' );
SELECT is( semver64(1.2::decimal), '1.2.0'::semver64, 'construct from decimal' );
SELECT is( semver64(1.2::real), '1.2.0'::semver64, 'construct from real' );
SELECT is( semver64(1.2::double precision), '1.2.0'::semver64, 'construct from double' );
SELECT is( semver64(1.2::float), '1.2.0'::semver64, 'construct from float' );

-- Test casting.
SELECT is( semver64('1.2.0'::text), '1.2.0', 'cast to text' );
SELECT is( text('1.2.0')::semver64, '1.2.0'::semver64, 'cast from text' );
SELECT is( 1::semver64, '1.0.0'::semver64, 'Cast from bare integer');
SELECT is( 1.2::semver64, '1.2.0'::semver64, 'Cast from bare number');
SELECT is( 1.2::numeric::semver64, '1.2.0'::semver64, 'Cast from numeric');
SELECT is( 1::integer::semver64, '1.0.0'::semver64, 'Cast from integer');
SELECT is( 1::bigint::semver64, '1.0.0'::semver64, 'Cast from bigint');
SELECT is( 1::smallint::semver64, '1.0.0'::semver64, 'Cast from smallint');
SELECT is( 1.0::decimal::semver64, '1.0.0'::semver64, 'Cast from decimal');
SELECT is( 1::decimal::semver64, '1.0.0'::semver64, 'Cast from decimal');
SELECT is( 1.0::real::semver64, '1.0.0'::semver64, 'Cast from real');
SELECT is( 1.0::double precision::semver64, '1.0.0'::semver64, 'Cast from double precision');
SELECT is( 1.0::float::semver64, '1.0.0'::semver64, 'Cast from float');

-- Test casting some more.
SELECT IS(lv::text, rv, 'Should correctly cast "' || rv || '" to text')
  FROM (VALUES
    ('1.0.0-beta'::semver64,   '1.0.0-beta'),
    ('1.0.0-beta1'::semver64,  '1.0.0-beta1'),
    ('1.0.0-alpha'::semver64,  '1.0.0-alpha'),
    ('1.0.0-alph'::semver64,   '1.0.0-alph'),
    ('1.0.0-food'::semver64,   '1.0.0-food'),
    ('1.0.0-f111'::semver64,   '1.0.0-f111'),
    ('1.0.0-f111asbcdasdfasdfasdfasdfasdfasdffasdfadsf'::semver64,
     '1.0.0-f111asbcdasdfasdfasdfasdfasdfasdffasdfadsf'),
    ('18446744073709551615.18446744073709551615.18446744073709551615-f111'::semver64,
        '18446744073709551615.18446744073709551615.18446744073709551615-f111')
 ) AS f(lv, rv);

-- SEMV 2.0.0 tests.
SELECT lives_ok(
    $$ SELECT '$$ || v || $$'::semver64 $$,
    '"' || v || '" is a valid 2.0.0 semver'
)  FROM unnest(ARRAY[
    '1.0.0+1',
    '1.0.0-1+1',
    '1.0.0-1.1+1',
    '1.0.0-1.1.1.1.1.1.1.1.1.1.1+1.1.1.1.1.1.1.1',
    '1.0.0-1.2',
    '1.0.0-1.0.2',
    '1.0.0-alpha',
    '1.0.0-alpha.1',
    '1.0.0-0.3.7',
    '1.0.0-x.7.z.92',
    '0.2.13+1583426134.07de632'
]) AS v;

SELECT throws_ok(
    $$ SELECT '$$ || v || $$'::semver64 $$,
    NULL,
    '"' || v || '" is not a valid 2.0.0 semver'
)  FROM unnest(ARRAY[
   '1.0.0-a..',
   '1.0.0-a.1.',
   '1.0.0+1_1',
   '1.0.0-1....',
   '1.0.0-1_2',
   '1.0.0-1.02'
]) AS v;

DELETE FROM vs;
INSERT INTO vs VALUES ('0.9.9-a1.1+1234'::semver64), ('0.9.9-a1.2.3'::semver64), ('0.9.9-a1.2'::semver64), ('0.9.9'::semver64), ('1.0.0+99'::semver64), ('1.0.0-1'::semver64);

SELECT results_eq(
    $$ SELECT version FROM vs ORDER BY version USING < $$,
    $$ VALUES ('0.9.9-a1.1+1234'::semver64), ('0.9.9-a1.2'::semver64), ('0.9.9-a1.2.3'::semver64), ('0.9.9'::semver64), ('1.0.0-1'::semver64), ('1.0.0+99'::semver64) $$,
    'ORDER BY semver (2.0.0) USING < should work'
);

SELECT results_eq(
    $$ SELECT version FROM vs ORDER BY version USING > $$,
    $$ VALUES ('1.0.0+99'::semver64), ('1.0.0-1'::semver64), ('0.9.9'::semver64), ('0.9.9-a1.2.3'::semver64), ('0.9.9-a1.2'::semver64), ('0.9.9-a1.1+1234'::semver64) $$,
    'ORDER BY semver (2.0.0) USING > should work'
);

SELECT collect_tap(ARRAY[
    ok(semver64_cmp(lv::semver64, rv::semver64) = 0, 'semver64(' || lv || ', ' || rv || ') should = 0'),
    ok(lv::semver64 = rv::semver64, 'v' || lv || ' should = v' || rv),
    ok(lv::semver64 <= rv::semver64, 'v' || lv || ' should be <= v' || rv),
    ok(lv::semver64 >= rv::semver64, 'v' || lv || ' should be >= v' || rv)
]) FROM (VALUES
    ('1.0.0-1+1',  '1.0.0-1+5'),
    ('1.0.0-1.1+1',  '1.0.0-1.1+5')
 ) AS f(lv, rv);

-- Test is_semver64().
SELECT has_function('is_semver64');
SELECT has_function('is_semver64', ARRAY['text']);
SELECT function_returns('is_semver64', 'boolean');

SELECT is(
    is_semver64(stimulus),
    expected,
    'is_semver64(' || stimulus || ') should return ' || expected::text
) FROM (VALUES
    ('1.2.2',                     true),
    ('0.2.2',                     true),
    ('0.0.0',                     true),
    ('0.1.999',                   true),
    ('9999.9999999.823823',       true),
    ('1.0.0-beta1',               true),
    ('1.0.0-beta2',               true),
    ('1.0.0',                     true),
    ('1.0.0-1',                   true),
    ('1.0.0-alpha+d34dm34t',      true),
    ('1.0.0+d34dm34t',            true),
    ('20110204.0.0',              true),
    ('1.2',                       false),
    ('1.2.02',                    false),
    ('1.2.2-',                    false),
    ('1.2.3b#5',                  false),
    ('03.3.3',                    false),
    ('v1.2.2',                    false),
    ('1.3b',                      false),
    ('1.4b.0',                    false),
    ('1v',                        false),
    ('1v.2.2v',                   false),
    ('1.2.4b.5',                  false),
    ('2016.5.18-MYW-600',         true),
    ('1010.5.0+2016-05-27-1832',  true),
    ('0.2.13+1583426134.07de632', true)
) v(stimulus, expected);

-- issue-gh-23
SELECT lives_ok(
    $$ SELECT '$$ || v || $$'::semver64 $$,
    '"' || v || '" is a valid semver'
)  FROM unnest(ARRAY[
    '2.3.0+80'
]) AS v;

SELECT is(lv::text, rv, 'Should correctly cast "' || rv || '" to text')
  FROM (VALUES
    ('2.3.0+80'::semver64, '2.3.0+80')
) AS f(lv, rv);
SELECT isnt(lv::semver64 > rv::semver64, true, '"' || lv || '" > "' || rv || '" (NOT!)')
  FROM (VALUES
    ('2.3.0+80', '2.3.0+110')
) AS f(lv, rv);
SELECT is(lv::semver64 > rv::semver64, true, '"' || lv || '" > "' || rv || '"')
  FROM (VALUES
    ('2.3.0+80', '2.3.0-alpha+110')
) AS f(lv, rv);


CREATE TABLE vs23 (
    version semver64
);
INSERT INTO vs23 VALUES ('1.0.0-alpha'), ('1.0.0-alpha.1'), ('1.0.0-alpha.beta'), ('1.0.0-beta'), ('1.0.0-beta.2'), ('1.0.0-beta.11'), ('1.0.0-rc.1'), ('1.0.0');
SELECT results_eq(
    $$ SELECT version FROM vs23 ORDER BY version USING < $$,
    $$ VALUES ('1.0.0-alpha'::semver64), ('1.0.0-alpha.1'::semver64), ('1.0.0-alpha.beta'::semver64), ('1.0.0-beta'::semver64), ('1.0.0-beta.2'::semver64), ('1.0.0-beta.11'::semver64), ('1.0.0-rc.1'::semver64), ('1.0.0'::semver64) $$,
    'ORDER BY semver USING < should work (section 11)'
);
SELECT results_eq(
    $$ SELECT version FROM vs23 ORDER BY version USING > $$,
    $$ VALUES ('1.0.0'::semver64), ('1.0.0-rc.1'::semver64), ('1.0.0-beta.11'::semver64), ('1.0.0-beta.2'::semver64), ('1.0.0-beta'::semver64), ('1.0.0-alpha.beta'::semver64), ('1.0.0-alpha.1'::semver64), ('1.0.0-alpha'::semver64) $$,
    'ORDER BY semver USING > should work (section 11)'
);
SELECT is(lv::semver64 = rv::semver64, true, '"' || lv || '" = "' || rv || '"')
  FROM (VALUES
    ('1.0.0', '1.0.0+535')
) AS f(lv, rv);
SELECT isnt(lv::semver64 < rv::semver64, true, '"' || lv || '" < "' || rv || '" (NOT!)')
  FROM (VALUES
    ('1.0.0', '1.0.0+535')
) AS f(lv, rv);
SELECT isnt(lv::semver64 > rv::semver64, true, '"' || lv || '" > "' || rv || '" (NOT!)')
  FROM (VALUES
    ('1.0.0', '1.0.0+535')
) AS f(lv, rv);

-- Test get_semver64_major
SELECT has_function('get_semver64_major');
SELECT has_function('get_semver64_major', 'semver');
SELECT function_returns('get_semver64_major', 'text');
SELECT is(get_semver64_major('2.1.0-alpha'::semver64), '2', 'major version check');
SELECT is(get_semver64_major('18446744073709551615.1.2-f111'::semver64), '18446744073709551615', 'major version check');

-- Test get_semver64_minor
SELECT has_function('get_semver64_minor');
SELECT has_function('get_semver64_minor', 'semver');
SELECT function_returns('get_semver64_minor', 'text');
SELECT is(get_semver64_minor('2.1.0-alpha'::semver64), '1', 'minor version check');
SELECT is(get_semver64_minor('2.18446744073709551615.3-f111'::semver64), '18446744073709551615', 'minor version check');

-- Test get_semver64_patch
SELECT has_function('get_semver64_patch');
SELECT has_function('get_semver64_patch', 'semver');
SELECT function_returns('get_semver64_patch', 'text');
SELECT is(get_semver64_patch('2.1.0-alpha'::semver64), '0', 'patch version check');
SELECT is(get_semver64_patch('2.3.18446744073709551615-f111'::semver64), '18446744073709551615', 'minor version check');

-- Test get_semver64_prerelease
SELECT has_function('get_semver64_prerelease');
SELECT has_function('get_semver64_prerelease', 'semver');
SELECT function_returns('get_semver64_prerelease', 'text');
SELECT is(get_semver64_prerelease('2.1.0-alpha'::semver64), 'alpha', 'prerelease label check');
SELECT is(get_semver64_prerelease('2.1.0-alpha+build'::semver64), 'alpha', 'prerelease label check. must return prerelease only');
SELECT is(get_semver64_prerelease('2.1.0+build'::semver64), '', 'prerelease label check. must return empty string');

-- Test range type.
SELECT ok(
    '1.0.0'::semver64 <@ '[1.0.0, 2.0.0]'::semver64range,
    '1.0.0 should be in range [1.0.0, 2.0.0]'
);
SELECT ok(
    NOT '1.0.0'::semver64 <@ '[1.0.1, 2.0.0]'::semver64range,
    '1.0.0 should not be in range [1.0.1, 2.0.0]'
);

SELECT ok(
    NOT semver64range('1.0.0', '2.0.0') @> '2.0.0'::semver64,
    '2.0.0 should not be in range [1.0.1, 2.0.0)'
);

SELECT ok(
    semver64range('1.0.0', '2.0.0') @> '1.9999.9999'::semver64,
    '1.9999.9999 should be in range [1.0.1, 2.0.0)'
);

SELECT ok(
    '1000.0.0'::semver64 <@ '[1.0.0,]'::semver64range,
    '1000.0.0 should be in range [1.0.0,)'
);

SELECT bag_eq($$
    SELECT version, version <@ ANY(
        '{"(1.0.0,1.2.3)", "(1.2.3,1.4.5)", "(1.4.5,2.0.0)"}'::semver64range[]
    ) AS valid FROM (VALUES
        ('1.0.0'::semver64), ('1.0.1'), ('1.2.3'), ('1.2.4'), ('1.4.4'), ('1.4.5'),
        ('1.7.0'), ('2.0.0')
    ) AS v(version)
$$, $$ VALUES
    ('1.0.0'::semver64, false),
    ('1.0.1', true),
    ('1.2.3', false),
    ('1.2.4', true),
    ('1.4.4', true),
    ('1.4.5', false),
    ('1.7.0', true),
    ('2.0.0', false)
$$, 'Should be able to work with arrays of semverranges');

-- Test formatting (issue-gh-48)
SELECT is(
    '1.0.0+1234567890123456789012345'::semver64::text,
    '1.0.0+1234567890123456789012345',
    'Should properly format a 32 character semver'
);

SELECT is(
    '1.0.0+12345678901234567890123456'::semver64::text,
    '1.0.0+12345678901234567890123456',
    'Should properly format a 33 character semver'
);

-- issue-gh-46
SELECT is(
    '1.0.0-alpha-0'::semver64::text, '1.0.0-alpha-0',
    'Should propery format a prerelease with a hyphen'
);

SELECT * FROM finish();
ROLLBACK;
