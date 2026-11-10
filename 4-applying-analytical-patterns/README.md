# Week 4 Applying Analytical Patterns
The homework this week will be using the `players`, `players_scd`, and `player_seasons` tables from week 1. For preparation, see [prep.sql](./sql-answer/prep.sql)

- A query that does state change tracking for `players`
  - A player entering the league should be `New`
  - A player leaving the league should be `Retired`
  - A player staying in the league should be `Continued Playing`
  - A player that comes out of retirement should be `Returned from Retirement`
  - A player that stays out of the league should be `Stayed Retired`
  
  see [q1-state-change-tracking.sql](./sql-answer/q1-state-change-tracking.sql) or below
  ```sql
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

  ```


- A query that uses `GROUPING SETS` to do efficient aggregations of `game_details` data
  - Aggregate this dataset along the following dimensions
    - player and team
      - Answer questions like who scored the most points playing for one team?
    - player and season
      - Answer questions like who scored the most points in one season?
    - team
      - Answer questions like which team has won the most games?
  
  see [q2-grouping-agg-gamedetails.sql](./sql-answer/q2-grouping-agg-gamedetails.sql) or below
  ```sql
  -- Aggregating data from two tables: games and game_details
  CREATE TABLE game_points_dashboard AS
  WITH games_augmented AS (
      SELECT player_name,
            team_abbreviation,
            team_city,
            COALESCE(pts, 0) AS pts,
            COALESCE(g.season, 0) AS season,
            CASE
                WHEN gd.team_id = g.home_team_id AND home_team_wins = 1 THEN gd.game_id
                WHEN gd.team_id = g.visitor_team_id AND home_team_wins = 0 THEN gd.game_id
            END AS game_id_won
      FROM game_details gd
              JOIN games g on gd.game_id = g.game_id
  )
  SELECT
        CASE
            WHEN GROUPING(player_name) = 0
                      AND GROUPING(team_city) = 0
                THEN 'player_name__team_city'
            WHEN GROUPING(player_name) = 0
                      AND GROUPING(season) = 0
                THEN 'player_name__season'
            WHEN GROUPING(team_city) = 0
                      AND GROUPING(team_abbreviation) = 0
                THEN 'team_city__abbreviation'
        END as aggregation_level,
        COALESCE(player_name, '(overall)') as player_name,
        COALESCE(team_abbreviation, '(overall)') as team_abbreviation,
        COALESCE(team_city, '(overall)') as team_city,
        season,
        SUM(pts) AS total_points,
        COUNT(DISTINCT game_id_won) AS total_wins
  FROM games_augmented
  GROUP BY GROUPING SETS (
    (player_name, team_city),
    (player_name, season),
    (team_city, team_abbreviation)
  );

  -- DROP TABLE game_points_dashboard;

  SELECT * FROM game_points_dashboard;

  -- Q1: Who scored the most points playing for one team?
  SELECT
      aggregation_level,
      player_name,
      team_city,
      total_points
  FROM game_points_dashboard
  WHERE aggregation_level = 'player_name__team_city'
  ORDER BY total_points DESC
  LIMIT 1;

  -- Q2: Who scored the most points in one season?
  SELECT
      aggregation_level,
      player_name,
      season,
      total_points
  FROM game_points_dashboard
  WHERE aggregation_level = 'player_name__season'
  ORDER BY total_points DESC
  LIMIT 1;

  -- Q3: Which team has won the most games?
  SELECT
      aggregation_level,
      team_abbreviation,
      team_city,
      total_wins
  FROM game_points_dashboard
  WHERE aggregation_level = 'team_city__abbreviation'
  ORDER BY total_wins DESC
  LIMIT 1;
  ```
- A query that uses window functions on `game_details` to find out the following things:
  - What is the most games a team has won in a 90 game stretch? 
  - How many games in a row did LeBron James score over 10 points a game?
  
  see [q3-windowfunction.sql](./sql-answer/q3-windowfunction.sql) or below
  ```sql
  -- Q4: What is the most games a team has won in a 90 game stretch?
  WITH team_results AS (
      SELECT
          gd.game_id,
          gd.team_id,
          gd.team_abbreviation,
          g.game_date_est,
          CASE
              WHEN gd.team_id = g.home_team_id AND g.home_team_wins = 1 THEN 1
              WHEN gd.team_id = g.visitor_team_id AND g.home_team_wins = 0 THEN 1
              ELSE 0
          END AS game_wins
      FROM game_details gd
      JOIN games g ON gd.game_id = g.game_id
  ),
  team_games AS (
      SELECT
          game_id,
          team_id,
          team_abbreviation,
          game_date_est,
          game_wins,
          ROW_NUMBER() OVER
              (PARTITION BY team_id
              ORDER BY game_date_est) AS game_number
      FROM team_results
      GROUP BY game_id, team_id, team_abbreviation, game_date_est, game_wins
  ),
  rolling_wins AS (
      SELECT
          t1.team_id,
          t1.team_abbreviation,
          t1.game_number,
          SUM(t2.game_wins) AS wins_in_90_games
      FROM
          team_games t1
      JOIN
          team_games t2
      ON
          t1.team_id = t2.team_id
          AND t2.game_number BETWEEN t1.game_number AND t1.game_number + 89
      GROUP BY
          t1.team_id, t1.team_abbreviation, t1.game_number
  )
  SELECT
      team_id,
      team_abbreviation,
      MAX(wins_in_90_games) AS max_wins_in_90_games
  FROM
      rolling_wins
  GROUP BY
      team_id, team_abbreviation
  ORDER BY
      max_wins_in_90_games DESC
  LIMIT 1;

  -- Q5: How many games in a row did LeBron James score over 10 points a game?
  WITH starter AS (
  SELECT g.game_date_est,
        player_name,
        team_id,
        team_abbreviation,
        pts,
            CASE
                WHEN pts > 10 THEN 1
                ELSE 0
            END AS scored_over_10
      FROM game_details gd
              JOIN games g on gd.game_id = g.game_id
      WHERE player_name = 'LeBron James'
  ),
  lagged AS (
  SELECT
      *,
      LAG(scored_over_10) OVER (PARTITION BY player_name ORDER BY game_date_est) AS scored_over_10_before
  FROM starter
  ),
  streak_change AS (
  SELECT
      *,
      CASE WHEN scored_over_10 <> scored_over_10_before THEN 1 ELSE 0 END as streak_changed
  FROM lagged
  ),
  streak_identified AS (
      SELECT *,
            SUM(streak_changed) OVER (PARTITION BY player_name ORDER BY game_date_est) AS streak_identifier
      FROM streak_change
  ),
  record_counts AS (
      SELECT *,
            ROW_NUMBER() OVER (PARTITION BY player_name, streak_identifier ORDER BY game_date_est) AS streak_length
      FROM streak_identified
      WHERE scored_over_10 = 1 -- учитывать только игры с более чем 10 очками
      ),
  ranked AS (
  SELECT *,
        MAX(streak_length) OVER (PARTITION BY player_name, streak_identifier) AS max_streak_length
  FROM record_counts
  )
  SELECT DISTINCT
      player_name,
      max_streak_length AS longest_streak
  FROM ranked
  ORDER BY longest_streak DESC
  LIMIT 1;
  ```