# Postgresql JSON query language

## Plan

## JSON(b) query language for postgresql


New binary storage format for JSON with name [*JSONB*](http://www.postgresql.org/docs/9.4/static/datatype-json.html)
was introduced in Postgresql 9.4 by [Russian pg team](http://obartunov.livejournal.com/177247.html).

Next challenge for pg team is advanced and efficient search in
jsonb documents (jsquery and VODKA).

This article is light introduction into new
postgresql extension  *jsquery*.
- query language for jsonb documents.

## Installation

Source code of *jsquery* is located at https://github.com/akorotkov/jsquery).
Installation requires requires PostgreSQL 9.4.

If you already have postgres 9.4, you can build jsquery from sources:

```bash
cd $PG_SOURCE_DIR/contrib
git clone https://github.com/akorotkov/jsquery.git
cd jsquery
make && make install && make installcheck
```

For this tutorial i've created docker image `niquola/jsquery`.

Image is defined by [Dockerfile](https://github.com/niquola/day-of-pg-jsquery/blob/master/Dockerfile)
and contains postgresql-9.4 built from sources with jsquery and pgcrypto extensions.
All pg executables are in `/home/dba/bin` directory and pg cluster in `/home/dba/data`.

Image also has database `day_of_jsquery`, filled with json
documents from open Health IT standard [FHIR](http://www.hl7.org/implement/standards/fhir/).

If you have installed [docker](https://docs.docker.com/),
just run new container:

```
docker run --name=jsquery -p 5432:5555 -i -t niquola/jsquery
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
  ...
  "name": [
    {
     "use": "official",
     "given": ["Peter", "James"],
     "family": ["Chalmers"]
    },
   ....
  ],
  ...
}
```

Let's find all patients with given name "Peter":

```SQL
SELECT content->'name'
  FROM resources
 WHERE content @@ $JS$
   resourceType="Patient"
   AND name.#.given @> ["Peter"]
 $JS$
```

Find all patients with given = "Duck"
and family = "Donald":

```SQL
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

```SQL
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

We could query for "Male" as

* geneder.display = "Male"
* %.% = "Male"
* * = "Male"

When we have array in path, we should use
*#* - any element of array:

```
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

### IN

*in* operator:

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

## HINTS

Best place to find more information is to look at
[tests](https://github.com/akorotkov/jsquery/blob/master/sql/jsquery.sql)
