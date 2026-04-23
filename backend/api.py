import os
from fastapi import FastAPI

app = FastAPI()

@app.get("/status")
def status():
    return {"pronto": True, "teste": "API funcionando!"}