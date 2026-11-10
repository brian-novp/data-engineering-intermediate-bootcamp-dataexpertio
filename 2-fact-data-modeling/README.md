# Week 2 Fact Data Modeling
The homework this week will be using the `devices` and `events` dataset. Check [tables](./tables/)

Construct the following eight queries:

- A query to deduplicate `game_details` from Day 1 so there's no duplicates
  ```sql
  -- create CTE to get needed column with row number
  with dedup as (
  select
      g.game_date_est,
      g.season,
      g.home_team_id,
      gd.*,
      row_number() over (partition by gd.game_id, team_id, player_id ORDER BY g.game_date_est) as row_num
  from game_details gd
      JOIN games g
      ON gd.game_id = g.game_id

  )

  select *
  FROM dedup
  WHERE row_num > 1
  -- select the required column and use row_number = 1 in the where clause to eliminate duplicates
  Select
      game_date_est as dim_game_date,
      season as dim_season,
      team_id as dim_team_id,
      player_id as dim_player_id,
      player_name as dim_player_name,
      start_position as dim_start_position,
      team_id = home_team_id as dim_playing_home,
      COALESCE(POSITION('DNP' in "comment"), 0) > 0 as dim_did_not_play,
      COALESCE(POSITION('DND' in "comment"), 0) > 0 as dim_did_not_dress,
      COALESCE(POSITION('NWT' in "comment"), 0) > 0 as dim_not_with_team,
      CAST(SPLIT_PART("min", ':', 1) as REAL)
      + CAST(SPLIT_PART("min", ':', 2) as real)/60 as m_minutes,
      fgm as m_fgm,
      fga as m_fga,
      fg3m as m_fg3m,
      fg3a as m_fg3a,
      ftm as m_ftm,
      fta as m_fta,
      oreb as m_oreb,
      dreb as m_dreb,
      reb as m_reb,
      ast as m_ast,
      stl as m_stl,
      blk as m_blk,
      "TO" as m_turnovers,
      pf as m_pf,
      pts as m_pts,
      plus_minus as m_plus_minus
  from dedup
  where row_num = 1;

  ```

- A DDL for an `user_devices_cumulated` table that has:
  - a `device_activity_datelist` which tracks a users active days by `browser_type`
  - data type here should look similar to `MAP<STRING, ARRAY[DATE]>`
    - or you could have `browser_type` as a column with multiple rows for each user (either way works, just be consistent!)
  ```sql
  -- drop table if exist command
  drop table if EXISTS user_devices_cumulated;

  -- create table using the necessary columns
  create table user_devices_cumulated (
      -- user_id as identifier
      user_id TEXT,
      -- device_id needed to join
      -- device_id NUMERIC,
      -- browser_type column to track users' active days
      browser_type TEXT,
      -- list of dates on the past where the user was active
      device_activity_datelist DATE[],
      -- the current date for the user
      date DATE,
      PRIMARY KEY (user_id, browser_type,date)
  )

  SELECT *
  FROM user_devices_cumulated

  -- query 3
  -- A cumulative query to generate device_activity_datelist from events

  -- using left join because 'events' table is the master fact table
  WITH dataset AS (
  SELECT
      e.user_id AS user_id,
      e.device_id as device_id,
      d.browser_type as browser_type,
      CAST(event_time AS TIMESTAMP) AS event_time    
  FROM events e
  LEFT JOIN devices d
  ON e.device_id = d.device_id
  )

  SELECT
      *,
      -- assign row number over all the columns to make sure whether duplicates exist
      row_number() over (partition by user_id, device_id, browser_type, event_time) as row_num
  FROM dataset
  ```

