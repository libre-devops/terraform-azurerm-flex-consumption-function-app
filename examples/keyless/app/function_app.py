"""A FastAPI hello world served through Azure Functions' ASGI bridge.

The Functions host hands every HTTP request to FastAPI (see host.json, which clears the host's
own /api route prefix so FastAPI owns the full path), so this file is plain FastAPI: add routers,
dependencies, and models exactly as you would anywhere else.
"""

import azure.functions as func
from fastapi import FastAPI

fastapi_app = FastAPI(title="Libre DevOps hello world")


@fastapi_app.get("/api/hello")
async def hello():
    return {"message": "Hello from FastAPI on Azure Functions Flex Consumption"}


@fastapi_app.get("/api/health")
async def health():
    return {"status": "ok"}


app = func.AsgiFunctionApp(app=fastapi_app, http_auth_level=func.AuthLevel.ANONYMOUS)
