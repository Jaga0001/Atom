from flask import Flask, request, jsonify
from explainer_agent.main import run_agent
from flask_cors import CORS

app = Flask(__name__)
CORS(app)


@app.route('/chat', methods=['POST'])
def chat():
    """Simple chat endpoint for metrics questions."""
    try:
        data = request.get_json()
        question = data.get('question', '').strip()
        
        if not question:
            return jsonify({"error": "Question required"}), 400
        
        answer = run_agent(question)
        
        return jsonify({
            "answer": answer
        }), 200
        
    except Exception as e:
        return jsonify({"error": str(e)}), 500


if __name__ == '__main__':
    import os
    port = int(os.environ.get('PORT', 5000))
    app.run(debug=False, host='0.0.0.0', port=port)