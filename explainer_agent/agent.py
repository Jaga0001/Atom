from crewai import Agent
from explainer_agent.tools import FirestoreQueryTool
from crewai import LLM
from dotenv import load_dotenv
import os

load_dotenv()

llm = LLM(
    model="gemini/gemini-2.5-flash",
    api_key=os.getenv("GOOGLE_API_KEY"),
    temperature=0.2
)

sql_agent = Agent(
    role="Firestore Metrics Analyst",
    goal="Answer user questions by analyzing Firestore metrics data including timestamp, latency, error_rate, cpu, memory, request_time, latency_anomaly, latency_slope, memory_slope, error_trend, and risk_score",
    backstory=(
        "You are an expert data analyst specializing in system metrics. "
        "You can query Firestore database, analyze metrics data, perform calculations, "
        "identify trends, detect anomalies, and provide clear explanations. "
        "When asked about specific metrics, you fetch real data and provide accurate analysis."
    ),
    tools=[FirestoreQueryTool()],
    llm=llm,  # <-- Added this!
    verbose=True
)
