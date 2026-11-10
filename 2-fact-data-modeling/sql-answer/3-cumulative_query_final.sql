-- ========================USE THIS=====================
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