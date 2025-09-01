import json
from src.lambda_function import handler

def test_handler_returns_200():
    resp = handler({"hello": "world"}, None)
    assert resp["statusCode"] == 200
    body = json.loads(resp["body"])
    assert "message" in body