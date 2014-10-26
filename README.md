# Postgresql JSON query language

## JSON(b) query language for postgresql


New binary storage for JSON with name [*JSONB*](http://www.postgresql.org/docs/9.4/static/datatype-json.html)
was introduced in Postgresql 9.4 by [Russian pg team](http://obartunov.livejournal.com/177247.html).

This feature joins advantages of document & relational databases.
Next challenge for pg team is advanced and efficient search in
jsonb documents (jsquery and VODKA).


This article is light introduction into new promising
postgresql extension  [*jsquery*](https://github.com/akorotkov/jsquery)
- query language for jsonb documents.

`jsquery` is under active development and looks very promising.

## Installation

To start we need postgresql with version 9.4 and jsquery extension.

We gonna use docker to build postgresql 9.4
in container for quick start and sandboxing.

Install [docker](https://docs.docker.com/).

You can run docker image `niquola/jsquery` from docker hub:

```
docker run --name=jsquery -p 5432 -i -t niquola/jsquery
```

This will start docker container and open psql.
But you can also connect to database in container:

```sql
# inspect port forwarding

docker ps -a | grep jsquery

> 3c75718833c6  niquola/jsquery:latest  "/bin/sh -c 'pg_ctl  10 minutes ago  Up 10 minutes  0.0.0.0:49153->5432/tcp  jsquery

# 0.0.0.0:49153->5432/tcp - this means that container port 5432 is visible at localhost as 49153
# connection information user=db password=db database=day_of_jsquery

export PGPASSWORD=db
psql -h localhost -p 49153 -U db day_of_jsquery

```

This image contains postgresql-9.4 built from sources.
All pg executables are in /home/dba/bin directory.
There is initialized cluster in /home/dba/data directory.

Image contains also database `day_of_jsquery`, filled with jsonb
documents from open Health IT standard [FHIR]().

Fill free to change Dockerfile.

## jsquery

*jsquery*  is query language for jsonb documents.

To query jsonb document we use expression:

```sql
SELECT *
  FROM your_table
 WHERE your_jsonb_column @@ '<jsquery expression>'
```

We start from some examples. In database `day_of_jsquery` we have table `resources`:

```sql
CREATE EXTENSION jsquery;
CREATE EXTENSION pgcrypto;

CREATE TABLE resources (
  id uuid primary key default gen_random_uuid(),
  content jsonb
);
```

All resources have attribute `resourceType`.
Let's select all `Patient` resources:

```sql
SELECT * FROM resources
 WHERE content @@ 'resourceType="Patient"'
```

This query should return patient records.

Patients have attribute `name`
with array of maps:

```json
"name": [
  {
   "use": "official",
   "given": ["Peter", "James"],
   "family": ["Chalmers"]
  }
]
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

The simple way to check expression is just cast text to `jsquery` using:

```sql
select 'asd(zzz < 13)'::jsquery;
```

Expressions grammar is
described in [jsquery_gram.y](https://github.com/akorotkov/jsquery/blob/master/jsquery_gram.y)
and here is [visualized EBNF rules](http://niquola.github.io/blog/jsquery_ebnf.xhtml).



Expression consists of `path` of attrubute

Read json & jsonb functions documentation and fill free
to play with functions - http://www.postgresql.org/docs/9.4/static/functions-json.html


Best place to find information is to look at [tests](https://github.com/akorotkov/jsquery/blob/master/sql/jsquery.sql)
