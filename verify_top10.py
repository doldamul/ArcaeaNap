from db_utils import get_top_10_most_played
import json
import os

# Ensure we are in correct dir for db_utils to find config
os.chdir(os.path.dirname(os.path.abspath(__file__)))

print("Fetching Top 10 Most Played...")
try:
    results = get_top_10_most_played()
    print(f"Found {len(results)} songs.")
    print(json.dumps(results, indent=2, ensure_ascii=False))
except Exception as e:
    print(f"Error: {e}")
