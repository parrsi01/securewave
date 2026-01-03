from fastapi import FastAPI

app = FastAPI()

@app.get("/")
def read_root():
    return {"status": "ok", "message": "Minimal app works"}

@app.get("/health")
def health():
    return {"status": "healthy"}
