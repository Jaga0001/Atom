#!/usr/bin/env python
import sys
import warnings

from sql_agent.crew import SqlAgentCrew

warnings.filterwarnings("ignore", category=SyntaxWarning, module="pysbd")


def run():
    """
    Run the crew with a question from command line.
    """
    question = sys.argv[1]

    inputs = {
        "question": question
    }

    result = SqlAgentCrew().crew().kickoff(inputs=inputs)
    print("\n--- RESULT ---\n")
    print(result)


if __name__ == "__main__":
    run()
