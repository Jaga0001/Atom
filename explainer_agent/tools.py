from crewai.tools import BaseTool
from typing import Type
from pydantic import BaseModel, Field
import firebase_admin
from firebase_admin import credentials, firestore


# Initialize Firebase ONCE
if not firebase_admin._apps:
    cred = credentials.Certificate("key.json")
    firebase_admin.initialize_app(cred)

db = firestore.client()


class FirestoreQueryInput(BaseModel):
    """Input schema for FirestoreQueryTool."""
    collection: str = Field(description="The Firestore collection to query (e.g., 'metrics')")
    limit: int = Field(default=20, description="Maximum number of documents to return")


class FirestoreQueryTool(BaseTool):
    name: str = "Firestore Query Tool"
    description: str = "Query Firestore collections and return structured data. Use this to fetch metrics data including timestamp, latency, error_rate, cpu, memory, request_time, latency_anomaly, latency_slope, memory_slope, error_trend, and risk_score."
    args_schema: Type[BaseModel] = FirestoreQueryInput

    def _run(self, collection: str, limit: int = 20) -> list:
        docs = (
            db.collection(collection)
            .limit(limit)
            .stream()
        )

        results = []
        for doc in docs:
            item = doc.to_dict()
            item["id"] = doc.id
            results.append(item)

        return results
