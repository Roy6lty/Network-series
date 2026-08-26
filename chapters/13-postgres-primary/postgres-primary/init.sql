CREATE ROLE replicator WITH REPLICATION LOGIN PASSWORD 'replica_password';

CREATE TABLE users (
    id serial PRIMARY KEY,
    name text NOT NULL
);

INSERT INTO users (name) VALUES ('primary-seed');
