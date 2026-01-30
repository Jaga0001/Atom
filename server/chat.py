from flask import Flask, request, jsonify
from flask_cors import CORS
from groq import Groq

app = Flask(__name__)
CORS(app)

# Configure your Groq API key
API_KEY = "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"
client = Groq(api_key=API_KEY)

# System prompt for pre-incident forecasting assistant
SYSTEM_PROMPT = """You are an AI-powered pre-incident detection assistant specializing in:

1. **Multi-Metric System State Monitoring**: Analyzing latency, error rates, memory usage, and request volume to assess system health.

2. **Baseline Learning & Trajectory Forecasting**: Learning normal operating baselines and forecasting metric behavior to identify unsafe trajectories.

3. **Predictive Incident Warnings**: Generating early warnings with:
   - Likelihood of impending outage
   - Estimated time-to-failure
   - Clear explanations of contributing metric trends

4. **Shadow Mode Evaluation**: Supporting passive evaluation alongside existing monitoring systems.

Help ML Engineers, SREs, Backend Architects, and Platform Engineers shift from reactive alerting to predictive reliability intelligence. Provide actionable insights, reduce false positives, and detect slow degradation patterns early."""

# Conversation history
history = [{"role": "system", "content": SYSTEM_PROMPT}]

def chat_with_groq(user_input):
    """Send a message to Groq and get a response."""
    history.append({"role": "user", "content": user_input})
    
    response = client.chat.completions.create(
        model="llama-3.3-70b-versatile",
        messages=history,
        temperature=0.7,
        max_tokens=2048
    )
    
    assistant_message = response.choices[0].message.content
    history.append({"role": "assistant", "content": assistant_message})
    
    return assistant_message

@app.route('/chat', methods=['POST'])
def chat():
    """Single endpoint for chat interactions."""
    try:
        data = request.get_json()
        user_input = data.get('message', '').strip()
        
        if not user_input:
            return jsonify({'error': 'Message is required'}), 400
        
        response = chat_with_groq(user_input)
        return jsonify({'response': response})
    
    except Exception as e:
        return jsonify({'error': str(e)}), 500

if __name__ == "__main__":
    app.run(host='0.0.0.0', port=5000, debug=True)
