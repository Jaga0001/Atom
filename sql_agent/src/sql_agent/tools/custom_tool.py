from crewai.tools import tool
from typing import Any, Dict
import json

from ..db import run_sql
from ..schema import load_schema


def truncate_result(result: Any, max_length: int = 2000) -> str:
    """Truncate result to avoid context overflow."""
    text = json.dumps(result) if isinstance(result, dict) else str(result)
    if len(text) > max_length:
        return text[:max_length] + "... [truncated]"
    return text


@tool("run_sql")
def run_sql_tool(query: str) -> str:
    """
    Execute a read-only SQL SELECT query on the system metrics database
    and return the result rows and column names.
    
    Args:
        query: A read-only SQL SELECT query to execute on the metrics database.
    """
    result = run_sql(query)
    return truncate_result(result)


@tool("get_schema_info")
def get_schema_tool(request: str = "all") -> str:
    """
    Retrieve the database schema, including table names and columns,
    to help understand what data is available.
    
    Args:
        request: What schema info to retrieve. Use 'all' to get everything.
    """
    result = load_schema()
    return truncate_result(result)
