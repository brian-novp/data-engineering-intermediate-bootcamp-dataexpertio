-- create custom data type STRUCT to be used later
CREATE TYPE films as (
	film TEXT,
	votes INTEGER,
	rating REAL,
	filmid TEXT
);

-- create custom data type STRUCT to be used later
create type quality_class as
	enum('bad', 'average', 'good', 'star');

-- drop table if exist for idempotency
drop table if exists actors;

-- create table as per requirements
create table actors (
	actor TEXT,
	actorid TEXT,
	films films[],
	quality_class quality_class,
	is_active BOOLEAN,
	years_since_last_film INTEGER,
	current_year INTEGER,
	PRIMARY KEY(actor, current_year)
);

