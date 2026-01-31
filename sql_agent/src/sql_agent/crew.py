import os
from crewai import Agent, Crew, Process, Task, LLM
from crewai.project import CrewBase, agent, crew, task
from crewai.agents.agent_builder.base_agent import BaseAgent
from typing import List
from .tools.custom_tool import run_sql_tool, get_schema_tool

@CrewBase
class SqlAgentCrew():
    """SqlAgent crew"""

    agents: List[BaseAgent]
    tasks: List[Task]

    
    @agent
    def sre_system_explainer(self) -> Agent:
        
        llm = LLM(
            model="groq/llama-3.1-8b-instant",
            api_key=os.getenv("GROQ_API_KEY"),
            max_tokens=1024,
        )
        
        return Agent(
            config=self.agents_config["sre_system_explainer"],
            llm=llm,
            tools=[
                get_schema_tool,
                run_sql_tool,
            ],
            verbose=False,
            max_iter=3,
        )
        
    @task
    def system_explanation_task(self) -> Task:
        return Task(
            config=self.tasks_config["system_explanation_task"]  # tasks.yaml
        )

    @crew
    def crew(self) -> Crew:
        """Creates the SRE System Explainer crew"""

        return Crew(
            agents=self.agents,   
            tasks=self.tasks,     
            process=Process.sequential,
            verbose=True
        )
