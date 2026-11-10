DROP FUNCTION IF EXISTS process_players_growth_accounting;
CREATE OR REPLACE FUNCTION process_players_growth_accounting(
    start_year INTEGER,
    end_year INTEGER
)
RETURNS TABLE(
    processing_year INTEGER,
    rows_ingested BIGINT
) 
LANGUAGE plpgsql
AS $$
DECLARE
    current_year INTEGER;
    row_count BIGINT;
BEGIN
    -- Loop through each year from start_year to end_year
    FOR current_year IN start_year..end_year LOOP
        
        -- Insert data for the current year
        INSERT INTO players_growth_accounting
        WITH previous_season AS (
            SELECT * FROM players_growth_accounting
            WHERE current_season = current_year - 1
        ),
        current_season AS (
            SELECT
                player_name,
                season,
                COUNT(1)
            FROM player_seasons
            WHERE season = current_year
                AND player_name IS NOT NULL
            GROUP BY player_name, season
        )
        SELECT
            COALESCE(cs.player_name, ps.player_name) AS player_name,
            COALESCE(ps.first_active_year, cs.season) AS first_active_year,
            COALESCE(cs.season, ps.last_active_year) AS last_active_year,
            CASE
                WHEN ps.player_name IS NULL AND cs.player_name IS NOT NULL THEN 'New'
                WHEN ps.player_name IS NOT NULL AND cs.player_name IS NULL THEN 'Retired'
                WHEN ps.player_name IS NOT NULL AND cs.player_name IS NOT NULL THEN 'Continued Playing'
                WHEN ps.player_name IS NOT NULL AND ps.last_active_year < cs.season - 1 THEN 'Returned from Retirement'
                WHEN ps.player_name IS NOT NULL AND cs.player_name IS NULL AND ps.last_active_year < ps.current_season THEN 'Stayed Retired'
                ELSE 'Unknown'
            END as active_state,
            COALESCE(ps.years_active, ARRAY[]::INTEGER[])
                || CASE WHEN
                    cs.player_name IS NOT NULL
                    THEN ARRAY[cs.season]
                    ELSE ARRAY[]::INTEGER[]
                END AS years_active,
            COALESCE(cs.season, ps.current_season + 1) AS current_season
        FROM current_season cs
        FULL OUTER JOIN previous_season ps
            ON cs.player_name = ps.player_name;
        
        -- Get the number of rows inserted
        GET DIAGNOSTICS row_count = ROW_COUNT;
        
        -- Return the year and row count
        processing_year := current_year;
        rows_ingested := row_count;
        RETURN NEXT;
        
    END LOOP;
    
    RETURN;
END;
$$;