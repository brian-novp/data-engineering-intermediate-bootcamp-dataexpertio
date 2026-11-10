-- SELECT ip,
--        event_timestamp,
--        referrer,
--        host,
--        url,
--        geodata
-- FROM public.processed_events;

-- DROP TABLE sessionized_events

-- CREATE TABLE sessionized_events (
--     ip VARCHAR,
--     host VARCHAR,
--     SESSION_START TIMESTAMP(3),
--     SESSION_END TIMESTAMP(3),
--     url_list TEXT
-- );
SELECT *
FROM public.sessionized_events


-- Q1: Calculate the average number of web events per session for users on Tech Creator
-- The query filters sessions where the host includes 'techcreator.io' and calculates the average number of events per session
-- by splitting the 'url_list' string into an array and counting its elements.
SELECT
    host,
    AVG(array_length(string_to_array(url_list, ','), 1)) AS avg_events_per_session
FROM sessionized_events
WHERE host LIKE '%techcreator.io' -- Filtering by Tech Creator host
GROUP BY host;


-- Q2: Compare the average number of web events per session across specific hosts
-- The query focuses on sessions from three specific hosts and calculates the average number of events per session.
-- Results are ordered in descending order of average events per session)
SELECT
    host,
    AVG(array_length(string_to_array(url_list, ','), 1)) AS avg_events_per_session
FROM sessionized_events
WHERE host IN ('zachwilson.techcreator.io', 'zachwilson.tech', 'lulu.techcreator.io')
GROUP BY host
ORDER BY avg_events_per_session DESC;