#!/usr/bin/env bash
# =============================================================================
# run.sh  –  Build & run the Hadoop Inverted Index
# =============================================================================
set -euo pipefail

# ------------- configuration (edit as needed) --------------------------------
HDFS_INPUT="/input"
HDFS_OUTPUT="/output"
STOPWORDS_LOCAL="stopwords.txt"
STOPWORDS_HDFS="/stopwords.txt"
BOOKS_DIR="./books"          # local directory that holds *.txt books
JAR="invertedindex.jar"
# -----------------------------------------------------------------------------

echo "=== [1/5] Compiling InvertedIndex.java ==="
javac -cp "$(hadoop classpath)" InvertedIndex.java
jar cf "$JAR" InvertedIndex*.class
echo "    → $JAR built."

echo "=== [2/5] Uploading stop-words to HDFS ==="
hadoop fs -test -e "$STOPWORDS_HDFS" && hadoop fs -rm "$STOPWORDS_HDFS" || true
hadoop fs -put "$STOPWORDS_LOCAL" "$STOPWORDS_HDFS"
echo "    → $STOPWORDS_HDFS uploaded."

echo "=== [3/5] Uploading books to HDFS ==="
hadoop fs -rm -r -f "$HDFS_INPUT"
hadoop fs -mkdir -p "$HDFS_INPUT"
for f in "$BOOKS_DIR"/*.txt; do
    hadoop fs -put "$f" "$HDFS_INPUT/"
    echo "    → uploaded: $(basename "$f")"
done

echo "=== [4/5] Removing old output (if any) ==="
hadoop fs -rm -r -f "$HDFS_OUTPUT"

echo "=== [5/5] Running MapReduce job ==="
hadoop jar "$JAR" InvertedIndex \
    --stopwords "hdfs:///$STOPWORDS_HDFS" \
    "$HDFS_INPUT" "$HDFS_OUTPUT"

echo ""
echo "=== Done! Showing first 30 lines of output ==="
hadoop fs -cat "$HDFS_OUTPUT/part-r-00000" | head -30
