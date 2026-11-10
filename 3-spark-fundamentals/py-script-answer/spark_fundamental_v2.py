from pyspark.sql import SparkSession
from pyspark.sql.functions import broadcast, col, avg, sum, count, desc, row_number
from pyspark.sql.window import Window

def main():
    # =========================================================================
    # Initialize Spark Session with optimizations
    # =========================================================================
    spark = SparkSession.builder \
        .appName("HaloDataAnalysis") \
        .config("spark.sql.autoBroadcastJoinThreshold", "-1") \  # Disable auto-broadcast
        .config("spark.sql.shuffle.partitions", "200") \         # Control shuffle partitions
        .getOrCreate()

    # =========================================================================
    # Load CSV files with inferred schemas
    # =========================================================================
    # medals: Medal metadata (small dimension table)
    medals = spark.read.csv("medal.csv", header=True, inferSchema=True)
    
    # maps: Map metadata (small dimension table)
    maps = spark.read.csv("maps.csv", header=True, inferSchema=True)
    
    # match_details: Player performance per match (large fact table)
    match_details = spark.read.csv("match_details.csv", header=True, inferSchema=True)
    
    # matches: Match metadata (medium fact table)
    matches = spark.read.csv("matches.csv", header=True, inferSchema=True)
    
    # medals_players: Medal counts per player per match (large fact table)
    medals_players = spark.read.csv("medals_matches_players.csv", header=True, inferSchema=True)

    # =========================================================================
    # Bucketing Configuration
    # =========================================================================
    num_buckets = 16  # Optimal bucket count based on cluster size
    
    # Bucket match_details on match_id (large table with player-match granularity)
    # Sorting by player_gamertag improves player-based aggregations
    match_details.write \
        .bucketBy(num_buckets, "match_id") \
        .sortBy("player_gamertag") \
        .saveAsTable("match_details_bucketed", format="parquet", mode="overwrite")
    
    # Bucket matches on match_id (medium table with match granularity)
    # Sorting by playlist_id improves playlist-based aggregations
    matches.write \
        .bucketBy(num_buckets, "match_id") \
        .sortBy("playlist_id") \
        .saveAsTable("matches_bucketed", format="parquet", mode="overwrite")
    
    # Bucket medals_players on match_id (large table with medal-player-match granularity)
    # Sorting by medal_id improves medal-based aggregations
    medals_players.write \
        .bucketBy(num_buckets, "match_id") \
        .sortBy("medal_id") \
        .saveAsTable("medals_players_bucketed", format="parquet", mode="overwrite")

    # =========================================================================
    # Reload Bucketed Tables for Optimized Joins
    # =========================================================================
    match_details_b = spark.table("match_details_bucketed")
    matches_b = spark.table("matches_bucketed")
    medals_players_b = spark.table("medals_players_bucketed")

    # =========================================================================
    # Broadcast Small Dimension Tables
    # =========================================================================
    medals_bc = broadcast(medals)  # ~1.5KB - ideal for broadcast
    maps_bc = broadcast(maps)      # ~500B - ideal for broadcast

    # =========================================================================
    # Create Base Joined Dataset with Optimized Joins
    # =========================================================================
    # 1. Join match metadata with player performance using bucketed tables (no shuffle)
    # 2. Join with medal counts using bucketed tables (no shuffle)
    # 3. Broadcast join with medal metadata
    # 4. Broadcast join with map metadata
    base_joined = matches_b \
        .join(match_details_b, "match_id") \
        .join(medals_players_b, ["match_id", "player_gamertag"]) \
        .join(medals_bc, "medal_id") \
        .join(maps_bc, "mapid")

    # =========================================================================
    # Question 1: Player with Highest Average Kills Per Game
    # =========================================================================
    # Why deduplicate? - The join with medals creates multiple rows per player per match
    # Create window to identify first row per player per match
    player_window = Window.partitionBy("player_gamertag", "match_id").orderBy(col("medal_id"))
    
    # Deduplicate to get one row per player per match
    distinct_kills = base_joined.withColumn("rn", row_number().over(player_window)) \
        .filter(col("rn") == 1) \
        .drop("rn")
    
    # Calculate average kills across all matches per player
    avg_kills = distinct_kills.groupBy("player_gamertag") \
        .agg(avg("player_total_kills").alias("avg_kills")) \
        .orderBy(desc("avg_kills")) \
        .limit(1)

    # =========================================================================
    # Question 2: Most Played Playlist
    # =========================================================================
    # Directly aggregate from matches table (most efficient source)
    playlist_count = matches_b.groupBy("playlist_id") \
        .agg(count("*").alias("total_matches")) \
        .orderBy(desc("total_matches")) \
        .limit(1)

    # =========================================================================
    # Question 3: Most Played Map
    # =========================================================================
    # Join matches with broadcasted maps for name lookup
    map_count = matches_b.join(maps_bc, "mapid") \
        .groupBy("mapid", "name") \
        .agg(count("*").alias("total_matches")) \
        .orderBy(desc("total_matches")) \
        .limit(1)

    # =========================================================================
    # Question 4: Map with Most Killing Spree Medals
    # =========================================================================
    # Filter for Killing Spree medals first to reduce data volume
    killing_spree = base_joined.filter(col("name") == "Killing Spree") \
        .groupBy("mapid", "maps.name") \
        .agg(sum("count").alias("total_medals")) \
        .orderBy(desc("total_medals")) \
        .limit(1)

    # =========================================================================
    # SortWithinPartitions Experiment
    # =========================================================================
    # Test different sorting strategies to minimize storage size
    # Strategy 1: Sort by playlist_id (lowest cardinality)
    sorted_by_playlist = base_joined.sortWithinPartitions("playlist_id")
    
    # Strategy 2: Sort by mapid (medium cardinality)
    sorted_by_map = base_joined.sortWithinPartitions("mapid")
    
    # Strategy 3: Sort by both columns (compound key)
    sorted_by_combo = base_joined.sortWithinPartitions("playlist_id", "mapid")
    
    # Write to disk to compare physical sizes
    sorted_by_playlist.write.mode("overwrite").parquet("sorted_by_playlist")
    sorted_by_map.write.mode("overwrite").parquet("sorted_by_map")
    sorted_by_combo.write.mode("overwrite").parquet("sorted_by_combo")

    # =========================================================================
    # Display Results
    # =========================================================================
    print("Player with highest average kills:")
    avg_kills.show()
    
    print("\nMost played playlist:")
    playlist_count.show()
    
    print("\nMost played map:")
    map_count.show()
    
    print("\nMap with most Killing Spree medals:")
    killing_spree.show()

    # =========================================================================
    # Cleanup
    # =========================================================================
    spark.stop()

if __name__ == "__main__":
    main()