create database day_of_jsquery;
\c day_of_jsquery
-- you can use psql autocompletition
-- start printing name of database or command and press tab

create extension jsquery;
create extension pgcrypto;

CREATE TABLE resources (
  id uuid primary key default gen_random_uuid(),
  content jsonb
);
