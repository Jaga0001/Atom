from crewai import Task, Crew

import sql_agent

task = Task(
    description=(
        "User question: {question}\n"
        "Use Firestore data to compute the answer."
    ),
    agent=sql_agent,
    expected_output="Clear, concise answer with reasoning"
)

crew = Crew(
    agents=[sql_agent],
    tasks=[task]
)

result = crew.kickoff(
    inputs={"question": "What are the most frequent error types?"}
)

print(result)
