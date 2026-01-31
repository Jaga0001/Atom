# c:\Karan program\Atom\convert_metrics_to_db.py
import sqlite3
import csv
import os

# Paths
csv_path = r"c:\Karan program\Atom\training_model\metrics.csv"
db_path = r"c:\Karan program\Atom\sql_agent\data\metrics.db"

# Ensure data folder exists
os.makedirs(os.path.dirname(db_path), exist_ok=True)

# Connect to new database
conn = sqlite3.connect(db_path)
cursor = conn.cursor()

# Read CSV and create table
with open(csv_path, 'r') as f:
    reader = csv.reader(f)
    headers = next(reader)
    
    # Create table with all columns as TEXT (adjust types as needed)
    columns = ', '.join([f'"{h}" TEXT' for h in headers])
    cursor.execute(f'CREATE TABLE IF NOT EXISTS metrics ({columns})')
    
    # Insert data
    placeholders = ', '.join(['?' for _ in headers])
    for row in reader:
        cursor.execute(f'INSERT INTO metrics VALUES ({placeholders})', row)

conn.commit()
conn.close()

print(f"Database created at: {db_path}")