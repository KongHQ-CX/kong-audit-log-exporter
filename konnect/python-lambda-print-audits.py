#!/bin/python3

import json
from flask import Flask, request, Response

app = Flask(__name__)

def create_response(path, method, headers):
  
  response = {
    "created": True
  }

  return Response(json.dumps(response), 200, mimetype='application/json')

@app.route('/', defaults={'path': ''}, methods = ['GET', 'POST'])
@app.route('/<path:path>', methods = ['GET', 'POST'])
def catch_all(path):
  print(request.get_data().decode().replace("\n", ""))
  return create_response(path, request.method, request.headers)

if __name__ == '__main__':
  app.run(host='0.0.0.0', port=8080)