- A cumulative query to generate `device_activity_datelist` from `events`
  ```sql
  drop table if EXISTS user_devices_cumulated;

  -- create table using the necessary columns
  create table user_devices_cumulated (
      -- user_id as identifier
      user_id TEXT,
      -- browser_type column to track users' active days
      browser_type TEXT,
      -- list of dates on the past where the user was active
      device_activity_datelist DATE[],
      -- the current date for the user
      date DATE,
      PRIMARY KEY (user_id,browser_type, date)
  );
  -- cumulative query using plpgsql for loop specified date
  CREATE OR REPLACE FUNCTION user_devices_cumulated(
      start_date DATE DEFAULT '2023-01-01',
      end_date DATE DEFAULT '2023-01-31'
  )
  RETURNS TABLE(
      process_date DATE,
      rows_ingested INTEGER,
      status TEXT,
      error_message TEXT
  ) 
  LANGUAGE plpgsql
  AS $$
  DECLARE
      processing_date DATE;
      yesterday_date DATE;
      rows_affected INTEGER;
      error_msg TEXT;
  BEGIN
      -- Validate input dates
      IF start_date >= end_date THEN
          RAISE EXCEPTION 'Start date must be before end date';
      END IF;
      
      -- Loop through each date in the range
      FOR processing_date IN SELECT generate_series(start_date, end_date, '1 day'::interval)::DATE
      LOOP
          BEGIN
              -- Calculate yesterday's date
              yesterday_date := processing_date - INTERVAL '1 day';
              
              -- Execute the main query with dynamic dates
              WITH yesterday AS (
                  SELECT
                      *
                  FROM user_devices_cumulated
                  WHERE date = yesterday_date
              ),
              today AS (
                  SELECT
                      CAST(user_id AS TEXT) as user_id,
                      e.device_id,
                      d.browser_type,
                      DATE(CAST(event_time AS TIMESTAMP)) as date_active
                  FROM events e
                  LEFT JOIN devices d
                  ON e.device_id = d.device_id
                  WHERE
                      DATE(CAST(event_time AS TIMESTAMP)) = processing_date
                      AND user_id IS NOT NULL
                      AND e.device_id IS NOT NULL
                      AND d.browser_type IS NOT NULL
                  -- GROUP BY user_id, e.device_id, d.browser_type, DATE(CAST(event_time as TIMESTAMP))
              ),
              stg AS (
                  SELECT
                      COALESCE(t.user_id, y.user_id) AS user_id,
                      COALESCE(t.browser_type, y.browser_type) AS browser_type,
                      CASE
                          WHEN y.device_activity_datelist IS NULL AND t.date_active IS NOT NULL
                              THEN ARRAY[t.date_active]
                              WHEN t.date_active IS NULL AND y.device_activity_datelist IS NOT NULL
                                  THEN y.device_activity_datelist
                              WHEN t.date_active IS NOT NULL AND y.device_activity_datelist IS NOT NULL
                              THEN ARRAY[t.date_active]||y.device_activity_datelist
                          ELSE
                              y.device_activity_datelist
                      END AS device_activity_datelist,
                      COALESCE(t.date_active, y.date + INTERVAL '1 DAY') as date

                  FROM today t
                  FULL OUTER JOIN yesterday y
                      ON t.user_id = y.user_id
                      AND t.browser_type = y.browser_type
                  where COALESCE(t.user_id, y.user_id) IS NOT NULL
                  AND COALESCE(t.browser_type, y.browser_type) IS NOT NULL
              )
              INSERT INTO user_devices_cumulated 
              SELECT
                  user_id,
                  browser_type,
                  device_activity_datelist,
                  date
              FROM stg
              GROUP BY 1,2,3,4;

              GET DIAGNOSTICS rows_affected = ROW_COUNT;
              
              -- Return success information
              process_date := processing_date;
              rows_ingested := rows_affected;
              status := 'SUCCESS';
              error_message := NULL;
              
              RETURN NEXT;
              
              -- Log progress (optional - comment out if not needed)
              RAISE NOTICE 'Processed date % - ingested % rows', processing_date, rows_affected;
              
          EXCEPTION
              WHEN OTHERS THEN
                  -- Capture error details
                  error_msg := SQLERRM;
                  
                  -- Return error information
                  process_date := processing_date;
                  rows_ingested := 0;
                  status := 'ERROR';
                  error_message := error_msg;
                  
                  RETURN NEXT;
                  
                  -- Log the error
                  RAISE NOTICE 'Error processing date %: %', processing_date, error_msg;
                  
                  -- Continue to next iteration instead of stopping
                  CONTINUE;
          END;
      END LOOP;
      
      RETURN;
  END;
  $$;

  SELECT user_devices_cumulated('2023-01-01','2023-01-31');
  ```
