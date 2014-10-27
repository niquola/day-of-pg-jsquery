# jsquery  - query language for jsonb in postgres

New binary storage format for JSON with name [*JSONB*](http://www.postgresql.org/docs/9.4/static/datatype-json.html)
was introduced in Postgresql 9.4 by [Russian pg team](http://obartunov.livejournal.com/177247.html).

Next challenge for pg team is advanced and efficient search in
jsonb documents (jsquery and VODKA).

This article is introduction into
postgresql extension  *jsquery* - query language for jsonb documents.

## Installation

Source code of *jsquery* is located at https://github.com/akorotkov/jsquery).
Installation requires PostgreSQL 9.4.

If you have postgres 9.4, you can build jsquery from sources:

```bash
cd $PG_SOURCE_DIR/contrib
git clone https://github.com/akorotkov/jsquery.git
cd jsquery
make && make install && make installcheck
```

For this tutorial i've created docker image [niquola/day-of-pg-jsquery](https://registry.hub.docker.com/u/niquola/day-of-pg-jsquery/)

Image is defined by [Dockerfile](https://github.com/niquola/day-of-pg-jsquery/blob/master/Dockerfile)
and contains postgresql-9.4 built from sources with jsquery and pgcrypto extensions.
All pg executables are in `/home/dba/bin` directory and pg cluster in `/home/dba/data`.

Image also has database `day_of_jsquery`, filled with json
documents from open Health IT standard [FHIR](http://www.hl7.org/implement/standards/fhir/).

If you have installed [docker](https://docs.docker.com/),
just run new container:

```bash
docker run --name=jsquery -p 5432:5555 -i -t niquola/day-of-pg-jsquery
```

This will start docker container and open psql.
Option `-p 5432:5555` instructs docker to bind container's port 5432 to host port 5555.
So you can connect to database from your preferred client: `host=localhost user=db password=db`.

```bash
export PGPASSWORD=db
psql -h localhost -p 5555 -U db day_of_jsquery
```

In this article we will use some json & jsonb functions:  http://www.postgresql.org/docs/9.4/static/functions-json.html.

## jsquery

*jsquery*  is query language for jsonb documents.

To query jsonb document we use query like this:

```sql
SELECT *
  FROM your_table
 WHERE your_jsonb_column @@ '<jsquery expression>'
```

Let's start from examples.

In database `day_of_jsquery` we have table `resources`:

```sql
CREATE EXTENSION jsquery;
CREATE EXTENSION pgcrypto;

CREATE TABLE resources (
  id uuid primary key default gen_random_uuid(),
  content jsonb
);
```

All resources have attribute *resourceType*.
Let's select all *Patient* resources:

```sql
SELECT * FROM resources
 WHERE content @@ 'resourceType="Patient"'
```

This query should return patient records.

Have a look at 'Patient' resource [specification](http://www.hl7.org/implement/standards/fhir/patient.html#resource).
Patient resource has attribute *name* with array of objects:

```json
{
  //...
  "name": [
    {
     "use": "official",
     "given": ["Peter", "James"],
     "family": ["Chalmers"]
    },
   //....
  ],
  //...
}
```

Let's find all patients with given name "Peter":

```sql
SELECT content->'name'
  FROM resources
 WHERE content @@ $JS$
   resourceType="Patient"
   AND name.#.given @> ["Peter"]
 $JS$
```

Find all patients with given = "Duck"
and family = "Donald":

```sql
SELECT content->'name' FROM resources
 WHERE content @@ $JS$
   resourceType="Patient" AND
   name.# (
     given @> ["Duck", "D"]
     AND family @> ["Donald"]
   )
 $JS$
```

## Grammar

jsquery grammar is
described in [jsquery_gram.y](https://github.com/akorotkov/jsquery/blob/master/jsquery_gram.y)
and [visualized as EBNF](http://niquola.github.io/blog/jsquery_ebnf.xhtml).

Query consists of expressions.

The simplest expression has form - `path predicate-operator value`:

```sql
resourceType = "Patient"
name.#.given @> ["Duck"]
```

Path constructed as chain of keys
and could contain some special wilecards:

* `*` - any path
* `#` - any item in array
* `%` - any key
* `$` - current key (used for recursive queries)

For json document:

```json
{
  "resourceType": "Patient",
  "gender": { "display": "Male" },
  "name": [
    {
     "use": "official",
     "given": ["Peter", "James"],
     "family": ["Chalmers"]
    },
  ]
}
```

We could query for "Male" as:

* geneder.display = "Male"
* %.% = "Male"
* * = "Male"

When we have array in path, we should use
*#* (any element of array):

```sql
name.#.given.# = "Peter"
```

Expressions could be logically composed
using 'AND' & 'OR' operators:

```
resourceType="Patient" AND name.#.given.# = "Peter"
```

Another type of expressions has form `path ( expression )`,
where *path* selects some branch of document and then
checks *expression* on it. For example to find all
patients with "usual" given name "Jim":

```sql
SELECT * FROM resources
 WHERE content @@ $JS$
  resourceType = "Patient" AND
  name.# (
    given.# = "Jim" AND
    use = "usual"
  )
 $JS$
```

Inside '()' the symbol *$* could be used to reference
current path key. This is very convenient when you
are applying more then one predicate:

```sql
select '[3,4]'::jsonb @@ '#($ > 2 and $ < 5)';

SELECT content
  FROM resources
 WHERE content @@ $JS$
  resourceType = "Encounter" AND
  length.value($ > 135 AND $ < 145)
 $JS$
```

## OPERATIONS

For different types of jsonb values
there are different predicate operators.

### String

Now string value could be queried only on equality:

```
resourceType = "Patient"
```

There is request & discussion about
ilike predicate [#1](https://github.com/akorotkov/jsquery/issues/1).

### Numbers && Booleans

Nothing interesting with numbers & booleans :)

* a = 0 AND b = false
* a < 10
* a > 10
* a >= 10
* a <= 10

### IN Operator

```
SELECT * FROM resources
 WHERE content @@ $JS$
   resourceType in ("MedicationDispense", "MedicationStatement", "MedicationAdministration", "MedicationPrescription")
 $JS$;
```

## IS

You could test type of value using *IS* operator:

```sql
select '{"as": "xxx"}' @@ 'as IS string'::jsquery;
select '{"as": 5}' @@ 'as is Numeric'::jsquery;
select '{"as": true}' @@ 'as is boolean'::jsquery;
select '["xxx"]' @@ '$ IS array'::jsquery;
select '"xxx"' @@ '$ IS string'::jsquery;
```

### Arrays

* `array @> subarray` - inclusion of subarray in array
* `subarray <@ array`
* `array1 && array2` - arrays intersection (i.e. at least one element in common)

Select all patients with given name "Peter", "Henry" or "Kenzi":

```sql
SELECT content->'name'
FROM resources
 WHERE content @@ $JS$
  resourceType = "Patient" AND
  name.#.given && ["Peter","Henry", "Kenzi"]
 $JS$
```

## INDEXING

Generate more patients:

```sql
-- simple template function
CREATE FUNCTION
template(_tpl_ text, variadic _bindings varchar[]) RETURNS text AS $$
DECLARE
  result text := _tpl_;
BEGIN
  FOR i IN 1..(array_upper(_bindings, 1)/2) LOOP
    result := replace(result, '{{' || _bindings[i*2 - 1] || '}}', coalesce(_bindings[i*2], ''));
  END LOOP;
  RETURN result;
END
$$ LANGUAGE plpgsql IMMUTABLE;

INSERT INTO resources (content)
SELECT template($JSON$
{
  "resourceType":"Patient",
  "test": true,
  "identifier":[{"system":"local", "code": "{{idx}}"}],
  "name":[{"given":["pt-{{idx}}"], "family": ["family-{{idx}}"]}]
}
$JSON$::text,
'idx', generate_series::varchar
)::jsonb
FROM generate_series(1,1000000);
```

Select patient with name 'pt-77777' and measure time:

```
\timing
-- Timing is on.

SELECT content->'name' as name
  FROM resources
 WHERE content @@ 'name.#.given && ["pt-66666"]'

--                       name
---------------------------------------------------------
-- [{"given": ["pt-66666"], "family": ["family-66666"]}]
-- (1 row)
--
-- Time: 585,828 ms
```

We could index documents using [GIN index](http://www.postgresql.org/docs/9.4/static/textsearch-indexes.html).

```sql
CREATE INDEX index_content ON
resources USING GIN (content jsonb_value_path_ops);

\timing
-- Timing is on.

SELECT content->'name' as name
  FROM resources
 WHERE content @@ 'name.#.given && ["pt-66666"]'

--                       name
---------------------------------------------------------
-- [{"given": ["pt-66666"], "family": ["family-66666"]}]
-- (1 row)
--
-- Time: 2,401 ms

SELECT content->'name' as name
  FROM resources
 WHERE content @@ '* = "family-66666"'

--                         name
---------------------------------------------------------
-- [{"given": ["pt-66666"], "family": ["family-66666"]}]
-- (1 row)
--
-- Time: 3,124 ms
```

Use explain analyse to inspect query plan:

```sql
EXPLAIN ANALYSE
 SELECT content->'name' as name
   FROM resources
  WHERE content @@ '* = "family-66666"'

--                                                        QUERY PLAN
----------------------------------------------------------------------------------------------------------------------------
-- Bitmap Heap Scan on resources  (cost=35.75..3466.12 rows=1000 width=207) (actual time=0.104..0.105 rows=1 loops=1)
--   Recheck Cond: (content @@ '* = "family-66666"'::jsquery)
--   Heap Blocks: exact=1
--   ->  Bitmap Index Scan on index_content  (cost=0.00..35.50 rows=1000 width=0) (actual time=0.068..0.068 rows=1 loops=1)
--         Index Cond: (content @@ '* = "family-66666"'::jsquery)
-- Planning time: 0.824 ms
-- Execution time: 0.485 ms

```


Index Scan could be skipped or forced using *hints*:

```sql
EXPLAIN ANALYSE
 SELECT content->'name' as name
  FROM resources
 WHERE content @@ 'name.#.family.# /*-- noindex */ = "family-66666"'

-- Timing is on.
--                                                   QUERY PLAN
-- ---------------------------------------------------------------------------------------------------------------
--  Seq Scan on resources  (cost=0.00..43752.50 rows=1000 width=207) (actual time=38.876..441.147 rows=1 loops=1)
--    Filter: (content @@ '"name".#."family".# /*-- noindex */  = "family-66666"'::jsquery)
--    Rows Removed by Filter: 999999
--  Planning time: 0.565 ms
--  Execution time: 441.187 ms
-- (5 rows)

-- Time: 443,518 ms
```

TODO: jsonb_path_value_ops ???

TODO: about vodka

## More information

Best place to find more information is [tests](https://github.com/akorotkov/jsquery/blob/master/sql/jsquery.sql)

## Conclusion
