from crewai import Crew, Task
from explainer_agent.agent import sql_agent


def run_agent(question: str) -> str:
    """Run the explainer agent with a user question."""
    
    task = Task(
        description=f"""
        User Question: {question}
        
        Instructions:
        1. Use the Firestore Query Tool to fetch data from the 'metrics' collection
        2. Analyze the retrieved data thoroughly
        3. Perform any calculations if needed
        4. Provide a clear, detailed answer to the user's question
        
        Available metrics fields: timestamp, latency, error_rate, cpu, memory, 
        request_time, latency_anomaly, latency_slope, memory_slope, error_trend, risk_score
        """,
        expected_output="A clear, detailed answer to the user's question based on the metrics data.",
        agent=sql_agent
    )
    
    crew = Crew(
        agents=[sql_agent],
        tasks=[task],
        verbose=True
    )
    
    result = crew.kickoff()
    return str(result)


def main():
    """Interactive CLI for the explainer agent."""
    print("=" * 60)
    print("🔥 Firestore Metrics Explainer Agent")
    print("=" * 60)
    print("Ask questions about your metrics data.")
    print("Type 'exit' or 'quit' to stop.\n")
    
    while True:
        question = input("📊 Your Question: ").strip()
        
        if question.lower() in ['exit', 'quit', 'q']:
            print("👋 Goodbye!")
            break
        
        if not question:
            print("⚠️  Please enter a question.\n")
            continue
        
        print("\n🔄 Analyzing...\n")
        
        try:
            answer = run_agent(question)
            print("\n" + "=" * 60)
            print("📈 ANSWER:")
            print("=" * 60)
            print(answer)
            print("=" * 60 + "\n")
        except Exception as e:
            print(f"❌ Error: {e}\n")


if __name__ == "__main__":
    main()