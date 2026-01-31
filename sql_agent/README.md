# SQL Agent

An AI-powered SQL agent built with CrewAI.

## Packages

- crewai
- groq

## Installation

```bash
uv sync
```

## Run

```bash
uvicorn server:app --reload
```

## Environment Variables

Set your Groq API key:

```bash
export GROQ_API_KEY=your_api_key_here
```

On Windows:
```cmd
set GROQ_API_KEY=your_api_key_here
```
