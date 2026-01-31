import sqlite3
import os
from typing import Any, Dict, Optional

# Store the last query result for reference
_last_query_result: Optional[Dict[str, Any]] = None

# Use absolute path - update this to your actual database location
DATABASE_PATH = "data\metrics.db"

MAX_ROWS = 1000 


def run_sql(query: str) -> Dict[str, Any]:
    """
    Execute a read-only SQL SELECT query and return results.
    """
    global _last_query_result
    
    print(f"[DEBUG] Database path: {DATABASE_PATH}")
    print(f"[DEBUG] Database exists: {os.path.exists(DATABASE_PATH)}")
    print(f"[DEBUG] Executing query: {query}")
    
    if not query.strip().upper().startswith("SELECT"):
        return {"error": "Only SELECT queries are allowed."}
    
    if not os.path.exists(DATABASE_PATH):
        return {"error": f"Database not found at: {DATABASE_PATH}"}    
    
    try:
        conn = sqlite3.connect(DATABASE_PATH)
        cursor = conn.cursor()
        cursor.execute(query)
        
        columns = [description[0] for description in cursor.description]
        rows = cursor.fetchmany(MAX_ROWS)  # Limit rows
        
        conn.close()
        
        _last_query_result = {
            "columns": columns,
            "rows": rows,
            "row_count": len(rows),
            "truncated": len(rows) == MAX_ROWS
        }
        
        print(f"[DEBUG] Query result: {_last_query_result}")
        return _last_query_result
        
    except Exception as e:
        print(f"[DEBUG] Query error: {str(e)}")
        return {"error": str(e)}


def get_last_query_result() -> Optional[Dict[str, Any]]:
    return _last_query_result
