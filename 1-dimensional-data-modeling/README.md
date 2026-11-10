# Dimensional Data Modeling - Week 1

This week's assignment involves working with the `actor_films` dataset. Your task is to construct a series of SQL queries and table definitions that will allow us to model the actor_films dataset in a way that facilitates efficient analysis. This involves creating new tables, defining data types, and writing queries to populate these tables with data from the actor_films dataset

## Dataset Overview
The `actor_films` dataset contains the following fields:

- `actor`: The name of the actor.
- `actorid`: A unique identifier for each actor.
- `film`: The name of the film.
- `year`: The year the film was released.
- `votes`: The number of votes the film received.
- `rating`: The rating of the film.
- `filmid`: A unique identifier for each film.

The primary key for this dataset is (`actor_id`, `film_id`). Check [sql-ddl](./sql-ddl)

## Assignment Tasks

1. **DDL for `actors` table:** Create a DDL for an `actors` table with the following fields:
    - `films`: An array of `struct` with the following fields:
		- film: The name of the film.
		- votes: The number of votes the film received.
		- rating: The rating of the film.
		- filmid: A unique identifier for each film.

        ```sql
        -- create custom data type STRUCT to be used later
        CREATE TYPE films as (
            film TEXT,
            votes INTEGER,
            rating REAL,
            filmid TEXT
        );
        ```

    - `quality_class`: This field represents an actor's performance quality, determined by the average rating of movies of their most recent year. It's categorized as follows:
		- `star`: Average rating > 8.
		- `good`: Average rating > 7 and ≤ 8.
		- `average`: Average rating > 6 and ≤ 7.
		- `bad`: Average rating ≤ 6.
        ```sql
        -- create custom data type STRUCT to be used later
        create type quality_class as
        enum('bad', 'average', 'good', 'star');
        ```

    - `is_active`: A BOOLEAN field that indicates whether an actor is currently active in the film industry (i.e., making films this year).
        ```sql
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
        ```

    
    
2. **Cumulative table generation query:** Write a query that populates the `actors` table one year at a time.
    ```sql
    /*
    Zach ingested the data per year for just a few year.
    I wanted to ingest the full data but did not want to use manual ingestion per year.
    So I used loop in a function.
    Also added information summary result at the end like
    how many rows inserted per year and total rows inserted across all years. 
    */

    -- wrap the ingestion using a function for loop
    create or replace function ingest_years(
        start_year INTEGER,
        end_year INTEGER
    )
    returns text as $$
    declare
        current_year_val INTEGER;
        prev_year_val INTEGER;
        rows_inserted INTEGER;
        total_rows INTEGER := 0;
        result_msg TEXT := '';
    BEGIN
        -- Validate input parameters
        IF start_year > end_year THEN
            RAISE EXCEPTION 'Start year (%) cannot be greater than end year (%)', start_year, end_year;
        END IF;
        
        -- Loop through each year in the specified range
        FOR current_year_val IN start_year..end_year LOOP
            prev_year_val := current_year_val - 1;
            
            -- Check if previous year data exists (except for the first year)
            IF current_year_val > start_year THEN
                IF NOT EXISTS (SELECT 1 FROM actors WHERE current_year = prev_year_val) THEN
                    RAISE NOTICE 'Warning: No data found for previous year (%). Skipping year %', prev_year_val, current_year_val;
                    CONTINUE;
                END IF;
            END IF;
            
            -- Check if current year data already exists
            IF EXISTS (SELECT 1 FROM actors WHERE current_year = current_year_val) THEN
                RAISE NOTICE 'Data for year % already exists. Skipping...', current_year_val;
                CONTINUE;
            END IF;
            INSERT INTO actors
            with prev_year as (
                select * 
                from actors
                where current_year = prev_year_val
            ),
            c_year as (
                select
                af.actor,
                af.actorid,
                array_agg(row(af.film,votes,af.rating,af.filmid)::films) as films,
                avg(af.rating) as quality,
                af.year
                from actor_films af
                where af.year =current_year_val
                group by af.actor,af.actorid,af.year
            )
            SElECT 
                coalesce(c.actor, p.actor) as actor,
                coalesce(c.actorid, p.actorid) as actorid,
                CASE
                    WHEN p.films is NULL
                    THEN c.films
                    else
                        case
                            when c.films is not null then
                                p.films || c.films
                            else p.films
                    end
                end as films,
                case
                    when c.quality is not null then
                        case
                            when c.quality > 8.0 then 'star'
                            when c.quality > 7.0 then 'good'
                            when c.quality > 6.0 then 'average'
                            else 'bad'
                        end::quality_class
                else quality_class
                end as quality_class,
                c.year is not null as is_active,
                case
                    when c.year is not null then 0
                    else p.years_since_last_film + 1
                end as years_since_last_film,
                coalesce(c.year, p.current_year::integer+1) as current_year
            FROM c_year c
            FULL OUTER JOIN prev_year p
                ON c.actor = p.actor;
        
            -- Get the number of rows inserted
            GET DIAGNOSTICS rows_inserted = ROW_COUNT;
            total_rows := total_rows + rows_inserted;
            
            result_msg := result_msg || 'Year ' || current_year_val || ': ' || rows_inserted || ' rows inserted; ' || chr(10);
            
            RAISE NOTICE 'Processed year %: % rows inserted', current_year_val, rows_inserted;
        END LOOP;
        
        result_msg := result_msg || chr(10) || 'Total: ' || total_rows || ' rows inserted across all years.';
        RETURN result_msg;
        
    EXCEPTION
        WHEN OTHERS THEN
            RAISE EXCEPTION 'Error processing year %: %', current_year_val, SQLERRM;
    END;
    $$ LANGUAGE plpgsql;

    -- perform the function to ingest data year by year
    SELECT ingest_years(1970,2001);

    ```
    
