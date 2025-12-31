from db_utils import calculate_user_stats
import os

# Ensure we are in correct dir for db_utils to find config
os.chdir(os.path.dirname(os.path.abspath(__file__)))

print("Calculating stats...")
count, time_seconds = calculate_user_stats()
print(f"Total Play Count: {count}")
print(f"Total Play Time: {time_seconds} seconds")

hours = time_seconds // 3600
minutes = (time_seconds % 3600) // 60
print(f"Formatted Time: {hours}h {minutes}m")
