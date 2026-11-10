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