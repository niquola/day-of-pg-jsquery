\c day_of_jsquery

-- List resources

SELECT content->'resourceType', count(*)
  FROM resources
  GROUP BY content->'resourceType'
  ORDER BY count(*);

-- select all patients

SELECT id, content->'name'
  FROM resources
 WHERE content @@ 'resourceType="Patient"';

-- find all Henries

SELECT id, content->'name'
  FROM resources
 WHERE content @@ $JSQ$
  (resourceType="Patient" AND name.#.given @> ["Henry"])
 $JSQ$;

-- find female
SELECT id
      ,content#>'{name}'
      ,content#>'{gender,coding}'
  FROM resources
 WHERE content @@ '(resourceType="Patient" AND gender.*.code = "F")';
