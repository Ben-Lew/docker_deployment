import sys

def handler(event, context):
    return {
        "statusCode": 200,
        "body": f"Hello from Lambda running on Python {sys.version}!"
    }