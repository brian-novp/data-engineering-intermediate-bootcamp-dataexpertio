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