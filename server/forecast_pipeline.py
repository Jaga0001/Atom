import pickle
import pandas as pd
import numpy as np
from datetime import datetime, timedelta
import threading
import time
import os
import firebase_admin
from firebase_admin import credentials, firestore

class ForecastPipeline:
    """
    AI Pipeline to forecast next 50 values of server metrics.
    Runs every hour using pre-trained ARIMA models (no model updates).
    """
    
    TARGET_METRICS = ["latency", "cpu", "memory", "error_rate", "risk_score"]
    FORECAST_STEPS = 50
    ACTUAL_STEPS = 50  # Number of recent actual values to fetch
    PIPELINE_INTERVAL = 3600  # 1 hour in seconds
    
    def __init__(self, credentials_path="key.json", models_dir="../models"):
        self.credentials_path = credentials_path
        self.models_dir = models_dir
        self.models = {}
        self.db = None
        self.is_running = False
        
        self.init_firestore()
        self.load_models()
    
    def init_firestore(self):
        """Initialize Firestore connection"""
        try:
            if not firebase_admin._apps:
                cred = credentials.Certificate(self.credentials_path)
                firebase_admin.initialize_app(cred)
            self.db = firestore.client()
            print("✅ Firestore initialized")
        except Exception as e:
            print(f"❌ Firestore error: {e}")
            raise
    
    def load_models(self):
        """Load pre-trained ARIMA models"""
        print("\n📦 Loading ARIMA models...")
        
        for metric in self.TARGET_METRICS:
            model_path = os.path.join(os.path.dirname(__file__), "models", f"{metric}_arima_model.pkl")
            try:
                with open(model_path, 'rb') as f:
                    self.models[metric] = pickle.load(f)
                print(f"   ✅ Loaded {metric.upper()}")
            except Exception as e:
                print(f"   ❌ Error loading {metric}: {e}")
        
        print(f"📊 Loaded {len(self.models)}/{len(self.TARGET_METRICS)} models")
    
    def fetch_actual_values(self, metric, limit=50):
        """Fetch recent actual metric values from Firestore."""
        try:
            # Query the metrics collection for recent values
            docs = (self.db.collection('metrics')
                    .order_by('timestamp', direction=firestore.Query.DESCENDING)
                    .limit(limit)
                    .stream())
            
            values = []
            timestamps = []
            
            for doc in docs:
                data = doc.to_dict()
                if metric in data:
                    values.append(data[metric])
                    # Handle both datetime and string timestamps
                    ts = data.get('timestamp')
                    if hasattr(ts, 'isoformat'):
                        timestamps.append(ts.isoformat())
                    else:
                        timestamps.append(str(ts))
            
            # Reverse to get chronological order
            values.reverse()
            timestamps.reverse()
            
            return {'values': values, 'timestamps': timestamps}
        except Exception as e:
            print(f"   ⚠️ Could not fetch actual {metric}: {e}")
            return {'values': [], 'timestamps': []}
    
    def generate_forecasts(self):
        """Generate forecasts for all metrics using pre-trained models."""
        forecasts = {}
        forecast_time = datetime.now()
        
        print(f"\n🔮 Generating forecasts - {forecast_time.isoformat()}")
        
        for metric in self.TARGET_METRICS:
            if metric not in self.models:
                continue
            
            try:
                # Fetch actual values
                actual_data = self.fetch_actual_values(metric, self.ACTUAL_STEPS)
                
                # Forecast using pre-trained model
                forecast_values = self.models[metric].predict(n_periods=self.FORECAST_STEPS)
                
                # Generate future timestamps (10-min intervals)
                future_timestamps = [
                    forecast_time + timedelta(minutes=10 * (i + 1))
                    for i in range(self.FORECAST_STEPS)
                ]
                
                forecasts[metric] = {
                    'actual': {
                        'values': actual_data['values'],
                        'timestamps': actual_data['timestamps']
                    },
                    'forecast': {
                        'values': forecast_values.tolist(),
                        'timestamps': [ts.isoformat() for ts in future_timestamps]
                    }
                }
                
                actual_vals = actual_data['values']
                if actual_vals:
                    print(f"   ✅ {metric.upper()}: actual={len(actual_vals)} pts ({min(actual_vals):.2f}-{max(actual_vals):.2f}), forecast={min(forecast_values):.2f}-{max(forecast_values):.2f}")
                else:
                    print(f"   ✅ {metric.upper()}: no actual data, forecast={min(forecast_values):.2f}-{max(forecast_values):.2f}")
                
            except Exception as e:
                print(f"   ❌ {metric}: {e}")
        
        return forecasts
    
    def save_forecasts(self, forecasts):
        """Save forecasts to Firestore."""
        try:
            doc = {
                'generated_at': datetime.now(),
                'forecast_steps': self.FORECAST_STEPS,
                'metrics': forecasts
            }
            
            # Update only latest
            self.db.collection('forecasts').document('latest').set(doc)
            print("💾 Latest forecast saved to Firestore")
            
        except Exception as e:
            print(f"❌ Save error: {e}")
    
    def run_pipeline(self):
        """Execute forecast pipeline."""
        print("\n" + "=" * 50)
        print(f"🚀 FORECAST PIPELINE - {datetime.now().isoformat()}")
        print("=" * 50)
        
        forecasts = self.generate_forecasts()
        
        if forecasts:
            self.save_forecasts(forecasts)
            print("✅ Pipeline completed")
            return forecasts
        
        return None
    
    def start_scheduled_pipeline(self):
        """Start hourly forecast pipeline."""
        if self.is_running:
            return
        
        self.is_running = True
        
        def loop():
            self.run_pipeline()  # Run immediately
            while self.is_running:
                time.sleep(self.PIPELINE_INTERVAL)
                if self.is_running:
                    self.run_pipeline()
        
        threading.Thread(target=loop, daemon=True).start()
        print("⏰ Forecast pipeline started (runs every 1 hour)")
    
    def stop_pipeline(self):
        self.is_running = False
    
    def get_latest_forecast(self):
        """Get latest forecast from Firestore."""
        try:
            doc = self.db.collection('forecasts').document('latest').get()
            return doc.to_dict() if doc.exists else None
        except:
            return None


if __name__ == "__main__":
    pipeline = ForecastPipeline(credentials_path="key.json", models_dir="../models")
    result = pipeline.run_pipeline()
    
    if result:
        for metric, data in result.items():
            actual = data['actual']['values']
            forecast = data['forecast']['values']
            actual_info = f"actual: {len(actual)} pts" if actual else "no actual data"
            print(f"{metric}: {actual_info}, forecast: min={min(forecast):.2f}, max={max(forecast):.2f}")