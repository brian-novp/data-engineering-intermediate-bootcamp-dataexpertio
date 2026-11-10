# Apache Flink Homework

Answered using PyFlink and PosgreSQL

- Create a Flink job that sessionizes the input data by IP address and host. Use a 5 minute gap. Check [pyflink script](./flinkanswer.py) or see below.
  ```python
  from pyflink.datastream import StreamExecutionEnvironment
  from pyflink.table import EnvironmentSettings, StreamTableEnvironment
  import os
  import logging

  # configuring logging
  logging.basicConfig(level=logging.INFO, format="%(asctime)s [%(levelname)s] %(message)s")
  logger = logging.getLogger(__name__)

  def create_postgres_sink(t_env):
      sink_table_name = "sessionized_events"
      sink_ddl = f"""
          CREATE TABLE {sink_table_name} (
              ip VARCHAR,
              host VARCHAR,
              session_start TIMESTAMP(3),
              session_end TIMESTAMP(3),
              url_list VARCHAR(2048)
          ) WITH (
              'connector' = 'jdbc',
              'url' = '{os.environ.get("POSTGRES_URL")}',
              'table-name' = '{sink_table_name}',
              'username' = '{os.environ.get("POSTGRES_USER", "postgres")}',
              'password' = '{os.environ.get("POSTGRES_PASSWORD", "postgres")}',
              'driver' = 'org.postgresql.Driver'
          )
      """
      t_env.execute_sql(sink_ddl)
      return sink_table_name

  def create_sessionize_source_kafka(t_env):
      kafka_key = os.environ.get("KAFKA_WEB_TRAFFIC_KEY", "")
      kafka_secret = os.environ.get("KAFKA_WEB_TRAFFIC_SECRET", "")
      source_table_name = "events"
      pattern = "yyyy-MM-dd''T''HH:mm:ss.SSS''Z''"
      source_ddl = f"""
          CREATE TABLE {source_table_name} (
              url VARCHAR,
              referrer VARCHAR,
              user_agent VARCHAR,
              host VARCHAR,
              ip VARCHAR,
              headers VARCHAR,
              event_time VARCHAR,
              event_timestamp AS TO_TIMESTAMP(event_time, '{pattern}'),
              WATERMARK FOR event_timestamp AS event_timestamp - INTERVAL '15' SECOND
          ) WITH (
              'connector' = 'kafka',
              'properties.bootstrap.servers' = '{os.environ.get('KAFKA_URL')}',
              'topic' = '{os.environ.get('KAFKA_TOPIC')}',
              'properties.group.id' = '{os.environ.get('KAFKA_GROUP')}',
              'properties.security.protocol' = 'SASL_SSL',
              'properties.sasl.mechanism' = 'PLAIN',
              'properties.sasl.jaas.config' = 'org.apache.flink.kafka.shaded.org.apache.kafka.common.security.plain.PlainLoginModule required username=\"{kafka_key}\" password=\"{kafka_secret}\";',
              'scan.startup.mode' = 'latest-offset',
              'properties.auto.offset.reset' = 'latest',
              'format' = 'json'
          );
          """
      t_env.execute_sql(source_ddl)
      return source_table_name

  # running main function sessionize_web_traffic
  def sessionize_web_traffic():
      logger.info("Starting Flink sessionization job.")
      try:
          # Set up the execution environment
          env = StreamExecutionEnvironment.get_execution_environment()
          env.enable_checkpointing(10000)  # Enable checkpointing every 10 seconds

          # Set up the table environment
          settings = EnvironmentSettings.new_instance().in_streaming_mode().build()
          t_env = StreamTableEnvironment.create(env, environment_settings=settings)

          # Create Kafka source table
          source_table = create_sessionize_source_kafka(t_env)
          logger.info("Kafka source table created successfully.")

          # Create PostgreSQL sink table
          sink_table = create_postgres_sink(t_env)
          logger.info("PostgreSQL sink table created successfully.")

          # Define the sessionization query
          t_env.execute_sql(
              f"""
              INSERT INTO {sink_table}
              SELECT
                  ip,
                  host,
                  SESSION_START(event_timestamp, INTERVAL '5' MINUTE) AS session_start,
                  SESSION_END(event_timestamp, INTERVAL '5' MINUTE) AS session_end,
                  CAST(COLLECT(url) AS STRING) AS url_list
              FROM {source_table}
              GROUP BY SESSION(event_timestamp, INTERVAL '5' MINUTE), ip, host
              """
          ).wait()
          logger.info("Sessionization query executed successfully.")

      except Exception as e:
          logger.error("An error occurred during the Flink job execution:", exc_info=True)


  if __name__ == "__main__":
      sessionize_web_traffic()
  ```



- Answer these questions
  - What is the average number of web events of a session from a user on Tech Creator?
  - Compare results between different hosts (zachwilson.techcreator.io, zachwilson.tech, lulu.techcreator.io)

  See [sqlanswer.sql](sqlanswer.sql) or see below
  ```sql
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
  ```