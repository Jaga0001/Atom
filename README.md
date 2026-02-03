<div align="center">
  <img src="dashboard/assets/logo.png" alt="Atom Logo" width="200"/>
  
  # ATOM
  ### AI-Powered Pre-Incident Detection & Predictive Reliability Platform
  
  [![Python](https://img.shields.io/badge/Python-3.10+-blue.svg)](https://python.org)
  [![Flutter](https://img.shields.io/badge/Flutter-3.0+-02569B.svg)](https://flutter.dev)
  [![Firebase](https://img.shields.io/badge/Firebase-Firestore-FFCA28.svg)](https://firebase.google.com)
  [![CrewAI](https://img.shields.io/badge/CrewAI-Agents-6366F1.svg)](https://crewai.com)
  [![License](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)
</div>

---

## 🎯 Problem Statement

Modern infrastructure teams are stuck in **reactive mode**—waiting for alerts, dashboards to turn red, or users to complain before taking action. Traditional monitoring tools excel at telling you *what broke*, but fail at predicting *what's about to break*.

**ATOM** shifts the paradigm from reactive alerting to **predictive reliability intelligence**, enabling teams to prevent incidents before they impact users.

---

## 💡 Solution Overview

ATOM is an end-to-end predictive observability platform that:

- **Collects** real-time system metrics (CPU, memory, latency, error rates)
- **Analyzes** trends using statistical methods and anomaly detection
- **Forecasts** future metric behavior using ARIMA time-series models
- **Predicts** risk scores with AI-powered agentic reasoning
- **Alerts** proactively with actionable recommendations

<div align="center">
  <img src="https://img.shields.io/badge/Shift-Reactive_→_Predictive-10B981?style=for-the-badge" alt="Shift"/>
</div>

---

## 🏗️ Architecture

```
┌─────────────────────────────────────────────────────────────────────────┐
│                              ATOM Platform                               │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│  ┌─────────────┐    ┌─────────────┐    ┌─────────────┐                 │
│  │  Prometheus │───▶│   Metrics   │───▶│  Firebase   │                 │
│  │   (Source)  │    │  Collector  │    │  Firestore  │                 │
│  └─────────────┘    └─────────────┘    └──────┬──────┘                 │
│                                               │                         │
│                     ┌─────────────────────────┼─────────────────────┐   │
│                     │                         ▼                     │   │
│  ┌─────────────┐    │  ┌─────────────┐  ┌──────────┐               │   │
│  │   CrewAI    │◀───┼──│  Forecast   │  │ Flutter  │               │   │
│  │  SQL Agent  │    │  │  Pipeline   │  │Dashboard │               │   │
│  └─────────────┘    │  │  (ARIMA)    │  └──────────┘               │   │
│         │           │  └─────────────┘       ▲                     │   │
│         ▼           │         │              │                     │   │
│  ┌─────────────┐    │         └──────────────┘                     │   │
│  │  SQLite DB  │    │       Real-time Updates                      │   │
│  │  (Metrics)  │    └───────────────────────────────────────────────┘   │
│  └─────────────┘                                                        │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
```

---

## ✨ Key Features

| Feature | Description |
|---------|-------------|
| 📊 **Real-time Monitoring** | Live metrics visualization with interactive charts |
| 🔮 **AI Forecasting** | ARIMA-based prediction of CPU, memory, latency & error rates |
| ⚠️ **Risk Scoring** | Dynamic risk assessment with 0-100 scale |
| 🤖 **Agentic Chat** | Natural language queries via CrewAI-powered SQL agent |
| 📈 **Trend Analysis** | Slope detection for latency, memory & error patterns |
| 🎯 **Actionable Insights** | Contextual recommendations based on system state |
| ⏱️ **Hourly Forecasts** | Automated pipeline generating 50-point predictions |

---

## 🛠️ Tech Stack

### Backend
- **Python 3.10+** - Core runtime
- **Flask** - REST API server
- **Firebase Admin SDK** - Firestore integration
- **Prometheus Client** - Metrics collection
- **ARIMA (pmdarima)** - Time-series forecasting
- **CrewAI** - Agentic AI framework
- **Groq** - LLM inference (Llama 3.3)

### Frontend
- **Flutter 3.0+** - Cross-platform dashboard
- **fl_chart** - Data visualization
- **Cloud Firestore** - Real-time data sync
- **Google Fonts** - Typography

### Infrastructure
- **Firebase Firestore** - Metrics & forecast storage
- **Prometheus** - Metrics source (optional)
- **SQLite** - Local metrics database for SQL agent

---

## 📁 Project Structure

```
Atom/
├── server/                    # Backend services
│   ├── app.py                 # Flask API server
│   ├── metrics_collector.py   # Prometheus → Firestore collector
│   ├── forecast_pipeline.py   # ARIMA forecasting engine
│   ├── models/                # Pre-trained ARIMA models
│   │   ├── latency_arima_model.pkl
│   │   ├── cpu_arima_model.pkl
│   │   ├── memory_arima_model.pkl
│   │   ├── error_rate_arima_model.pkl
│   │   └── risk_score_arima_model.pkl
│   └── key.json               # Firebase service account
│
├── sql_agent/                 # CrewAI SQL Agent
│   └── src/sql_agent/
│       ├── main.py            # Agent entry point
│       ├── crew.py            # CrewAI crew definition
│       ├── db.py              # SQLite database interface
│       ├── schema.py          # Database schema loader
│       └── tools/
│           └── custom_tool.py # SQL execution tools
│
├── dashboard/                 # Flutter frontend
│   ├── lib/
│   │   ├── main.dart          # App entry point
│   │   ├── firebase_options.dart
│   │   └── pages/
│   │       ├── dashboard_page.dart  # Main dashboard
│   │       └── analytics_page.dart  # Advanced analytics
│   └── assets/
│       └── logo.png
│
└── data/                      # Data files
    └── metrics.db             # SQLite metrics database
```

---

## 🚀 Getting Started

### Prerequisites

- Python 3.10+
- Flutter 3.0+
- Firebase project with Firestore enabled
- Groq API key (for LLM features)

### 1. Clone the Repository

```bash
git clone https://github.com/your-team/atom.git
cd atom
```

### 2. Backend Setup

```bash
cd server

# Create virtual environment
python -m venv venv
source venv/bin/activate  # On Windows: venv\Scripts\activate

# Install dependencies
pip install flask flask-cors groq firebase-admin prometheus-client numpy pandas pmdarima

# Configure Firebase
# Place your Firebase service account key as key.json

# Set environment variables
export GROQ_API_KEY=your_groq_api_key

# Run the server
python app.py
```

### 3. SQL Agent Setup

```bash
cd sql_agent

# Install with uv (recommended)
uv sync

# Or with pip
pip install crewai groq

# Set environment variables
export GROQ_API_KEY=your_groq_api_key

# Run the agent
python -m sql_agent.main "What is the average latency?"
```

### 4. Dashboard Setup

```bash
cd dashboard

# Get Flutter dependencies
flutter pub get

# Configure Firebase
flutterfire configure

# Run the app
flutter run -d chrome  # For web
flutter run -d windows # For desktop
```

---

## 🔧 Configuration

### Environment Variables

| Variable | Description | Required |
|----------|-------------|----------|
| `GROQ_API_KEY` | Groq API key for LLM inference | Yes |
| `PROMETHEUS_URL` | Prometheus server URL | Optional |

### Firebase Setup

1. Create a Firebase project at [console.firebase.google.com](https://console.firebase.google.com)
2. Enable Firestore Database
3. Generate a service account key (Project Settings → Service Accounts)
4. Save as `server/key.json`
5. Run `flutterfire configure` in the dashboard directory

---

## 📊 API Endpoints

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/chat` | POST | Chat with AI assistant |
| `/metrics` | GET | Fetch latest metrics |
| `/forecast` | GET | Get latest forecast |
| `/forecast/run` | POST | Trigger manual forecast |

### Example: Chat Request

```bash
curl -X POST http://localhost:5000/chat \
  -H "Content-Type: application/json" \
  -d '{"message": "What is the current risk score?"}'
```

---

## 📸 Screenshots

<div align="center">
  <table>
    <tr>
      <td align="center">
        <img src="docs/dashboard.png" width="400" alt="Dashboard"/>
        <br/>
        <em>Main Dashboard</em>
      </td>
      <td align="center">
        <img src="docs/analytics.png" width="400" alt="Analytics"/>
        <br/>
        <em>Advanced Analytics</em>
      </td>
    </tr>
    <tr>
      <td align="center">
        <img src="docs/forecast.png" width="400" alt="Forecasting"/>
        <br/>
        <em>Risk Forecasting</em>
      </td>
      <td align="center">
        <img src="docs/chat.png" width="400" alt="AI Chat"/>
        <br/>
        <em>AI Assistant</em>
      </td>
    </tr>
  </table>
</div>

---

## 🧪 How It Works

### 1. Metrics Collection
The `MetricsCollector` queries Prometheus (or generates synthetic data) every 10 minutes, computing:
- Raw metrics: CPU, memory, latency, error rate
- Derived metrics: slopes, trends, anomaly flags
- Risk score: weighted combination of all factors

### 2. Forecasting Pipeline
Hourly, the `ForecastPipeline`:
- Loads pre-trained ARIMA models for each metric
- Generates 50-point forecasts (8+ hours ahead)
- Stores predictions in Firestore for real-time dashboard updates

### 3. Risk Scoring Algorithm

```python
risk_score = 0
risk_score += 30 if latency_anomaly else 0
risk_score += min(error_rate * 10, 30)
risk_score += min((memory / 100) * 20, 20)
risk_score += min(abs(memory_slope) * 10, 20)
return min(risk_score, 100)
```

### 4. Agentic SQL Queries
The CrewAI SQL Agent allows natural language queries:
```
User: "Show me the top 5 highest latency events"
Agent: SELECT * FROM metrics ORDER BY latency DESC LIMIT 5
```

---

## 👥 Team

| Member | Role |
|--------|------|
| **Jagavantha PA** | Full Stack Developer |
| **Pranov JB & Karunakaran M** | ML Engineer |
| **Yuva Krishna I** | Frontend Developer |

---

## 🏆 BeachHack 2025

This project was built during **BeachHack 2025** hackathon.

**Problem Statement:** Pre-Incident Detection AI  
**Track:** AI/ML & DevOps

---

## 📜 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

---

<div align="center">
  <strong>Built with ❤️ for predictive reliability</strong>
  <br/>
  <em>Shifting from reactive alerts to proactive intelligence</em>
</div>