3. **DDL for `actors_history_scd` table:** Create a DDL for an `actors_history_scd` table with the following features:
    - Implements type 2 dimension modeling (i.e., includes `start_date` and `end_date` fields).
    - Tracks `quality_class` and `is_active` status for each actor in the `actors` table.
    ```sql
    drop table if exists actors_history_scd;

    create table actors_history_scd (
        actorid text,                          
        quality_class quality_class,           
        is_active boolean,                      
        start_date integer,                     
        end_date integer,                       
        is_current boolean default true,       
        primary key (actorid, start_date)      
    );

    ```  

4. **Backfill query for `actors_history_scd`:** Write a "backfill" query that can populate the entire `actors_history_scd` table in a single query.
    ```sql
    insert into actors_history_scd
    select
        actorid,                               
        quality_class,                         
        is_active,                             
        min(current_year) as start_date,               
        lead(current_year, 1, 9999) over (             
            partition by actorid               
            order by current_year                      
        ) - 1 as end_date,                      
        case                                  
            when lead(current_year, 1) over (
                    partition by actorid
                    order by current_year
                ) is null then true
            else false
        end as is_current
    from actors
    group by 1, 2, 3, current_year
    order by actorid, start_date;
    ```

5. **Incremental query for `actors_history_scd`:** Write an "incremental" query that combines the previous year's SCD data with new incoming data from the `actors` table.
    ```sql    
    insert into actors_history_scd
        select
            a.actorid,
            a.quality_class,
            a.is_active,
            a.current_year as start_date,
            9999 as end_date,
            true as is_current
        from actors a
        left join actors_history_scd scd
            on a.actorid = scd.actorid
            and scd.is_current = true 
        where
            (scd.actorid is null) 
            or (scd.quality_class <> a.quality_class 
                or scd.is_active <> a.is_active); 

    update actors_history_scd
        set end_date = a.current_year - 1, 
            is_current = false 
        from actors a
        where actors_history_scd.actorid = a.actorid
            and actors_history_scd.is_current = true 
            and (actors_history_scd.quality_class <> a.quality_class
                or actors_history_scd.is_active <> a.is_active);
    ```
