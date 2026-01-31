from fastapi import FastAPI, HTTPException
from pydantic import BaseModel

from sql_agent.crew import SqlAgentCrew

app = FastAPI(
    title="SRE System Explainer API",
    description="Ask questions about system behavior using historical metrics data",
    version="1.0"
)

class QueryRequest(BaseModel):
    question: str


class QueryResponse(BaseModel):
    question: str
    answer: str


@app.post("/query", response_model=QueryResponse)
def query_system(q: QueryRequest):
    """
    Accepts a natural-language SRE question and returns
    a data-backed explanation from the CrewAI system.
    """
    try:
        crew = SqlAgentCrew().crew()

        result = crew.kickoff(
            inputs={
                "question": q.question
            }
        )

        return {
                "question": q.question,
              "answer": str(result)
        }
    except Exception as e:
        raise HTTPException(
            status_code=500,
              detail=f"Failed to process query: {str(e)}"
        )