- A `datelist_int` generation query. Convert the `device_activity_datelist` column into a `datelist_int` column 
  ```sql
  -- datelist_int generation query.
  -- Convert device_activity_datelist column into a datelist_int column
  -- datelist_int means bitwise

  -- create CTE from user_devices_cumulated to be CROSS JOINed
  with users_cumul AS (
      SELECT 
      *
      FROM user_devices_cumulated
      where date = DATE('2023-01-31')
  ),
  -- create series CTE that has a range of date
      series AS (
          SELECT 
          *
          FROM generate_series (DATE('2023-01-01'),DATE('2023-01-31'), INTERVAL '1 DAY') as series_date
  ),
  -- create place_int CTE to calculate the int value from the device_activity_datelist
      place_int AS (
      SELECT
          *,
          CASE
              WHEN device_activity_datelist @> ARRAY[DATE(series_date)]
              THEN CAST(POW(2, 32 - (date - DATE(series_date))) as BIGINT)
              ELSE 0
          END as placeholder_int
      FROM users_cumul 
      CROSS JOIN series
  )
  -- main query, pick the required column, SUM the int_value and CAST it as BIT32
      SELECT
      user_id,
      browser_type,
      CAST(CAST(SUM(placeholder_int) as BIGINT) as BIT(32)) AS datelist_int
      FROM place_int
      GROUP BY 1,2
  ```
- A DDL for `hosts_cumulated` table 
  - a `host_activity_datelist` which logs to see which dates each host is experiencing any activity
  ```sql
  CREATE TABLE hosts_cumulated (
  host TEXT,
  host_activity_datelist DATE[],
  date DATE,
  PRIMARY KEY (host, date)
  );
  ```
  
- The incremental query to generate `host_activity_datelist`
  ```sql
  -- The incremental query to generate host_activity_datelist
  INSERT INTO hosts_cumulated
  WITH activity_dates AS (
      SELECT
          host,
          DATE(CAST(event_time AS TIMESTAMP)) AS activity_date -- Convert event_time to date
      FROM events
      WHERE event_time IS NOT NULL
  )
  SELECT
      host,
      ARRAY_AGG(DISTINCT activity_date ORDER BY activity_date) AS host_activity_datelist,
      MAX(activity_date) AS date
  FROM activity_dates
  GROUP BY host;
  ```
- A monthly, reduced fact table DDL `host_activity_reduced`
   - month
   - host
   - hit_array - think COUNT(1)
   - unique_visitors array -  think COUNT(DISTINCT user_id)
   ```sql
   --A monthly, reduced fact table DDL host_activity_reduced
  CREATE TABLE host_activity_reduced (
      -- The month for aggregation
      month DATE,
      -- The host identifier 
      host TEXT,
      -- Count of total hits
      hit_array INT,
      -- Count of unique users
      unique_visitors TEXT[],
      -- Ensure uniqueness of each host per month
      PRIMARY KEY (month, host)       
  );
   ```

- An incremental query that loads `host_activity_reduced`
  - day-by-day
  ```sql
  INSERT INTO host_activity_reduced
  WITH activity_data AS (
      SELECT
      -- month from event_time
          DATE_TRUNC('month', CAST(event_time AS TIMESTAMP)) AS month,  host,
          user_id
      FROM events
      WHERE event_time IS NOT NULL
  ),
  host_months AS (
      -- Generate a list of all possible host-month combinations
      SELECT DISTINCT
          DATE_TRUNC('month', CAST(event_time AS TIMESTAMP)) AS month,
          host
      FROM events
      WHERE event_time IS NOT NULL
  ),
  aggregated_data AS (
      SELECT
          hm.month,
          hm.host,
          -- Count total events for the month-host
          COUNT(ad.user_id) AS hit_array,
           -- Unique visitors for the month-host
          ARRAY_AGG(DISTINCT ad.user_id) AS unique_visitors
      FROM host_months hm
      LEFT JOIN activity_data ad
          ON hm.month = ad.month AND hm.host = ad.host
      GROUP BY hm.month, hm.host
  )
  SELECT
      month,
      host,
      -- Default to 0 hits for missing data
      COALESCE(hit_array, 0) AS hit_array,  
      -- Default to empty array for visitors
      COALESCE(unique_visitors, ARRAY[]::BIGINT[]) AS unique_visitors 
  FROM aggregated_data;
  ```
