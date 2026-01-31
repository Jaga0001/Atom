import sqlite3
import os

# Configure your database path here (should match db.py)
DATABASE_PATH = "data\metrics.db"  


def load_schema() -> str:
    """
    Load and return the database schema as a formatted string.
    """
    print(f"[DEBUG] Loading schema from: {DATABASE_PATH}")
    print(f"[DEBUG] Database exists: {os.path.exists(DATABASE_PATH)}")
    
    if not os.path.exists(DATABASE_PATH):
        return f"Error: Database not found at: {DATABASE_PATH}"
    
    try:
        conn = sqlite3.connect(DATABASE_PATH)
        cursor = conn.cursor()
        
        cursor.execute("SELECT name FROM sqlite_master WHERE type='table';")
        tables = cursor.fetchall()
        
        print(f"[DEBUG] Found tables: {tables}")
        
        schema_info = []
        
        for (table_name,) in tables:
            cursor.execute(f"PRAGMA table_info({table_name});")
            columns = cursor.fetchall()
            
            column_details = []
            for col in columns:
                col_id, col_name, col_type, not_null, default_val, is_pk = col
                column_details.append(f"  - {col_name} ({col_type})")
            
            schema_info.append(f"Table: {table_name}\n" + "\n".join(column_details))
        
        conn.close()
        
        result = "\n\n".join(schema_info) if schema_info else "No tables found in database."
        print(f"[DEBUG] Schema result: {result}")
        return result
        
    except Exception as e:
        print(f"[DEBUG] Schema error: {str(e)}")
        return f"Error loading schema: {str(e)}"
