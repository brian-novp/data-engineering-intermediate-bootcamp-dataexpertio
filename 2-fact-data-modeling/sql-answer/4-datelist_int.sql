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